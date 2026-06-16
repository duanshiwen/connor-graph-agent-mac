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

    public init(
        baseURL: URL,
        apiKey: String,
        model: String,
        authHeaderKind: AnthropicCompatibleAuthHeaderKind = .xAPIKey,
        anthropicVersion: String = "2023-06-01",
        extraHeaders: [String: String] = [:],
        maxTokens: Int = 4096
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.authHeaderKind = authHeaderKind
        self.anthropicVersion = anthropicVersion
        self.extraHeaders = extraHeaders
        self.maxTokens = maxTokens
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
    case httpStatus(Int)
    case missingAssistantMessage
}

public struct AnthropicCompatibleProvider<Client: AgentHTTPClient>: LLMProvider, AgentModelProvider, Sendable {
    public var config: AnthropicCompatibleConfig
    public var httpClient: Client

    public var modelID: String { config.requestModel }
    public var capabilities: AgentModelCapabilities {
        AgentModelCapabilities(
            supportsStreaming: false,
            supportsToolCalling: true,
            supportsParallelToolCalls: false,
            supportsStructuredOutput: false,
            supportsVision: false
        )
    }

    public init(config: AnthropicCompatibleConfig, httpClient: Client) {
        self.config = config
        self.httpClient = httpClient
    }

    public init(config: AnthropicCompatibleConfig) where Client == URLSessionAgentHTTPClient {
        self.config = config
        self.httpClient = URLSessionAgentHTTPClient()
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
            throw AnthropicCompatibleProviderError.httpStatus(httpResponse.statusCode)
        }
        return try parseMessagesResponse(httpResponse.body)
    }

    public func healthCheck() async throws -> LLMProviderHealthCheckResult {
        let response = try await complete(AgentModelRequest(messages: [
            AgentModelMessage(role: .system, content: "You are a connection health checker."),
            AgentModelMessage(role: .user, content: "Reply with exactly: OK")
        ]))
        guard let text = response.text, !text.isEmpty else { throw AnthropicCompatibleProviderError.missingAssistantMessage }
        return LLMProviderHealthCheckResult(ok: true, model: config.requestModel, message: "Connection OK: \(config.requestModel)")
    }

    private func makeMessagesRequest(_ request: AgentModelRequest) throws -> AgentHTTPRequest {
        var body: [String: Any] = [
            "model": config.requestModel,
            "max_tokens": config.maxTokens,
            "messages": request.messages.compactMap { anthropicMessage(for: $0) }
        ]
        let system = request.messages
            .filter { $0.role == .system }
            .map(\.content)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        if !system.isEmpty {
            body["system"] = system
        }
        if !request.tools.isEmpty {
            body["tools"] = request.tools.map { tool in
                [
                    "name": tool.name,
                    "description": tool.description,
                    "input_schema": tool.inputSchema.jsonObject
                ] as [String: Any]
            }
            body["tool_choice"] = ["type": "auto"]
        }
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return AgentHTTPRequest(url: messagesEndpoint(), method: "POST", headers: requestHeaders(), body: data)
    }

    private func anthropicMessage(for message: AgentModelMessage) -> [String: Any]? {
        switch message.role {
        case .system:
            return nil
        case .user:
            return ["role": "user", "content": contentBlocks(for: message)]
        case .assistant:
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
        case .tool:
            return [
                "role": "user",
                "content": [[
                    "type": "tool_result",
                    "tool_use_id": message.toolCallID ?? message.id,
                    "content": message.content
                ]]
            ]
        }
    }

    private func contentBlocks(for message: AgentModelMessage) -> [[String: Any]] {
        if let parts = message.contentParts, !parts.isEmpty {
            let blocks = parts.compactMap { part -> [String: Any]? in
                switch part.kind {
                case .text:
                    guard let text = part.text, !text.isEmpty else { return nil }
                    return ["type": "text", "text": text]
                case .imageDataURL:
                    return nil
                }
            }
            if !blocks.isEmpty { return blocks }
        }
        return [["type": "text", "text": message.content]]
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
        let usage = usageObject == nil ? nil : AgentModelUsage(promptTokens: inputTokens, completionTokens: outputTokens)
        let stopReason = object["stop_reason"] as? String
        let finishReason: AgentModelFinishReason = stopReason == "tool_use" ? .toolCalls : .stop
        let rawJSON = String(data: data, encoding: .utf8)
        return AgentModelResponse(
            text: textBlocks.isEmpty ? nil : textBlocks.joined(separator: ""),
            toolCalls: toolCalls,
            usage: usage,
            finishReason: finishReason,
            rawResponseJSON: rawJSON
        )
    }
}
