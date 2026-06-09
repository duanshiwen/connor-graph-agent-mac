import Foundation
import ConnorGraphSearch
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct OpenAICompatibleConfig: Sendable, Equatable {
    public var baseURL: URL
    public var apiKey: String
    public var model: String

    public init(baseURL: URL, apiKey: String, model: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
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
    case httpStatus(Int)
    case missingAssistantMessage
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

    public init(url: URL, method: String, headers: [String: String], body: Data) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
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
        var urlRequest = URLRequest(url: request.url)
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

public struct OpenAICompatibleProvider<Client: AgentHTTPClient>: LLMProvider, AgentModelProvider, Sendable {
    public var config: OpenAICompatibleConfig
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

    public init(config: OpenAICompatibleConfig, httpClient: Client) {
        self.config = config
        self.httpClient = httpClient
    }

    public func complete(prompt: String, context: AgentContext) async throws -> LLMResponse {
        var client = httpClient
        let request = try makeRequest(prompt: prompt, context: context)
        let response = try await client.send(request)
        if response.statusCode < 200 || response.statusCode >= 300 {
            throw OpenAICompatibleProviderError.httpStatus(response.statusCode)
        }
        let text = try parseResponse(response.body)
        return LLMResponse(text: text, citations: context.items.map(\.sourceID))
    }

    public func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse {
        try await completeWithTools(request)
    }

    public func completeWithTools(_ modelRequest: AgentModelRequest) async throws -> AgentModelResponse {
        var client = httpClient
        let request = try makeToolCallingRequest(modelRequest)
        let response = try await client.send(request)
        if response.statusCode < 200 || response.statusCode >= 300 {
            throw OpenAICompatibleProviderError.httpStatus(response.statusCode)
        }
        return try parseToolCallingResponse(response.body)
    }

    public func healthCheck() async throws -> LLMProviderHealthCheckResult {
        let context = AgentContext(query: "provider-health-check", items: [])
        let response = try await complete(prompt: "Reply with exactly: OK", context: context)
        return LLMProviderHealthCheckResult(
            ok: !response.text.isEmpty,
            model: config.requestModel,
            message: "Connection OK: \(config.requestModel)"
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
            temperature: 0.2
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return AgentHTTPRequest(
            url: endpoint,
            method: "POST",
            headers: [
                "Authorization": "Bearer \(config.apiKey)",
                "Content-Type": "application/json"
            ],
            body: try encoder.encode(body)
        )
    }

    private var systemPrompt: String {
        """
        You are Connor Graph Agent, a graph-backed assistant. Answer using the provided graph context when relevant. If context is insufficient, say what is missing. Keep citations implicit in the response; the runtime tracks source IDs separately.
        """
    }

    private func makeToolCallingRequest(_ request: AgentModelRequest) throws -> AgentHTTPRequest {
        let endpoint = config.baseURL.appendingPathComponent("chat/completions")
        let messages = request.messages.map { message in
            OpenAIChatMessage(role: message.role.rawValue, content: message.content, toolCallID: message.toolCallID, name: message.name)
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
            toolChoice: tools.isEmpty ? nil : "auto"
        )
        let data = try JSONSerialization.data(withJSONObject: try body.jsonObject(), options: [.sortedKeys])
        return AgentHTTPRequest(
            url: endpoint,
            method: "POST",
            headers: ["Authorization": "Bearer \(config.apiKey)", "Content-Type": "application/json"],
            body: data
        )
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
}

public extension OpenAICompatibleProvider where Client == URLSessionAgentHTTPClient {
    init(config: OpenAICompatibleConfig) {
        self.init(config: config, httpClient: URLSessionAgentHTTPClient())
    }
}

private struct OpenAIChatCompletionRequest: Encodable {
    var model: String
    var messages: [OpenAIChatMessage]
    var temperature: Double
    var tools: [OpenAIToolDefinition]?
    var toolChoice: String?

    init(model: String, messages: [OpenAIChatMessage], temperature: Double, tools: [OpenAIToolDefinition]? = nil, toolChoice: String? = nil) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.tools = tools
        self.toolChoice = toolChoice
    }

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case tools
        case toolChoice = "tool_choice"
    }

    func jsonObject() throws -> [String: Any] {
        let data = try JSONEncoder().encode(self)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}

private struct OpenAIChatMessage: Codable {
    var role: String
    var content: String?
    var toolCallID: String?
    var name: String?
    var toolCalls: [OpenAIToolCall]?

    init(role: String, content: String? = nil, toolCallID: String? = nil, name: String? = nil, toolCalls: [OpenAIToolCall]? = nil) {
        self.role = role
        self.content = content
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
        case let int as Int:
            var container = encoder.singleValueContainer(); try container.encode(int)
        case let double as Double:
            var container = encoder.singleValueContainer(); try container.encode(double)
        case let bool as Bool:
            var container = encoder.singleValueContainer(); try container.encode(bool)
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
