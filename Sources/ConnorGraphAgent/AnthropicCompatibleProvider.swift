import Foundation
import ConnorGraphSearch
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum AnthropicCompatibleAuthHeaderKind: String, Codable, Sendable, Equatable {
    case xAPIKey = "x_api_key"
    case bearer
}

public struct AnthropicCompatibleConfig: Sendable, Equatable {
    public var baseURL: URL
    public var apiKey: String
    public var model: String
    public var authHeaderKind: AnthropicCompatibleAuthHeaderKind
    public var anthropicVersion: String
    public var extraHeaders: [String: String]
    public var maxTokens: Int
    public var requestTimeout: TimeInterval
    public var featureOptions: AnthropicCompatibleFeatureOptions

    public init(
        baseURL: URL,
        apiKey: String,
        model: String,
        authHeaderKind: AnthropicCompatibleAuthHeaderKind = .xAPIKey,
        anthropicVersion: String = "2023-06-01",
        extraHeaders: [String: String] = [:],
        maxTokens: Int = 4096,
        requestTimeout: TimeInterval = 300,
        featureOptions: AnthropicCompatibleFeatureOptions = AnthropicCompatibleFeatureOptions()
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.authHeaderKind = authHeaderKind
        self.anthropicVersion = anthropicVersion
        self.extraHeaders = extraHeaders
        self.maxTokens = maxTokens
        self.requestTimeout = requestTimeout
        self.featureOptions = featureOptions
    }

    public init(
        baseURL: URL,
        apiKey: String,
        model: String,
        authHeaderKind: AnthropicCompatibleAuthHeaderKind = .xAPIKey,
        anthropicVersion: String = "2023-06-01",
        extraHeaders: [String: String] = [:],
        maxTokens: Int = 4096,
        featureOptions: AnthropicCompatibleFeatureOptions
    ) {
        self.init(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            authHeaderKind: authHeaderKind,
            anthropicVersion: anthropicVersion,
            extraHeaders: extraHeaders,
            maxTokens: maxTokens,
            requestTimeout: 300,
            featureOptions: featureOptions
        )
    }

    public var requestModel: String {
        model
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? model.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum AnthropicCompatibleProviderError: Error, Equatable, Sendable {
    case invalidResponse
    case httpStatus(Int, message: String?)
    case missingAssistantMessage
    case streamError(String)
    case unsupportedVisionInput(model: String, reason: String)
    case invalidImageDataURL
}

extension AnthropicCompatibleProviderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Anthropic-compatible provider returned an invalid response."
        case let .httpStatus(code, message):
            if let message, !message.isEmpty {
                return "HTTP \(code): \(message)"
            }
            return "HTTP \(code)"
        case .missingAssistantMessage:
            return "Anthropic-compatible provider response did not include an assistant message."
        case let .streamError(message):
            return message
        case let .unsupportedVisionInput(model, reason):
            return "Anthropic-compatible model \(model) cannot receive image input: \(reason)"
        case .invalidImageDataURL:
            return "Anthropic-compatible provider received a malformed image data URL."
        }
    }
}

public struct AnthropicCompatibleProvider<Client: AgentHTTPClient>: LLMProvider, StreamingAgentModelProvider, Sendable {
    public var config: AnthropicCompatibleConfig
    public var httpClient: Client
    public var sseClient: (any AgentSSEHTTPClient)?

    public var modelID: String { config.requestModel }
    public var capabilityProfile: AgentModelCapabilityProfile {
        var profile = AgentModelCapabilityKernel.profile(providerKind: .anthropicCompatible, modelID: config.requestModel)
        profile.supportsStreaming = config.featureOptions.streamingEnabled
        return profile
    }
    public var capabilities: AgentModelCapabilities { capabilityProfile.agentCapabilities }

    public init(config: AnthropicCompatibleConfig, httpClient: Client, sseClient: (any AgentSSEHTTPClient)? = nil) {
        self.config = config
        self.httpClient = httpClient
        self.sseClient = sseClient
    }

    public init(config: AnthropicCompatibleConfig) where Client == URLSessionAgentHTTPClient {
        self.config = config
        self.httpClient = URLSessionAgentHTTPClient()
        self.sseClient = URLSessionAgentSSEHTTPClient()
    }

    public func complete(prompt: String, context: AgentContext) async throws -> LLMResponse {
        let response = try await complete(AgentModelRequest(messages: [
            AgentModelMessage(role: .system, content: AgentInstructionSection.defaultConnorInstruction),
            AgentModelMessage(role: .user, content: "Question:\n\(prompt)\n\nGraph Context:\n\(context.renderedText)")
        ]))
        guard let text = response.text, !text.isEmpty else { throw AnthropicCompatibleProviderError.missingAssistantMessage }
        return LLMResponse(text: text, citations: context.items.map(\.sourceID))
    }

    public func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse {
        var client = httpClient
        let httpRequest = try makeMessagesRequest(request)
        let httpResponse = try await client.send(httpRequest)
        if httpResponse.statusCode < 200 || httpResponse.statusCode >= 300 {
            throw AnthropicCompatibleProviderError.httpStatus(httpResponse.statusCode, message: Self.errorMessage(from: httpResponse.body))
        }
        return try parseMessagesResponse(httpResponse.body)
    }

    public func streamComplete(_ request: AgentModelRequest) -> AsyncThrowingStream<AgentModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard config.featureOptions.streamingEnabled, let sseClient else {
                        continuation.yield(.completed(try await complete(request)))
                        continuation.finish()
                        return
                    }
                    let httpRequest = try makeMessagesRequest(request, stream: true)
                    let frames = try await sseClient.stream(httpRequest)
                    let parser = AnthropicSSEParser()
                    var accumulator = AnthropicStreamAccumulator()
                    for try await frame in frames {
                        for event in parser.parse(frame) {
                            if case .error(let message) = event {
                                continuation.finish(throwing: AnthropicCompatibleProviderError.streamError(message))
                                return
                            }
                            if let mapped = accumulator.append(event) {
                                continuation.yield(mapped)
                            }
                        }
                    }
                    continuation.yield(.completed(accumulator.response()))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func healthCheck() async throws -> LLMProviderHealthCheckResult {
        let response = try await complete(AgentModelRequest(messages: [
            AgentModelMessage(role: .system, content: "You are a connection health checker."),
            AgentModelMessage(role: .user, content: "Reply with exactly: OK")
        ]))
        guard let text = response.text, !text.isEmpty else { throw AnthropicCompatibleProviderError.missingAssistantMessage }
        return LLMProviderHealthCheckResult(ok: true, model: config.requestModel, message: "Connection OK: \(config.requestModel)")
    }

    private func makeMessagesRequest(_ request: AgentModelRequest, stream: Bool = false) throws -> AgentHTTPRequest {
        try validateVisionSendAllowed(request)
        var body: [String: Any] = [
            "model": config.requestModel,
            "max_tokens": config.maxTokens,
            "messages": anthropicMessages(for: request.messages)
        ]
        if stream { body["stream"] = true }
        if let thinking = config.featureOptions.thinking { body["thinking"] = thinking.jsonObject }
        if let cache = config.featureOptions.promptCache.jsonObject { body["cache_control"] = cache }
        let system = request.messages
            .filter { $0.role == .system }
            .map(\.content)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        if !system.isEmpty {
            body["system"] = system
        }
        if !request.tools.isEmpty || !config.featureOptions.serverTools.isEmpty {
            var tools: [[String: Any]] = request.tools.map { tool in
                var object: [String: Any] = [
                    "name": tool.name,
                    "description": tool.description,
                    "input_schema": tool.inputSchema.jsonObject
                ]
                if config.featureOptions.eagerInputStreamingToolNames.contains(tool.name) { object["eager_input_streaming"] = true }
                if config.featureOptions.cachedToolNames.contains(tool.name) { object["cache_control"] = ["type": "ephemeral"] }
                return object
            }
            tools.append(contentsOf: config.featureOptions.serverTools.map(\.jsonObject))
            body["tools"] = tools
        }
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return AgentHTTPRequest(
            url: messagesEndpoint(),
            method: "POST",
            headers: requestHeaders(),
            body: data,
            timeoutInterval: config.requestTimeout
        )
    }

    private func anthropicMessages(for messages: [AgentModelMessage]) -> [[String: Any]] {
        var result: [[String: Any]] = []
        var index = messages.startIndex
        while index < messages.endIndex {
            let message = messages[index]
            switch message.role {
            case .system:
                index = messages.index(after: index)
            case .user:
                result.append(["role": "user", "content": contentBlocks(for: message)])
                index = messages.index(after: index)
            case .assistant:
                result.append(anthropicAssistantMessage(for: message))
                index = messages.index(after: index)
            case .tool:
                var content: [[String: Any]] = []
                while index < messages.endIndex, messages[index].role == .tool {
                    content.append(toolResultBlock(for: messages[index]))
                    index = messages.index(after: index)
                }
                if index < messages.endIndex, messages[index].role == .user {
                    content.append(contentsOf: contentBlocks(for: messages[index]))
                    index = messages.index(after: index)
                }
                result.append(["role": "user", "content": content])
            }
        }
        return result
    }

    private func anthropicAssistantMessage(for message: AgentModelMessage) -> [String: Any] {
        if message.providerMetadata?.providerID == "anthropic-compatible",
           let raw = message.providerMetadata?.rawAssistantContentJSON,
           let data = raw.data(using: .utf8),
           let blocks = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return ["role": "assistant", "content": blocks]
        }
        var content: [[String: Any]] = []
        let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { content.append(["type": "text", "text": text]) }
        for toolCall in message.toolCalls ?? [] {
            let inputObject = (try? JSONSerialization.jsonObject(with: Data(toolCall.argumentsJSON.utf8))) ?? [:]
            content.append([
                "type": "tool_use",
                "id": toolCall.id,
                "name": toolCall.name,
                "input": inputObject
            ])
        }
        return ["role": "assistant", "content": content]
    }

    private func toolResultBlock(for message: AgentModelMessage) -> [String: Any] {
        [
            "type": "tool_result",
            "tool_use_id": message.toolCallID ?? message.id,
            "content": message.content
        ]
    }

    private func contentBlocks(for message: AgentModelMessage) -> [[String: Any]] {
        if let parts = message.contentParts, !parts.isEmpty {
            let blocks = parts.compactMap { part -> [String: Any]? in
                switch part.kind {
                case .text:
                    guard let text = part.text, !text.isEmpty else { return nil }
                    return ["type": "text", "text": text]
                case .imageDataURL:
                    guard let parsed = AgentImageDataURLParser.parse(part.dataURL ?? "", fallbackMimeType: part.mimeType) else {
                        return nil
                    }
                    return [
                        "type": "image",
                        "source": [
                            "type": "base64",
                            "media_type": parsed.mimeType,
                            "data": parsed.base64
                        ]
                    ]
                }
            }
            if !blocks.isEmpty { return blocks }
        }
        return [["type": "text", "text": message.content]]
    }

    private func validateVisionSendAllowed(_ request: AgentModelRequest) throws {
        let profile = capabilityProfile
        switch AgentModelCapabilityKernel.visionSendDecision(profile: profile, request: request) {
        case .allowed:
            return
        case .denied(let reason):
            throw AnthropicCompatibleProviderError.unsupportedVisionInput(model: profile.modelID, reason: reason)
        }
    }

    private static func errorMessage(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? [String: Any] {
                if let message = error["message"] as? String, !message.isEmpty {
                    return sanitizedErrorMessage(message)
                }
                if let type = error["type"] as? String, !type.isEmpty {
                    return sanitizedErrorMessage(type)
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

    private func messagesEndpoint() -> URL {
        let path = config.baseURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path == "v1" || path.hasSuffix("/v1") {
            return config.baseURL.appendingPathComponent("messages")
        }
        return config.baseURL.appendingPathComponent("v1").appendingPathComponent("messages")
    }

    private func requestHeaders() -> [String: String] {
        var headers = config.extraHeaders
        headers["Content-Type"] = "application/json"
        headers["anthropic-version"] = config.anthropicVersion
        if !config.featureOptions.betaHeaders.isEmpty { headers["anthropic-beta"] = config.featureOptions.betaHeaders.joined(separator: ",") }
        switch config.authHeaderKind {
        case .xAPIKey:
            headers["x-api-key"] = config.apiKey
            headers.removeValue(forKey: "Authorization")
        case .bearer:
            headers["Authorization"] = "Bearer \(config.apiKey)"
            headers.removeValue(forKey: "x-api-key")
        }
        return headers
    }

    private func parseMessagesResponse(_ data: Data) throws -> AgentModelResponse {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AnthropicCompatibleProviderError.invalidResponse
        }
        let content = object["content"] as? [[String: Any]] ?? []
        var textBlocks: [String] = []
        var toolCalls: [AgentToolCall] = []
        for block in content {
            switch block["type"] as? String {
            case "text":
                if let text = block["text"] as? String, !text.isEmpty { textBlocks.append(text) }
            case "tool_use":
                guard let id = block["id"] as? String,
                      let name = block["name"] as? String else { continue }
                let input = block["input"] ?? [:]
                let inputData = try JSONSerialization.data(withJSONObject: input, options: [.sortedKeys])
                let argumentsJSON = String(data: inputData, encoding: .utf8) ?? "{}"
                toolCalls.append(AgentToolCall(id: id, name: name, argumentsJSON: argumentsJSON))
            default:
                continue
            }
        }
        let usageObject = object["usage"] as? [String: Any]
        let inputTokens = usageObject?["input_tokens"] as? Int ?? 0
        let outputTokens = usageObject?["output_tokens"] as? Int ?? 0
        let usage = usageObject == nil ? nil : AgentModelUsage(promptTokens: inputTokens, completionTokens: outputTokens, cacheCreationInputTokens: usageObject?["cache_creation_input_tokens"] as? Int, cacheReadInputTokens: usageObject?["cache_read_input_tokens"] as? Int)
        let stopReason = object["stop_reason"] as? String
        let finishReason: AgentModelFinishReason = stopReason == "tool_use" ? .toolCalls : (stopReason == "max_tokens" ? .length : .stop)
        let rawJSON = String(data: data, encoding: .utf8)
        let contentData = try? JSONSerialization.data(withJSONObject: content, options: [.sortedKeys])
        let rawContentJSON = contentData.flatMap { String(data: $0, encoding: .utf8) }
        return AgentModelResponse(
            text: textBlocks.isEmpty ? nil : textBlocks.joined(separator: ""),
            toolCalls: toolCalls,
            usage: usage,
            finishReason: finishReason,
            rawResponseJSON: rawJSON,
            providerMetadata: AgentModelProviderMetadata(providerID: "anthropic-compatible", rawAssistantContentJSON: rawContentJSON, stopReason: stopReason)
        )
    }
}
