import Foundation
import ConnorGraphCore

public protocol GraphExtractionLLMClient: Sendable {
    func completeExtraction(prompt: String) async throws -> String
}

public struct LLMGraphExtractor<Client: GraphExtractionLLMClient>: GraphExtractorProvider, Sendable {
    public var client: Client
    public var promptBuilder: GraphExtractionPromptBuilder
    public var decoder: GraphExtractionDecoder

    public init(
        client: Client,
        promptBuilder: GraphExtractionPromptBuilder = GraphExtractionPromptBuilder(),
        decoder: GraphExtractionDecoder = GraphExtractionDecoder()
    ) {
        self.client = client
        self.promptBuilder = promptBuilder
        self.decoder = decoder
    }

    public func extract(from source: GraphExtractionSource) async throws -> GraphExtractionDraft {
        let prompt = promptBuilder.buildPrompt(for: source)
        let rawResponse = try await client.completeExtraction(prompt: prompt)
        let decoded = try decoder.decode(rawResponse)
        return try decoded.output.toDraft(source: source, requireStatementEvidence: decoder.requireStatementEvidence)
    }
}

public struct ClosureGraphExtractionLLMClient: GraphExtractionLLMClient, Sendable {
    public var completion: @Sendable (String) async throws -> String

    public init(completion: @escaping @Sendable (String) async throws -> String) {
        self.completion = completion
    }

    public func completeExtraction(prompt: String) async throws -> String {
        try await completion(prompt)
    }
}
