import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore

private struct FakeExtractionLLMClient: GraphExtractionLLMClient {
    var response: String
    var onPrompt: @Sendable (String) -> Void = { _ in }

    func completeExtraction(prompt: String) async throws -> GraphExtractionLLMResponse {
        onPrompt(prompt)
        return GraphExtractionLLMResponse(
            text: response,
            provider: "fake",
            modelID: "fake-model",
            promptVersion: "test-prompt",
            promptTokens: 10,
            completionTokens: 20,
            totalTokens: 30,
            latencyMilliseconds: 42,
            rawResponseID: "resp-test"
        )
    }
}

private func llmExtractorSource() -> GraphExtractionSource {
    GraphExtractionSource(
        id: "chat-1",
        graphID: "default",
        sourceType: .chat,
        title: "Preference",
        content: "诗闻 prefers tea.",
        occurredAt: Date(timeIntervalSince1970: 1_000)
    )
}

private let extractionResponse = """
{
  "entities": [
    {
      "localID": "shiwen",
      "name": "诗闻",
      "entityKind": "person_object",
      "scope": "personal",
      "canonicalClassID": null,
      "aliases": [],
      "summary": "",
      "confidence": 0.9,
      "evidenceSpanIDs": ["span-1"],
      "metadata": {}
    },
    {
      "localID": "tea",
      "name": "tea",
      "entityKind": "life_object",
      "scope": "personal",
      "canonicalClassID": null,
      "aliases": [],
      "summary": "",
      "confidence": 0.85,
      "evidenceSpanIDs": ["span-1"],
      "metadata": {}
    }
  ],
  "statements": [
    {
      "explicitID": null,
      "subjectLocalID": "shiwen",
      "predicate": "PREFERS",
      "objectLocalID": "tea",
      "statementText": "诗闻 prefers tea",
      "confidence": 0.88,
      "validAt": null,
      "referenceTime": null,
      "evidenceSpanIDs": ["span-1"],
      "metadata": {}
    }
  ],
  "evidenceSpans": [
    { "id": "span-1", "text": "诗闻 prefers tea.", "startOffset": null, "endOffset": null }
  ],
  "warnings": [],
  "confidence": 0.87,
  "metadata": {}
}
"""

@Test func llmGraphExtractorBuildsPromptAndConvertsResponseToDraft() async throws {
    nonisolated(unsafe) var capturedPrompt = ""
    let extractor = LLMGraphExtractor(client: FakeExtractionLLMClient(response: extractionResponse) { prompt in
        capturedPrompt = prompt
    })

    let draft = try await extractor.extract(from: llmExtractorSource())

    #expect(capturedPrompt.contains("诗闻 prefers tea."))
    #expect(draft.entities.count == 2)
    #expect(draft.statements.count == 1)
    #expect(draft.statements[0].predicate == .prefers)
    #expect(draft.metadata["llm_provider"] == "fake")
    #expect(draft.metadata["llm_model_id"] == "fake-model")
    #expect(draft.metadata["prompt_tokens"] == "10")
    #expect(draft.metadata["latency_ms"] == "42")
    #expect(draft.metadata["normalized_json"] != nil)
}

@Test func llmGraphExtractorWrapsDecoderErrorsWithResponseDiagnostics() async throws {
    let extractor = LLMGraphExtractor(client: FakeExtractionLLMClient(response: "{ not-json"))

    await #expect(throws: GraphExtractionAttemptFailure.self) {
        try await extractor.extract(from: llmExtractorSource())
    }

    do {
        _ = try await extractor.extract(from: llmExtractorSource())
        Issue.record("Expected extraction failure")
    } catch let failure as GraphExtractionAttemptFailure {
        #expect(failure.decoderErrorKind == "invalid_json")
        #expect(failure.normalizedJSON == "{ not-json")
        #expect(failure.traceMetadata["llm_model_id"] == "fake-model")
        #expect(failure.traceMetadata["decoder_error_kind"] == "invalid_json")
    }
}
