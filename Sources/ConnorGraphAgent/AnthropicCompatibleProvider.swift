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
    public var explicitVisionSupport: Bool?

    public init(
        baseURL: URL,
        apiKey: String,
        model: String,
        authHeaderKind: AnthropicCompatibleAuthHeaderKind = .xAPIKey,
        anthropicVersion: String = "2023-06-01",
        extraHeaders: [String: String] = [:],
        maxTokens: Int = 20_000,
        requestTimeout: TimeInterval = 300,
        featureOptions: AnthropicCompatibleFeatureOptions = AnthropicCompatibleFeatureOptions(),
        explicitVisionSupport: Bool? = nil
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.authHeaderKind = authHeaderKind
        self.anthropicVersion = anthropicVersion
        self.extraHeaders = extraHeaders
        self.maxTokens = Self.effectiveMaxTokens(requested: maxTokens, thinking: featureOptions.thinking)
        self.requestTimeout = requestTimeout
        self.featureOptions = featureOptions
        self.explicitVisionSupport = explicitVisionSupport
    }

    private static func effectiveMaxTokens(requested: Int, thinking: AnthropicThinkingConfig?) -> Int {
        guard case .enabled(let budgetTokens, _) = thinking else { return requested }
        return max(requested, budgetTokens + 10_000)
    }

    public init(
        baseURL: URL,
        apiKey: String,
        model: String,
        authHeaderKind: AnthropicCompatibleAuthHeaderKind = .xAPIKey,
        anthropicVersion: String = "2023-06-01",
        extraHeaders: [String: String] = [:],
        maxTokens: Int = 20_000,
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

func anthropicCompatibleErrorMessage(from data: Data) -> String? {
    guard !data.isEmpty else { return nil }
    let message: String?
    if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        if let error = object["error"] as? [String: Any] {
            message = (error["message"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? (error["type"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        } else {
            message = (object["message"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
    } else {
        message = String(data: data, encoding: .utf8)
    }
    guard let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
        return nil
    }
    return trimmed.count <= 800 ? trimmed : String(trimmed.prefix(800)) + "…"
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
    private final class StreamingCompatibilityState: @unchecked Sendable {
        private let lock = NSLock()
        private var streamingIsDisabled = false

        var shouldAttemptStreaming: Bool {
            lock.withLock { !streamingIsDisabled }
        }

        func markIncompatible() {
            lock.withLock { streamingIsDisabled = true }
        }
    }

    public var config: AnthropicCompatibleConfig
    public var httpClient: Client
    public var sseClient: (any AgentSSEHTTPClient)?
    private let streamingCompatibility = StreamingCompatibilityState()

    public var modelID: String { config.requestModel }
    public var capabilityProfile: AgentModelCapabilityProfile {
        var profile = AgentModelCapabilityKernel.profile(providerKind: .anthropicCompatible, modelID: config.requestModel, explicitVisionSupport: config.explicitVisionSupport)
        profile.supportsStreaming = config.featureOptions.streamingEnabled
        return profile
    }
    public var capabilities: AgentModelCapabilities {
        var capabilities = capabilityProfile.agentCapabilities
        capabilities.supportsExplicitPromptCacheBreakpoints = config.featureOptions.promptCache.enabled
        return capabilities
    }

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
            AgentModelMessage(role: .system, content: AgentInstructionSection.runtimeConnorInstruction),
            AgentModelMessage(role: .user, content: "Question:\n\(prompt)")
        ]))
        guard let text = response.text, !text.isEmpty else { throw AnthropicCompatibleProviderError.missingAssistantMessage }
        return LLMResponse(text: text, citations: [])
    }

    private static var visionDegradationWarning: String { "⚠️ 当前模型不支持图片输入，已自动发送文字内容。图片内容已忽略。" }

    public func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse {
        var client = httpClient
        do {
            let httpRequest = try makeMessagesRequest(request)
            let httpResponse = try await client.send(httpRequest)
            if httpResponse.statusCode < 200 || httpResponse.statusCode >= 300 {
                throw AnthropicCompatibleProviderError.httpStatus(httpResponse.statusCode, message: anthropicCompatibleErrorMessage(from: httpResponse.body))
            }
            return try validatedMessagesResponse(parseMessagesResponse(httpResponse.body))
        } catch AnthropicCompatibleProviderError.unsupportedVisionInput {
            guard request.containsImageInput else { throw AnthropicCompatibleProviderError.unsupportedVisionInput(model: capabilityProfile.modelID, reason: "vision not supported") }
            let stripped = request.stripImageContent()
            let httpRequest = try makeMessagesRequest(stripped)
            let httpResponse = try await client.send(httpRequest)
            if httpResponse.statusCode < 200 || httpResponse.statusCode >= 300 {
                throw AnthropicCompatibleProviderError.httpStatus(httpResponse.statusCode, message: anthropicCompatibleErrorMessage(from: httpResponse.body))
            }
            var result = try validatedMessagesResponse(parseMessagesResponse(httpResponse.body))
            result.warnings.append(Self.visionDegradationWarning)
            return result
        }
    }

    public func streamComplete(_ request: AgentModelRequest) -> AsyncThrowingStream<AgentModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard config.featureOptions.streamingEnabled,
                          streamingCompatibility.shouldAttemptStreaming,
                          let sseClient else {
                        continuation.yield(.completed(try await complete(request)))
                        continuation.finish()
                        return
                    }
                    do {
                        let httpRequest = try makeMessagesRequest(request, stream: true)
                        let frames = try await sseClient.stream(httpRequest)
                        let parser = AnthropicSSEParser()
                        var accumulator = AnthropicStreamAccumulator()
                        var receivedMessageStop = false
                        for try await frame in frames {
                            for event in parser.parse(frame) {
                                if case .error(let message) = event {
                                    continuation.finish(throwing: AnthropicCompatibleProviderError.streamError(message))
                                    return
                                }
                                if case .messageStop = event { receivedMessageStop = true }
                                if let mapped = accumulator.append(event) {
                                    if case .completed(let response) = mapped {
                                        if shouldFallbackFromEmptyStream(response) {
                                            streamingCompatibility.markIncompatible()
                                            continuation.yield(.completed(try await complete(request)))
                                        } else {
                                            continuation.yield(.completed(try validatedMessagesResponse(response)))
                                        }
                                        continuation.finish()
                                        return
                                    }
                                    continuation.yield(mapped)
                                }
                            }
                        }
                        guard receivedMessageStop else {
                            try await recoverFromPrematureStreamEnd(request, continuation: continuation)
                            return
                        }
                        let response = accumulator.response()
                        if shouldFallbackFromEmptyStream(response) {
                            streamingCompatibility.markIncompatible()
                            continuation.yield(.completed(try await complete(request)))
                        } else {
                            continuation.yield(.completed(try validatedMessagesResponse(response)))
                        }
                        continuation.finish()
                    } catch AnthropicCompatibleProviderError.unsupportedVisionInput {
                        guard request.containsImageInput else { throw AnthropicCompatibleProviderError.unsupportedVisionInput(model: capabilityProfile.modelID, reason: "vision not supported") }
                        let stripped = request.stripImageContent()
                        let httpRequest = try makeMessagesRequest(stripped, stream: true)
                        let frames = try await sseClient.stream(httpRequest)
                        let parser = AnthropicSSEParser()
                        var accumulator = AnthropicStreamAccumulator()
                        var receivedMessageStop = false
                        for try await frame in frames {
                            for event in parser.parse(frame) {
                                if case .error(let message) = event {
                                    continuation.finish(throwing: AnthropicCompatibleProviderError.streamError(message))
                                    return
                                }
                                if case .messageStop = event { receivedMessageStop = true }
                                if let mapped = accumulator.append(event) {
                                    if case .completed(var response) = mapped {
                                        if shouldFallbackFromEmptyStream(response) {
                                            streamingCompatibility.markIncompatible()
                                            response = try await complete(request)
                                        } else {
                                            response = try validatedMessagesResponse(response)
                                        }
                                        response.warnings.append(Self.visionDegradationWarning)
                                        continuation.yield(.completed(response))
                                        continuation.finish()
                                        return
                                    } else {
                                        continuation.yield(mapped)
                                    }
                                }
                            }
                        }
                        guard receivedMessageStop else {
                            if isNativeAnthropicEndpoint {
                                throw AnthropicCompatibleProviderError.streamError("Anthropic stream ended before message_stop.")
                            }
                            streamingCompatibility.markIncompatible()
                            var response = try await complete(request)
                            response.warnings.append(Self.visionDegradationWarning)
                            continuation.yield(.completed(response))
                            continuation.finish()
                            return
                        }
                        var finalResponse = accumulator.response()
                        if shouldFallbackFromEmptyStream(finalResponse) {
                            streamingCompatibility.markIncompatible()
                            finalResponse = try await complete(request)
                        } else {
                            finalResponse = try validatedMessagesResponse(finalResponse)
                        }
                        finalResponse.warnings.append(Self.visionDegradationWarning)
                        continuation.yield(.completed(finalResponse))
                        continuation.finish()
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
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
            "messages": anthropicMessages(for: AgentModelMessageProtocolRepair.repairing(request.messages))
        ]
        if stream { body["stream"] = true }
        if let thinking = config.featureOptions.thinking {
            body["thinking"] = isXiaomiMiMoEndpoint ? ["type": "enabled"] : thinking.jsonObject
        } else if isXiaomiMiMoEndpoint {
            body["thinking"] = ["type": "disabled"]
        }
        if !isXiaomiMiMoEndpoint, let effort = config.featureOptions.effort {
            body["output_config"] = ["effort": effort]
        }
        if !isXiaomiMiMoEndpoint, let cache = config.featureOptions.promptCache.jsonObject {
            body["cache_control"] = cache
        }
        if let system = anthropicSystem(for: request) {
            body["system"] = system
        }
        if !request.tools.isEmpty || !config.featureOptions.serverTools.isEmpty {
            var tools: [[String: Any]] = request.tools.map { tool in
                var object: [String: Any] = [
                    "name": tool.name,
                    "description": tool.description,
                    "input_schema": tool.inputSchema.jsonObject
                ]
                if config.featureOptions.strictToolUseEnabled && !isXiaomiMiMoEndpoint { object["strict"] = true }
                if !tool.inputExamples.isEmpty,
                   !isXiaomiMiMoEndpoint,
                   (isNativeAnthropicEndpoint || config.featureOptions.strictToolUseEnabled) {
                    object["input_examples"] = tool.inputExamples.map { $0.mapValues(\.jsonCompatibleObject) }
                }
                if !isXiaomiMiMoEndpoint,
                   config.featureOptions.eagerInputStreamingToolNames.contains(tool.name) {
                    object["eager_input_streaming"] = true
                }
                if !isXiaomiMiMoEndpoint,
                   config.featureOptions.cachedToolNames.contains(tool.name) {
                    object["cache_control"] = ["type": "ephemeral"]
                }
                if isXiaomiMiMoEndpoint { object["type"] = "custom" }
                return object
            }
            tools.append(contentsOf: config.featureOptions.serverTools.map(\.jsonObject))
            body["tools"] = tools
            if request.toolChoice == .required {
                body["tool_choice"] = ["type": "any"]
            }
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

    private func validatedMessagesResponse(_ response: AgentModelResponse) throws -> AgentModelResponse {
        guard Self.hasAssistantOutput(response) || response.providerMetadata?.stopReason != nil else {
            throw AnthropicCompatibleProviderError.missingAssistantMessage
        }
        return response
    }

    private func recoverFromPrematureStreamEnd(
        _ request: AgentModelRequest,
        continuation: AsyncThrowingStream<AgentModelStreamEvent, Error>.Continuation
    ) async throws {
        guard !isNativeAnthropicEndpoint else {
            throw AnthropicCompatibleProviderError.streamError("Anthropic stream ended before message_stop.")
        }
        streamingCompatibility.markIncompatible()
        continuation.yield(.completed(try await complete(request)))
        continuation.finish()
    }

    private func shouldFallbackFromEmptyStream(_ response: AgentModelResponse) -> Bool {
        !isNativeAnthropicEndpoint
            && !Self.hasAssistantOutput(response)
            && response.providerMetadata?.stopReason == nil
            && response.usage == nil
    }

    private static func hasAssistantOutput(_ response: AgentModelResponse) -> Bool {
        response.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || !response.toolCalls.isEmpty
    }

    private func anthropicSystem(for request: AgentModelRequest) -> Any? {
        let indexed = request.messages.enumerated().compactMap { index, message -> (Int, String)? in
            guard message.role == .system else { return nil }
            let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return content.isEmpty ? nil : (index, content)
        }
        guard !indexed.isEmpty else { return nil }
        guard config.featureOptions.promptCache.enabled,
              let breakpoint = request.promptCacheContext?.explicitBreakpointIndex,
              let cachedIndex = indexed.lastIndex(where: { $0.0 < breakpoint }) else {
            return indexed.map(\.1).joined(separator: "\n\n")
        }
        return indexed.enumerated().map { offset, entry -> [String: Any] in
            var block: [String: Any] = ["type": "text", "text": entry.1]
            if offset == cachedIndex, let cache = config.featureOptions.promptCache.jsonObject {
                block["cache_control"] = cache
            }
            return block
        }
    }

    private func anthropicMessages(for messages: [AgentModelMessage]) -> [[String: Any]] {
        var result: [[String: Any]] = []

        func appendMessage(role: String, content: [[String: Any]]) {
            guard !content.isEmpty else { return }
            if let lastIndex = result.indices.last,
               result[lastIndex]["role"] as? String == role,
               var existing = result[lastIndex]["content"] as? [[String: Any]] {
                existing.append(contentsOf: content)
                result[lastIndex]["content"] = Self.normalizedContentOrder(existing, role: role)
            } else {
                result.append(["role": role, "content": Self.normalizedContentOrder(content, role: role)])
            }
        }

        var index = messages.startIndex
        while index < messages.endIndex {
            let message = messages[index]
            switch message.role {
            case .system:
                index = messages.index(after: index)
            case .user:
                appendMessage(role: "user", content: contentBlocks(for: message))
                index = messages.index(after: index)
            case .assistant:
                appendMessage(role: "assistant", content: anthropicAssistantContent(for: message))
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
                appendMessage(role: "user", content: content)
            }
        }
        return result
    }

    private static func normalizedContentOrder(_ blocks: [[String: Any]], role: String) -> [[String: Any]] {
        switch role {
        case "assistant":
            let thinkingTypes: Set<String> = ["thinking", "redacted_thinking"]
            return blocks.filter { thinkingTypes.contains($0["type"] as? String ?? "") }
                + blocks.filter { !thinkingTypes.contains($0["type"] as? String ?? "") }
        case "user":
            return blocks.filter { $0["type"] as? String == "tool_result" }
                + blocks.filter { $0["type"] as? String != "tool_result" }
        default:
            return blocks
        }
    }

    private func anthropicAssistantContent(for message: AgentModelMessage) -> [[String: Any]] {
        if message.providerMetadata?.providerID == "anthropic-compatible",
           let raw = message.providerMetadata?.rawAssistantContentJSON,
           let data = raw.data(using: .utf8),
           var blocks = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            blocks.removeAll { Self.isStreamingEnvelope($0) }
            if let selectedCalls = message.toolCalls {
                let selectedIDs = Set(selectedCalls.map(\.id))
                blocks.removeAll { block in
                    block["type"] as? String == "tool_use"
                        && !((block["id"] as? String).map { selectedIDs.contains($0) } ?? false)
                }
                let existingIDs = Set(blocks.compactMap { block in
                    block["type"] as? String == "tool_use" ? block["id"] as? String : nil
                })
                blocks.append(contentsOf: selectedCalls.filter { !existingIDs.contains($0.id) }.map(toolUseBlock))
            }
            return blocks
        }
        var content: [[String: Any]] = []
        let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { content.append(["type": "text", "text": text]) }
        content.append(contentsOf: (message.toolCalls ?? []).map(toolUseBlock))
        return content
    }

    private func toolUseBlock(for toolCall: AgentToolCall) -> [String: Any] {
        let inputObject = (try? JSONSerialization.jsonObject(with: Data(toolCall.argumentsJSON.utf8))) ?? [:]
        return [
            "type": "tool_use",
            "id": toolCall.id,
            "name": toolCall.name,
            "input": inputObject
        ]
    }

    private static func isStreamingEnvelope(_ block: [String: Any]) -> Bool {
        switch block["type"] as? String {
        case "message_start", "content_block_start", "content_block_delta", "content_block_stop", "message_delta", "message_stop", "ping", "error":
            return true
        default:
            return false
        }
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
        return message.content.isEmpty ? [] : [["type": "text", "text": message.content]]
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

    private func messagesEndpoint() -> URL {
        if config.baseURL.lastPathComponent == "messages" {
            return config.baseURL
        }
        if isXiaomiMiMoEndpoint {
            var components = URLComponents(url: config.baseURL, resolvingAgainstBaseURL: false)
            components?.path = "/anthropic/v1/messages"
            components?.query = nil
            components?.fragment = nil
            if let url = components?.url { return url }
        }
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
        if !isXiaomiMiMoEndpoint, !config.featureOptions.betaHeaders.isEmpty {
            headers["anthropic-beta"] = config.featureOptions.betaHeaders.joined(separator: ",")
        } else if isXiaomiMiMoEndpoint {
            headers.removeValue(forKey: "anthropic-beta")
        }
        switch config.authHeaderKind {
        case .xAPIKey:
            headers[isXiaomiMiMoEndpoint ? "api-key" : "x-api-key"] = config.apiKey
            if isXiaomiMiMoEndpoint { headers.removeValue(forKey: "x-api-key") }
            headers.removeValue(forKey: "Authorization")
        case .bearer:
            headers["Authorization"] = "Bearer \(config.apiKey)"
            headers.removeValue(forKey: "x-api-key")
        }
        return headers
    }

    private var isXiaomiMiMoEndpoint: Bool {
        let host = config.baseURL.host?.lowercased()
        return host == "api.xiaomimimo.com" || host == "token-plan-cn.xiaomimimo.com"
    }

    private var isNativeAnthropicEndpoint: Bool {
        config.baseURL.host?.lowercased() == "api.anthropic.com"
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
        let usage = AnthropicStreamAccumulator.usage(from: usageObject)
        let stopReason = object["stop_reason"] as? String
        let finishReason = AgentModelFinishReason.anthropic(stopReason: stopReason)
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
