import Foundation
import ConnorGraphSearch

public struct OpenAIResponsesConfig: Sendable, Equatable {
    public var baseURL: URL
    public var apiKey: String
    public var model: String
    public var extraHeaders: [String: String]
    public var apiKeyHeaderKind: OpenAICompatibleAPIKeyHeaderKind
    public var reasoningEffort: String?
    public var includeEncryptedReasoning: Bool
    public var requestTimeout: TimeInterval
    public var explicitVisionSupport: Bool?

    public init(
        baseURL: URL,
        apiKey: String,
        model: String,
        extraHeaders: [String: String] = [:],
        apiKeyHeaderKind: OpenAICompatibleAPIKeyHeaderKind = .bearer,
        reasoningEffort: String? = nil,
        includeEncryptedReasoning: Bool = false,
        requestTimeout: TimeInterval = 300,
        explicitVisionSupport: Bool? = nil
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.extraHeaders = extraHeaders
        self.apiKeyHeaderKind = apiKeyHeaderKind
        self.reasoningEffort = reasoningEffort
        self.includeEncryptedReasoning = includeEncryptedReasoning
        self.requestTimeout = requestTimeout
        self.explicitVisionSupport = explicitVisionSupport
    }

    public var requestModel: String {
        model
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? model.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct OpenAIResponsesProvider<Client: AgentHTTPClient>: AgentModelProvider, StreamingAgentModelProvider, LLMProvider, Sendable {
    public var config: OpenAIResponsesConfig
    public var httpClient: Client
    public var sseClient: (any AgentSSEHTTPClient)?

    public var modelID: String { config.requestModel }
    public var capabilityProfile: AgentModelCapabilityProfile {
        AgentModelCapabilityKernel.profile(providerKind: .openAIResponses, modelID: config.requestModel, explicitVisionSupport: config.explicitVisionSupport)
    }
    public var capabilities: AgentModelCapabilities { capabilityProfile.agentCapabilities }

    public init(config: OpenAIResponsesConfig, httpClient: Client, sseClient: (any AgentSSEHTTPClient)? = nil) {
        self.config = config
        self.httpClient = httpClient
        self.sseClient = sseClient
    }

    public func complete(prompt: String, context: AgentContext) async throws -> LLMResponse {
        let response = try await complete(AgentModelRequest(messages: [
            AgentModelMessage(role: .system, content: "You are Connor, a concise and helpful graph-memory-native assistant."),
            AgentModelMessage(role: .user, content: "Question:\n\(prompt)\n\nGraph Context:\n\(context.renderedText)")
        ]))
        guard let text = response.text, !text.isEmpty else { throw OpenAICompatibleProviderError.missingAssistantMessage }
        return LLMResponse(text: text, citations: [])
    }

    public func healthCheck() async throws -> LLMProviderHealthCheckResult {
        let context = AgentContext(query: "provider-health-check", items: [])
        let response = try await complete(prompt: "Reply with exactly: OK", context: context)
        return LLMProviderHealthCheckResult(
            ok: !response.text.isEmpty,
            model: config.requestModel,
            message: response.text
        )
    }

    private static var visionDegradationWarning: String { "⚠️ 当前模型不支持图片输入，已自动发送文字内容。图片内容已忽略。" }

    public func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse {
        var client = httpClient
        do {
            let httpRequest = try makeRequest(request, stream: false)
            let response = try await client.send(httpRequest)
            if response.statusCode < 200 || response.statusCode >= 300 {
                throw OpenAICompatibleProviderError.httpStatus(response.statusCode, message: nil)
            }
            return try OpenAIResponsesParser.parseResponse(response.body)
        } catch OpenAICompatibleProviderError.unsupportedVisionInput {
            guard request.containsImageInput else { throw OpenAICompatibleProviderError.unsupportedVisionInput(model: capabilityProfile.modelID, reason: "vision not supported") }
            let stripped = request.stripImageContent()
            let httpRequest = try makeRequest(stripped, stream: false)
            let response = try await client.send(httpRequest)
            if response.statusCode < 200 || response.statusCode >= 300 {
                throw OpenAICompatibleProviderError.httpStatus(response.statusCode, message: nil)
            }
            var result = try OpenAIResponsesParser.parseResponse(response.body)
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
                        let httpRequest = try makeRequest(request, stream: true)
                        let frames = try await sseClient.stream(httpRequest)
                        var accumulator = OpenAIResponsesStreamAccumulator()
                        for try await frame in frames {
                            for payload in OpenAIResponsesSSEParser.payloads(from: frame) {
                                guard payload != "[DONE]" else { continue }
                                for event in try accumulator.append(payload: payload) {
                                    continuation.yield(event)
                                }
                            }
                        }
                        if let response = accumulator.completedResponse {
                            continuation.yield(.completed(response))
                        }
                        continuation.finish()
                    } catch OpenAICompatibleProviderError.unsupportedVisionInput {
                        guard request.containsImageInput else { throw OpenAICompatibleProviderError.unsupportedVisionInput(model: capabilityProfile.modelID, reason: "vision not supported") }
                        let stripped = request.stripImageContent()
                        let httpRequest = try makeRequest(stripped, stream: true)
                        let frames = try await sseClient.stream(httpRequest)
                        var accumulator = OpenAIResponsesStreamAccumulator()
                        for try await frame in frames {
                            for payload in OpenAIResponsesSSEParser.payloads(from: frame) {
                                guard payload != "[DONE]" else { continue }
                                for event in try accumulator.append(payload: payload) {
                                    continuation.yield(event)
                                }
                            }
                        }
                        if var response = accumulator.completedResponse {
                            response.warnings.append(Self.visionDegradationWarning)
                            continuation.yield(.completed(response))
                        }
                        continuation.finish()
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
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

    private func makeRequest(_ request: AgentModelRequest, stream: Bool) throws -> AgentHTTPRequest {
        try validateVisionSendAllowed(request)
        let endpoint = config.baseURL.appendingPathComponent("responses")
        var body: [String: Any] = [
            "model": config.requestModel,
            "input": inputItems(for: request),
            "store": false
        ]
        if request.temperature > 0 { body["temperature"] = request.temperature }
        if stream { body["stream"] = true }
        if let reasoningEffort = config.reasoningEffort, !reasoningEffort.isEmpty {
            body["reasoning"] = ["effort": reasoningEffort]
        }
        if config.includeEncryptedReasoning {
            body["include"] = ["reasoning.encrypted_content"]
        }
        let tools = request.tools.map { tool in
            [
                "type": "function",
                "name": tool.name,
                "description": tool.description,
                "parameters": tool.inputSchema.jsonObject,
                "strict": tool.inputSchema.isOpenAIStrictCompatible
            ] as [String: Any]
        }
        if !tools.isEmpty {
            body["tools"] = tools
            body["tool_choice"] = "auto"
        }
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return AgentHTTPRequest(url: endpoint, method: "POST", headers: requestHeaders(), body: data, timeoutInterval: config.requestTimeout)
    }

    private func inputItems(for request: AgentModelRequest) -> [[String: Any]] {
        request.messages.enumerated().flatMap { index, message -> [[String: Any]] in
            let role = projectedRole(for: message, index: index, instructionPlacement: request.instructionPlacement)
            switch message.role {
            case .tool:
                return [[
                    "type": "function_call_output",
                    "call_id": message.toolCallID ?? message.id,
                    "output": message.content
                ]]
            case .assistant where message.toolCalls?.isEmpty == false:
                return message.toolCalls?.map { call in
                    [
                        "type": "function_call",
                        "call_id": call.id,
                        "name": call.name,
                        "arguments": call.argumentsJSON
                    ]
                } ?? []
            default:
                var item: [String: Any] = ["role": role]
                if let contentParts = responsesContentParts(for: message), !contentParts.isEmpty {
                    item["content"] = contentParts
                } else {
                    item["content"] = message.content
                }
                return [item]
            }
        }
    }

    private func responsesContentParts(for message: AgentModelMessage) -> [[String: Any]]? {
        guard let parts = message.contentParts, !parts.isEmpty else { return nil }
        let mapped = parts.compactMap { part -> [String: Any]? in
            switch part.kind {
            case .text:
                guard let text = part.text, !text.isEmpty else { return nil }
                return ["type": "input_text", "text": text]
            case .imageDataURL:
                guard let dataURL = part.dataURL, !dataURL.isEmpty else { return nil }
                var object: [String: Any] = ["type": "input_image", "image_url": dataURL]
                if let detail = part.detail, !detail.isEmpty { object["detail"] = detail }
                return object
            }
        }
        return mapped.isEmpty ? nil : mapped
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
}

public extension OpenAIResponsesProvider where Client == URLSessionAgentHTTPClient {
    init(config: OpenAIResponsesConfig) {
        self.init(config: config, httpClient: URLSessionAgentHTTPClient(), sseClient: URLSessionAgentSSEHTTPClient())
    }
}

private enum OpenAIResponsesParser {
    static func parseResponse(_ data: Data) throws -> AgentModelResponse {
        let object = try jsonObject(from: data)
        return try parseResponseObject(object, rawJSON: String(data: data, encoding: .utf8))
    }

    static func parseResponseObject(_ object: [String: Any], rawJSON: String?) throws -> AgentModelResponse {
        let output = object["output"] as? [[String: Any]] ?? []
        let outputText = text(from: output)
        let toolCalls = functionCalls(from: output)
        let usage = usage(from: object["usage"] as? [String: Any])
        let rawOutputItemsJSON = try? jsonString(output)
        let responseID = object["id"] as? String
        let finishReason: AgentModelFinishReason = toolCalls.isEmpty ? .stop : .toolCalls
        let metadata = AgentModelProviderMetadata(
            providerID: "openai-responses",
            rawOutputItemsJSON: rawOutputItemsJSON,
            stopReason: object["status"] as? String,
            responseID: responseID,
            reasoningEncryptedContentPresent: rawOutputItemsJSON?.contains("encrypted_content") == true
        )
        return AgentModelResponse(
            text: outputText,
            toolCalls: toolCalls,
            usage: usage,
            finishReason: finishReason,
            rawResponseJSON: rawJSON,
            providerMetadata: metadata
        )
    }

    private static func text(from output: [[String: Any]]) -> String? {
        let parts = output.flatMap { item -> [String] in
            if item["type"] as? String == "message", let content = item["content"] as? [[String: Any]] {
                return content.compactMap { part in
                    guard ["output_text", "text"].contains(part["type"] as? String ?? "") else { return nil }
                    return part["text"] as? String
                }
            }
            if item["type"] as? String == "output_text" { return [item["text"] as? String].compactMap { $0 } }
            return []
        }
        let text = parts.joined()
        return text.isEmpty ? nil : text
    }

    private static func functionCalls(from output: [[String: Any]]) -> [AgentToolCall] {
        output.compactMap { item in
            guard item["type"] as? String == "function_call" else { return nil }
            let id = (item["call_id"] as? String) ?? (item["id"] as? String) ?? UUID().uuidString
            guard let name = item["name"] as? String else { return nil }
            let arguments = item["arguments"] as? String ?? "{}"
            return AgentToolCall(id: id, name: name, argumentsJSON: arguments)
        }
    }

    private static func usage(from object: [String: Any]?) -> AgentModelUsage? {
        guard let object else { return nil }
        let prompt = object["input_tokens"] as? Int ?? object["prompt_tokens"] as? Int ?? 0
        let completion = object["output_tokens"] as? Int ?? object["completion_tokens"] as? Int ?? 0
        let total = object["total_tokens"] as? Int
        return AgentModelUsage(promptTokens: prompt, completionTokens: completion, totalTokens: total)
    }

    static func jsonObject(from data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenAICompatibleProviderError.invalidResponse
        }
        return object
    }

    static func jsonString(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? ""
    }
}

private enum OpenAIResponsesSSEParser {
    static func payloads(from frame: String) -> [String] {
        frame
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.hasPrefix("data:") else { return nil }
                return String(trimmed.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces)
            }
    }
}

private struct OpenAIResponsesStreamAccumulator {
    var completedResponse: AgentModelResponse?
    private var functionCallsByOutputIndex: [Int: (callID: String?, name: String?, arguments: String)] = [:]

    mutating func append(payload: String) throws -> [AgentModelStreamEvent] {
        let object = try OpenAIResponsesParser.jsonObject(from: Data(payload.utf8))
        guard let type = object["type"] as? String else { return [.rawProviderEvent(payload)] }
        switch type {
        case "response.output_text.delta":
            return [object["delta"] as? String].compactMap { $0 }.map(AgentModelStreamEvent.textDelta)
        case "response.output_item.added":
            if let outputIndex = object["output_index"] as? Int,
               let item = object["item"] as? [String: Any],
               item["type"] as? String == "function_call" {
                functionCallsByOutputIndex[outputIndex] = (
                    callID: item["call_id"] as? String ?? item["id"] as? String,
                    name: item["name"] as? String,
                    arguments: item["arguments"] as? String ?? ""
                )
            }
            return [.rawProviderEvent(payload)]
        case "response.function_call_arguments.delta":
            let outputIndex = object["output_index"] as? Int ?? 0
            let delta = object["delta"] as? String ?? ""
            var existing = functionCallsByOutputIndex[outputIndex] ?? (callID: nil, name: nil, arguments: "")
            existing.arguments += delta
            functionCallsByOutputIndex[outputIndex] = existing
            return [.toolInputDelta(toolCallID: existing.callID, name: existing.name, partialJSON: delta)]
        case "response.function_call_arguments.done":
            if let outputIndex = object["output_index"] as? Int,
               let item = object["item"] as? [String: Any] {
                functionCallsByOutputIndex[outputIndex] = (
                    callID: item["call_id"] as? String ?? item["id"] as? String,
                    name: item["name"] as? String,
                    arguments: item["arguments"] as? String ?? ""
                )
            }
            return [.rawProviderEvent(payload)]
        case "response.completed":
            if let responseObject = object["response"] as? [String: Any] {
                completedResponse = try OpenAIResponsesParser.parseResponseObject(responseObject, rawJSON: try? OpenAIResponsesParser.jsonString(responseObject))
            }
            return [.rawProviderEvent(payload)]
        case "error", "response.failed":
            return [.rawProviderEvent(payload)]
        default:
            return [.rawProviderEvent(payload)]
        }
    }
}
