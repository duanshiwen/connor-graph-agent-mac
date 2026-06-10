import Foundation
import ConnorGraphAgent
import ConnorGraphMemory

public struct AppLLMMemoryDistillationClient: MemoryDistillationLLMClient, Sendable {
    public var provider: AnyAgentModelProvider
    public var providerName: String
    public var promptVersion: String

    public init(
        provider: AnyAgentModelProvider,
        providerName: String = "openai-compatible",
        promptVersion: String = MemoryDistillationPromptBuilder.defaultPromptVersion
    ) {
        self.provider = provider
        self.providerName = providerName
        self.promptVersion = promptVersion
    }

    public func completeDistillation(prompt: String) async throws -> MemoryDistillationLLMResponse {
        let startedAt = Date()
        let response = try await provider.complete(AgentModelRequest(
            messages: [
                AgentModelMessage(
                    role: .system,
                    content: "You are a strict memory distillation engine. Return only valid JSON matching the user schema."
                ),
                AgentModelMessage(role: .user, content: prompt)
            ],
            tools: [],
            temperature: 0.1
        ))
        let latency = Int(Date().timeIntervalSince(startedAt) * 1000)
        guard let text = response.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenAICompatibleProviderError.missingAssistantMessage
        }
        return MemoryDistillationLLMResponse(
            text: text,
            provider: providerName,
            modelID: provider.modelID,
            promptVersion: promptVersion,
            promptTokens: response.usage?.promptTokens,
            completionTokens: response.usage?.completionTokens,
            totalTokens: response.usage?.totalTokens,
            latencyMilliseconds: latency,
            metadata: ["finish_reason": response.finishReason.rawValue]
        )
    }
}

public typealias AppLLMMemoryDistiller = LLMMemoryDistiller<AppLLMMemoryDistillationClient>
