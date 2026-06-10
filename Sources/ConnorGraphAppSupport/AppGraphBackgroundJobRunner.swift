import Foundation
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphSearch
import ConnorGraphStore

private struct AppLLMGraphExtractionClient: GraphExtractionLLMClient, Sendable {
    var provider: AnyAgentModelProvider
    var providerName: String
    var promptVersion: String

    func completeExtraction(prompt: String) async throws -> GraphExtractionLLMResponse {
        let startedAt = Date()
        let response = try await provider.complete(AgentModelRequest(
            messages: [
                AgentModelMessage(
                    role: .system,
                    content: "You extract structured graph memory. Return only JSON that conforms to the user prompt schema."
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
        return GraphExtractionLLMResponse(
            text: text,
            provider: providerName,
            modelID: provider.modelID,
            promptVersion: promptVersion,
            promptTokens: response.usage?.promptTokens,
            completionTokens: response.usage?.completionTokens,
            totalTokens: response.usage?.totalTokens,
            latencyMilliseconds: latency,
            rawResponseID: Self.rawResponseID(from: response.rawResponseJSON),
            rawResponseJSON: response.rawResponseJSON,
            metadata: ["finish_reason": response.finishReason.rawValue]
        )
    }

    private static func rawResponseID(from rawResponseJSON: String?) -> String? {
        guard let rawResponseJSON,
              let data = rawResponseJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object["id"] as? String
    }
}

/// App-level wrapper for `GraphBackgroundJobRunner` that provides a simple
/// interface for running queued background jobs (extraction, index refresh,
/// anomaly resolution, entity merge review).
///
/// Defaults to a safe stub extractor. When LLM settings contain a valid
/// OpenAI-compatible provider configuration, the app can construct an
/// LLM-backed extractor that produces validated extraction drafts. Extraction
/// drafts still flow through the store-side optimistic write pipeline; future
/// review-queue work should route them through `GraphWriteCandidate` before
/// trusted graph commits.
public struct AppGraphBackgroundJobRunner: @unchecked Sendable {
    public let runner: GraphBackgroundJobRunner<AnyGraphExtractorProvider>
    public let graphID: String

    public init(store: SQLiteGraphKernelStore, graphID: String = "default") {
        self.init(store: store, graphID: graphID, extractor: AnyGraphExtractorProvider(StubGraphExtractor()))
    }

    public init(store: SQLiteGraphKernelStore, graphID: String = "default", settingsRepository: AppLLMSettingsRepository) {
        let extractor = Self.makeExtractor(settingsRepository: settingsRepository)
        self.init(store: store, graphID: graphID, extractor: extractor)
    }

    public init(store: SQLiteGraphKernelStore, graphID: String = "default", extractor: AnyGraphExtractorProvider) {
        self.runner = GraphBackgroundJobRunner(store: store, extractor: extractor)
        self.graphID = graphID
    }

    /// Run a single available job. Returns nil if no jobs are queued.
    public func runOnce(now: Date = Date()) async throws -> GraphBackgroundJobRunResult? {
        try await runner.runOnce(graphID: graphID, now: now)
    }

    /// Run up to `limit` available jobs. Returns results for each job processed.
    @discardableResult
    public func runAvailable(now: Date = Date(), limit: Int = 10) async throws -> [GraphBackgroundJobRunResult] {
        try await runner.runAvailable(graphID: graphID, now: now, limit: limit)
    }

    private static func makeExtractor(settingsRepository: AppLLMSettingsRepository) -> AnyGraphExtractorProvider {
        do {
            guard let config = try settingsRepository.openAICompatibleConfig() else {
                return AnyGraphExtractorProvider(StubGraphExtractor())
            }
            let provider = AnyAgentModelProvider(OpenAICompatibleProvider(config: config))
            let client = AppLLMGraphExtractionClient(
                provider: provider,
                providerName: "openai-compatible",
                promptVersion: GraphExtractionPromptBuilder.defaultPromptVersion
            )
            return AnyGraphExtractorProvider(LLMGraphExtractor(client: client))
        } catch {
            return AnyGraphExtractorProvider(StubGraphExtractor())
        }
    }
}
