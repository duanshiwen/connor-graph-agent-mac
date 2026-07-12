import Foundation
import ConnorGraphSearch
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum OpenAICompatibleAPIKeyHeaderKind: String, Sendable, Equatable, Codable, CaseIterable {
    case bearer
    case apiKey = "api-key"
}

public struct OpenAICompatibleConfig: Sendable, Equatable {
    public var baseURL: URL
    public var apiKey: String
    public var model: String
    public var extraHeaders: [String: String]
    public var apiKeyHeaderKind: OpenAICompatibleAPIKeyHeaderKind
    public var reasoningEffort: String?
    public var requestTimeout: TimeInterval
    public var explicitVisionSupport: Bool?

    public init(
        baseURL: URL,
        apiKey: String,
        model: String,
        extraHeaders: [String: String] = [:],
        apiKeyHeaderKind: OpenAICompatibleAPIKeyHeaderKind = .bearer,
        reasoningEffort: String? = nil,
        explicitVisionSupport: Bool? = nil
    ) {
        self.init(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            extraHeaders: extraHeaders,
            apiKeyHeaderKind: apiKeyHeaderKind,
            reasoningEffort: reasoningEffort,
            requestTimeout: 300,
            explicitVisionSupport: explicitVisionSupport
        )
    }

    public init(
        baseURL: URL,
        apiKey: String,
        model: String,
        extraHeaders: [String: String] = [:],
        apiKeyHeaderKind: OpenAICompatibleAPIKeyHeaderKind = .bearer,
        reasoningEffort: String? = nil,
        requestTimeout: TimeInterval,
        explicitVisionSupport: Bool? = nil
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.extraHeaders = extraHeaders
        self.apiKeyHeaderKind = apiKeyHeaderKind
        self.reasoningEffort = reasoningEffort
        self.requestTimeout = requestTimeout
        self.explicitVisionSupport = explicitVisionSupport
    }

    public var requestModel: String {
        model
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? model.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func fromEnvironment(_ environment: [String: String]) throws -> OpenAICompatibleConfig {
        guard let apiKey = environment["CONNOR_LLM_API_KEY"], !apiKey.isEmpty else {
            throw OpenAICompatibleProviderError.missingAPIKey
        }
        let baseURLString = environment["CONNOR_LLM_BASE_URL"] ?? "https://api.openai.com/v1"
        guard let baseURL = URL(string: baseURLString) else {
            throw OpenAICompatibleProviderError.invalidBaseURL(baseURLString)
        }
        let model = environment["CONNOR_LLM_MODEL"] ?? "gpt-4o-mini"
        return OpenAICompatibleConfig(baseURL: baseURL, apiKey: apiKey, model: model)
    }

    public static func optionalFromEnvironment(_ environment: [String: String]) throws -> OpenAICompatibleConfig? {
        guard let apiKey = environment["CONNOR_LLM_API_KEY"], !apiKey.isEmpty else {
            return nil
        }
        return try fromEnvironment(environment)
    }
}

public enum OpenAICompatibleProviderError: Error, Equatable, Sendable {
    case missingAPIKey
    case invalidBaseURL(String)
    case invalidResponse
    case httpStatus(Int, message: String?)
    case missingAssistantMessage
    case unsupportedVisionInput(model: String, reason: String)
}

extension OpenAICompatibleProviderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Missing OpenAI-compatible API key."
        case let .invalidBaseURL(value):
            return "Invalid OpenAI-compatible base URL: \(value)"
        case .invalidResponse:
            return "OpenAI-compatible provider returned an invalid response."
        case let .httpStatus(code, message):
            if let message, !message.isEmpty {
                return "HTTP \(code): \(message)"
            }
            return "HTTP \(code)"
        case .missingAssistantMessage:
            return "OpenAI-compatible provider response did not include an assistant message."
        case let .unsupportedVisionInput(model, reason):
            return "OpenAI-compatible model \(model) cannot receive image input: \(reason)"
        }
    }
}

public struct LLMProviderHealthCheckResult: Sendable, Equatable {
    public var ok: Bool
    public var model: String
    public var message: String

    public init(ok: Bool, model: String, message: String) {
        self.ok = ok
        self.model = model
        self.message = message
    }
}

public struct AgentHTTPRequest: Sendable, Equatable {
    public var url: URL
    public var method: String
    public var headers: [String: String]
    public var body: Data
    public var timeoutInterval: TimeInterval?

    public init(url: URL, method: String, headers: [String: String], body: Data, timeoutInterval: TimeInterval? = nil) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.timeoutInterval = timeoutInterval
    }
}

public struct AgentHTTPResponse: Sendable, Equatable {
    public var statusCode: Int
    public var body: Data

    public init(statusCode: Int, body: Data) {
        self.statusCode = statusCode
        self.body = body
    }
}

public protocol AgentHTTPClient: Sendable {
    mutating func send(_ request: AgentHTTPRequest) async throws -> AgentHTTPResponse
}

public struct URLSessionAgentHTTPClient: AgentHTTPClient, Sendable, Equatable {
    public init() {}

    public mutating func send(_ request: AgentHTTPRequest) async throws -> AgentHTTPResponse {
        var urlRequest = request.timeoutInterval.map { URLRequest(url: request.url, timeoutInterval: $0) } ?? URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAICompatibleProviderError.invalidResponse
        }
        return AgentHTTPResponse(statusCode: httpResponse.statusCode, body: data)
    }
}

public struct OpenAICompatibleProvider<Client: AgentHTTPClient>: LLMProvider, StreamingAgentModelProvider, Sendable {
    public var config: OpenAICompatibleConfig
    public var httpClient: Client
    public var sseClient: (any AgentSSEHTTPClient)?

    public var modelID: String { config.requestModel }
    public var capabilityProfile: AgentModelCapabilityProfile {
        AgentModelCapabilityKernel.profile(providerKind: .openAICompatible, modelID: config.requestModel, explicitVisionSupport: config.explicitVisionSupport)
    }
    public var capabilities: AgentModelCapabilities { capabilityProfile.agentCapabilities }

    public init(config: OpenAICompatibleConfig, httpClient: Client) {
        self.init(config: config, httpClient: httpClient, sseClient: nil)
    }

    public init(config: OpenAICompatibleConfig, httpClient: Client, sseClient: (any AgentSSEHTTPClient)?) {
        self.config = config
        self.httpClient = httpClient
        self.sseClient = sseClient
    }

    public func complete(prompt: String, context: AgentContext) async throws -> LLMResponse {
        var client = httpClient
        let request = try makeRequest(prompt: prompt, context: context)
        let response = try await client.send(request)
        if response.statusCode < 200 || response.statusCode >= 300 {
            throw OpenAICompatibleProviderError.httpStatus(response.statusCode, message: Self.errorMessage(from: response.body))
        }
        let text = try parseResponse(response.body)
        return LLMResponse(text: text, citations: context.items.map(\.sourceID))
    }

    public func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse {
        try await completeWithTools(request)
    }

    private static var visionDegradationWarning: String { "⚠️ 当前模型不支持图片输入，已自动发送文字内容。图片内容已忽略。" }

    public func completeWithTools(_ modelRequest: AgentModelRequest) async throws -> AgentModelResponse {
        var client = httpClient
        do {
            let request = try makeToolCallingRequest(modelRequest)
            let response = try await client.send(request)
            if response.statusCode < 200 || response.statusCode >= 300 {
                throw OpenAICompatibleProviderError.httpStatus(response.statusCode, message: Self.errorMessage(from: response.body))
            }
            return try parseToolCallingResponse(response.body)
        } catch OpenAICompatibleProviderError.unsupportedVisionInput {
            guard modelRequest.containsImageInput else { throw OpenAICompatibleProviderError.unsupportedVisionInput(model: capabilityProfile.modelID, reason: "vision not supported") }
            let stripped = modelRequest.stripImageContent()
            let request = try makeToolCallingRequest(stripped)
            let response = try await client.send(request)
            if response.statusCode < 200 || response.statusCode >= 300 {
                throw OpenAICompatibleProviderError.httpStatus(response.statusCode, message: Self.errorMessage(from: response.body))
            }
            var result = try parseToolCallingResponse(response.body)
            result.warnings.append(Self.visionDegradationWarning)
            return result
        }
    }

    public func streamComplete(_ request: AgentModelRequest) -> AsyncThrowingStream<AgentModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let sseClient else {
                        continuation.yield(.completed(try await complete(request)))
                        continuation.finish()
                        return
                    }
                    do {
                        let httpRequest = try makeToolCallingRequest(request, stream: true)
                        let frames = try await sseClient.stream(httpRequest)
                        var accumulator = OpenAIChatCompletionStreamAccumulator()
                        for try await frame in frames {
                            for payload in OpenAISSEParser.payloads(from: frame) {
                                guard payload != "[DONE]" else { continue }
                                let chunk = try JSONDecoder().decode(OpenAIChatCompletionStreamChunk.self, from: Data(payload.utf8))
                                for event in accumulator.append(chunk: chunk, rawJSON: payload) {
                                    continuation.yield(event)
                                }
                            }
                        }
                        continuation.yield(.completed(accumulator.response()))
                        continuation.finish()
                    } catch OpenAICompatibleProviderError.unsupportedVisionInput {
                        guard request.containsImageInput else { throw OpenAICompatibleProviderError.unsupportedVisionInput(model: capabilityProfile.modelID, reason: "vision not supported") }
                        let stripped = request.stripImageContent()
                        let httpRequest = try makeToolCallingRequest(stripped, stream: true)
                        let frames = try await sseClient.stream(httpRequest)
                        var accumulator = OpenAIChatCompletionStreamAccumulator()
                        for try await frame in frames {
                            for payload in OpenAISSEParser.payloads(from: frame) {
                                guard payload != "[DONE]" else { continue }
                                let chunk = try JSONDecoder().decode(OpenAIChatCompletionStreamChunk.self, from: Data(payload.utf8))
                                for event in accumulator.append(chunk: chunk, rawJSON: payload) {
                                    continuation.yield(event)
                                }
                            }
                        }
                        var finalResponse = accumulator.response()
                        finalResponse.warnings.append(Self.visionDegradationWarning)
                        continuation.yield(.completed(finalResponse))
                        continuation.finish()
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func healthCheck() async throws -> LLMProviderHealthCheckResult {
        var client = httpClient
        let request = try makeHealthCheckRequest()
        let response = try await client.send(request)
        if response.statusCode < 200 || response.statusCode >= 300 {
            throw OpenAICompatibleProviderError.httpStatus(response.statusCode, message: Self.errorMessage(from: response.body))
        }
        let text = try parseResponse(response.body)
        return LLMProviderHealthCheckResult(
            ok: !text.isEmpty,
            model: config.requestModel,
            message: "Connection OK: \(config.requestModel)"
        )
    }

    private func makeHealthCheckRequest() throws -> AgentHTTPRequest {
        let endpoint = config.baseURL.appendingPathComponent("chat/completions")
        let body = OpenAIChatCompletionRequest(
            model: config.requestModel,
            messages: [OpenAIChatMessage(role: "user", content: "Reply with exactly: OK")],
            temperature: nil
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return AgentHTTPRequest(
            url: endpoint,
            method: "POST",
            headers: requestHeaders(),
            body: try encoder.encode(body),
            timeoutInterval: config.requestTimeout
        )
    }

    private func makeRequest(prompt: String, context: AgentContext) throws -> AgentHTTPRequest {
        let endpoint = config.baseURL.appendingPathComponent("chat/completions")
        let body = OpenAIChatCompletionRequest(
            model: config.requestModel,
            messages: [
                OpenAIChatMessage(role: "system", content: systemPrompt),
                OpenAIChatMessage(role: "user", content: "Question:\n\(prompt)\n\nGraph Context:\n\(context.renderedText)")
            ],
            temperature: 0.2,
            reasoningEffort: config.reasoningEffort
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return AgentHTTPRequest(
            url: endpoint,
            method: "POST",
            headers: requestHeaders(),
            body: try encoder.encode(body),
            timeoutInterval: config.requestTimeout
        )
    }

    private var systemPrompt: String {
        AgentInstructionSection.defaultConnorInstruction
    }

    private func requestHeaders() -> [String: String] {
        var headers = config.extraHeaders
        switch config.apiKeyHeaderKind {
        case .bearer:
            headers["Authorization"] = "Bearer \(config.apiKey)"
        case .apiKey:
            headers["api-key"] = config.apiKey
        }
        headers["Content-Type"] = "application/json"
        return headers
    }

    private func makeToolCallingRequest(_ request: AgentModelRequest, stream: Bool = false) throws -> AgentHTTPRequest {
        try validateVisionSendAllowed(request)
        let endpoint = config.baseURL.appendingPathComponent("chat/completions")
        let messages = request.messages.enumerated().map { index, message in
            let role = projectedRole(for: message, index: index, instructionPlacement: request.instructionPlacement)
            return OpenAIChatMessage(
                role: role,
                content: message.content,
                contentParts: message.contentParts,
                toolCallID: message.toolCallID,
                name: message.name,
                toolCalls: message.toolCalls?.map { call in
                    OpenAIToolCall(
                        id: call.id,
                        type: "function",
                        function: OpenAIToolCallFunction(name: call.name, arguments: call.argumentsJSON)
                    )
                }
            )
        }
        let tools = request.tools.map { definition in
            OpenAIToolDefinition(type: "function", function: OpenAIFunctionDefinition(
                name: definition.name,
                description: definition.description,
                parameters: definition.inputSchema.jsonObject
            ))
        }
        let body = OpenAIChatCompletionRequest(
            model: config.requestModel,
            messages: messages,
            temperature: request.temperature,
            tools: tools.isEmpty ? nil : tools,
            toolChoice: tools.isEmpty ? nil : "auto",
            reasoningEffort: config.reasoningEffort,
            stream: stream
        )
        let data = try JSONSerialization.data(withJSONObject: try body.jsonObject(), options: [.sortedKeys])
        return AgentHTTPRequest(
            url: endpoint,
            method: "POST",
            headers: requestHeaders(),
            body: data,
            timeoutInterval: config.requestTimeout
        )
    }

    private func validateVisionSendAllowed(_ request: AgentModelRequest) throws {
        let profile = capabilityProfile
        switch AgentModelCapabilityKernel.visionSendDecision(profile: profile, request: request) {
        case .allowed:
            return
        case .denied(let reason):
            throw OpenAICompatibleProviderError.unsupportedVisionInput(model: profile.modelID, reason: reason)
        }
    }

    private func projectedRole(for message: AgentModelMessage, index: Int, instructionPlacement: AgentInstructionPlacement) -> String {
        guard index == 0, message.role == .system else { return message.role.rawValue }
        switch instructionPlacement {
        case .developerMessage:
            return "developer"
        case .systemMessage, .providerNativeSystem:
            return "system"
        }
    }

    private func parseResponse(_ data: Data) throws -> String {
        let decoded = try JSONDecoder().decode(OpenAIChatCompletionResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
            throw OpenAICompatibleProviderError.missingAssistantMessage
        }
        return content
    }

    private func parseToolCallingResponse(_ data: Data) throws -> AgentModelResponse {
        let decoded = try JSONDecoder().decode(OpenAIChatCompletionResponse.self, from: data)
        let choice = decoded.choices.first
        let message = choice?.message
        let toolCalls = message?.toolCalls?.map { call in
            AgentToolCall(id: call.id, name: call.function.name, argumentsJSON: call.function.arguments)
        } ?? []
        let finishReason = AgentModelFinishReason(rawValue: choice?.finishReason ?? "") ?? .unknown
        let usage = decoded.usage.map { AgentModelUsage(promptTokens: $0.promptTokens, completionTokens: $0.completionTokens, totalTokens: $0.totalTokens) }
        return AgentModelResponse(
            text: message?.content,
            toolCalls: toolCalls,
            usage: usage,
            finishReason: finishReason,
            rawResponseJSON: String(data: data, encoding: .utf8)
        )
    }

    static func errorMessage(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? [String: Any] {
                if let message = error["message"] as? String, !message.isEmpty {
                    return sanitizedErrorMessage(message)
                }
                if let code = error["code"] as? String, !code.isEmpty {
                    return sanitizedErrorMessage(code)
                }
            }
            if let message = object["message"] as? String, !message.isEmpty {
                return sanitizedErrorMessage(message)
            }
        }
        guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return sanitizedErrorMessage(text)
    }

    private static func sanitizedErrorMessage(_ message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 800 { return trimmed }
        return String(trimmed.prefix(800)) + "…"
    }
}

public extension OpenAICompatibleProvider where Client == URLSessionAgentHTTPClient {
    init(config: OpenAICompatibleConfig) {
        self.init(config: config, httpClient: URLSessionAgentHTTPClient(), sseClient: URLSessionAgentSSEHTTPClient())
    }
}

private struct OpenAIChatCompletionRequest: Encodable {
    var model: String
    var messages: [OpenAIChatMessage]
    var temperature: Double?
    var tools: [OpenAIToolDefinition]?
    var toolChoice: String?
    var reasoningEffort: String?
    var stream: Bool?

    init(model: String, messages: [OpenAIChatMessage], temperature: Double? = nil, tools: [OpenAIToolDefinition]? = nil, toolChoice: String? = nil, reasoningEffort: String? = nil, stream: Bool? = nil) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.tools = tools
        self.toolChoice = toolChoice
        self.reasoningEffort = reasoningEffort
        self.stream = stream
    }

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case tools
        case toolChoice = "tool_choice"
        case reasoningEffort = "reasoning_effort"
        case stream
    }

    func jsonObject() throws -> [String: Any] {
        let data = try JSONEncoder().encode(self)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}

private struct OpenAIChatMessage: Codable {
    var role: String
    var content: String?
    var contentParts: [AgentModelMessageContentPart]?
    var toolCallID: String?
    var name: String?
    var toolCalls: [OpenAIToolCall]?

    init(
        role: String,
        content: String? = nil,
        contentParts: [AgentModelMessageContentPart]? = nil,
        toolCallID: String? = nil,
        name: String? = nil,
        toolCalls: [OpenAIToolCall]? = nil
    ) {
        self.role = role
        self.content = content
        self.contentParts = contentParts
        self.toolCallID = toolCallID
        self.name = name
        self.toolCalls = toolCalls
    }

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case toolCallID = "tool_call_id"
        case name
        case toolCalls = "tool_calls"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(String.self, forKey: .role)
        content = try? container.decodeIfPresent(String.self, forKey: .content)
        contentParts = nil
        toolCallID = try container.decodeIfPresent(String.self, forKey: .toolCallID)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        toolCalls = try container.decodeIfPresent([OpenAIToolCall].self, forKey: .toolCalls)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        if let contentParts, !contentParts.isEmpty {
            try container.encode(contentParts.map(OpenAIChatContentPart.init(part:)), forKey: .content)
        } else {
            try container.encodeIfPresent(content, forKey: .content)
        }
        try container.encodeIfPresent(toolCallID, forKey: .toolCallID)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(toolCalls, forKey: .toolCalls)
    }
}

private struct OpenAIChatContentPart: Encodable {
    var type: String
    var text: String?
    var imageURL: OpenAIChatImageURL?

    init(part: AgentModelMessageContentPart) {
        switch part.kind {
        case .text:
            type = "text"
            text = part.text ?? ""
            imageURL = nil
        case .imageDataURL:
            type = "image_url"
            text = nil
            imageURL = OpenAIChatImageURL(url: part.dataURL ?? "", detail: part.detail)
        }
    }

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }
}

private struct OpenAIChatImageURL: Encodable {
    var url: String
    var detail: String?
}

private struct OpenAIToolDefinition: Encodable {
    var type: String
    var function: OpenAIFunctionDefinition
}

private struct OpenAIFunctionDefinition: Encodable {
    var name: String
    var description: String
    var parameters: [String: Any]

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case parameters
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        let data = try JSONSerialization.data(withJSONObject: parameters)
        let object = try JSONSerialization.jsonObject(with: data)
        try container.encode(AnyEncodableJSON(object), forKey: .parameters)
    }
}

private struct OpenAIToolCall: Codable {
    var id: String
    var type: String?
    var function: OpenAIToolCallFunction
}

private struct OpenAIToolCallFunction: Codable {
    var name: String
    var arguments: String
}

private struct OpenAIChatCompletionResponse: Decodable {
    var choices: [Choice]
    var usage: Usage?

    struct Choice: Decodable {
        var message: OpenAIChatMessage
        var finishReason: String?

        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }

    struct Usage: Decodable {
        var promptTokens: Int
        var completionTokens: Int
        var totalTokens: Int

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }
}

private enum OpenAISSEParser {
    static func payloads(from frame: String) -> [String] {
        frame
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { line -> String? in
                guard line.hasPrefix("data:") else { return nil }
                return line.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
    }
}

private struct OpenAIChatCompletionStreamChunk: Decodable {
    var choices: [Choice]
    var usage: OpenAIChatCompletionResponse.Usage?

    struct Choice: Decodable {
        var delta: Delta
        var finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    struct Delta: Decodable {
        var role: String?
        var content: String?
        var toolCalls: [ToolCallDelta]?

        enum CodingKeys: String, CodingKey {
            case role
            case content
            case toolCalls = "tool_calls"
        }
    }

    struct ToolCallDelta: Decodable {
        var index: Int
        var id: String?
        var type: String?
        var function: FunctionDelta?
    }

    struct FunctionDelta: Decodable {
        var name: String?
        var arguments: String?
    }
}

private struct OpenAIChatCompletionStreamAccumulator {
    private struct ToolCallState {
        var id: String?
        var name: String?
        var arguments = ""
    }

    private var text = ""
    private var finishReason: AgentModelFinishReason = .unknown
    private var usage: AgentModelUsage?
    private var rawEvents: [String] = []
    private var toolCalls: [Int: ToolCallState] = [:]

    mutating func append(chunk: OpenAIChatCompletionStreamChunk, rawJSON: String) -> [AgentModelStreamEvent] {
        rawEvents.append(rawJSON)
        if let chunkUsage = chunk.usage {
            usage = AgentModelUsage(promptTokens: chunkUsage.promptTokens, completionTokens: chunkUsage.completionTokens, totalTokens: chunkUsage.totalTokens)
        }
        var events: [AgentModelStreamEvent] = []
        for choice in chunk.choices {
            if let reason = choice.finishReason {
                finishReason = AgentModelFinishReason(rawValue: reason) ?? .unknown
            }
            if let content = choice.delta.content, !content.isEmpty {
                text += content
                events.append(.textDelta(content))
            }
            for toolCall in choice.delta.toolCalls ?? [] {
                var state = toolCalls[toolCall.index] ?? ToolCallState()
                if let id = toolCall.id { state.id = id }
                if let name = toolCall.function?.name { state.name = name }
                let arguments = toolCall.function?.arguments ?? ""
                if !arguments.isEmpty { state.arguments += arguments }
                toolCalls[toolCall.index] = state
                if !arguments.isEmpty {
                    events.append(.toolInputDelta(toolCallID: state.id, name: state.name, partialJSON: arguments))
                }
            }
        }
        return events
    }

    func response() -> AgentModelResponse {
        let calls = toolCalls.keys.sorted().compactMap { index -> AgentToolCall? in
            guard let state = toolCalls[index], let name = state.name else { return nil }
            return AgentToolCall(id: state.id ?? "call_\(index)", name: name, argumentsJSON: state.arguments)
        }
        return AgentModelResponse(
            text: text.isEmpty ? nil : text,
            toolCalls: calls,
            usage: usage,
            finishReason: finishReason,
            rawResponseJSON: rawEvents.joined(separator: "\n")
        )
    }
}

private struct AnyEncodableJSON: Encodable {
    var value: Any

    init(_ value: Any) { self.value = value }

    func encode(to encoder: Encoder) throws {
        switch value {
        case let dictionary as [String: Any]:
            var container = encoder.container(keyedBy: DynamicCodingKey.self)
            for (key, value) in dictionary {
                try container.encode(AnyEncodableJSON(value), forKey: DynamicCodingKey(stringValue: key)!)
            }
        case let array as [Any]:
            var container = encoder.unkeyedContainer()
            for value in array { try container.encode(AnyEncodableJSON(value)) }
        case let string as String:
            var container = encoder.singleValueContainer(); try container.encode(string)
        case let number as NSNumber:
            var container = encoder.singleValueContainer()
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                try container.encode(number.boolValue)
            } else if CFNumberIsFloatType(number) {
                try container.encode(number.doubleValue)
            } else {
                try container.encode(number.int64Value)
            }
        case _ as NSNull:
            var container = encoder.singleValueContainer(); try container.encodeNil()
        default:
            var container = encoder.singleValueContainer(); try container.encode(String(describing: value))
        }
    }
}

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) { self.stringValue = stringValue; self.intValue = nil }
    init?(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
}
