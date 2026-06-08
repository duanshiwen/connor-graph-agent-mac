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

public struct OpenAICompatibleProvider<Client: AgentHTTPClient>: LLMProvider, Sendable {
    public var config: OpenAICompatibleConfig
    public var httpClient: Client

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

    private func makeRequest(prompt: String, context: AgentContext) throws -> AgentHTTPRequest {
        let endpoint = config.baseURL.appendingPathComponent("chat/completions")
        let body = OpenAIChatCompletionRequest(
            model: config.model,
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

    private func parseResponse(_ data: Data) throws -> String {
        let decoded = try JSONDecoder().decode(OpenAIChatCompletionResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
            throw OpenAICompatibleProviderError.missingAssistantMessage
        }
        return content
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
}

private struct OpenAIChatMessage: Codable {
    var role: String
    var content: String
}

private struct OpenAIChatCompletionResponse: Decodable {
    var choices: [Choice]

    struct Choice: Decodable {
        var message: OpenAIChatMessage
    }
}
