import Foundation
import ConnorGraphSearch

public struct AnyLLMProvider: LLMProvider, Sendable {
    private let completion: @Sendable (String, AgentContext) async throws -> LLMResponse

    public init(_ completion: @escaping @Sendable (String, AgentContext) async throws -> LLMResponse) {
        self.completion = completion
    }

    public init<Provider: LLMProvider>(_ provider: Provider) {
        self.completion = { prompt, context in
            try await provider.complete(prompt: prompt, context: context)
        }
    }

    public func complete(prompt: String, context: AgentContext) async throws -> LLMResponse {
        try await completion(prompt, context)
    }
}
