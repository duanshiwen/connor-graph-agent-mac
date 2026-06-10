import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory

private enum StubMemoryDistillationError: Error {
    case failed
}

@Test func llmMemoryDistillerDecodesStructuredCandidates() async throws {
    let now = Date(timeIntervalSince1970: 1_000)
    let bundle = ConversationTurnBundle(
        id: "bundle-preference",
        sessionID: "session-1",
        userMessages: [ConversationTurnMessage(id: "user-1", role: .user, content: "请记住我喜欢结构化推进", createdAt: now)],
        assistantMessage: ConversationTurnMessage(id: "assistant-1", role: .assistant, content: "已记录。", createdAt: now),
        startedAt: now,
        closedAt: now,
        status: .closed
    )
    let buffer = MemoryStagingBuffer(id: "buffer-1", sessionID: "session-1", pendingBundles: [bundle])
    let json = """
    {
      "candidates": [
        {
          "kind": "preference",
          "title": "结构化推进偏好",
          "content": "诗闻喜欢结构化推进，并希望回答保持清晰层次。",
          "rationale": "用户明确要求记住该偏好。",
          "importance": 0.9,
          "confidence": 0.85,
          "source_bundle_id": "bundle-preference",
          "source_message_ids": ["user-1"],
          "metadata": {"source": "test"}
        }
      ],
      "discarded_items": []
    }
    """
    let client = ClosureMemoryDistillationLLMClient(completion: { _ in
        MemoryDistillationLLMResponse(
            text: json,
            provider: "stub",
            modelID: "stub-memory",
            promptVersion: MemoryDistillationPromptBuilder.defaultPromptVersion
        )
    })
    let distiller = LLMMemoryDistiller(client: client)

    let result = await distiller.distill(buffer: buffer, at: now, triggerReasons: [.explicitRememberRequest])

    #expect(result.preferenceCandidates.count == 1)
    #expect(result.preferenceCandidates[0].metadata["candidate_origin"] == "llm_memory_distiller")
    #expect(result.preferenceCandidates[0].metadata["classification_method"] == "llm")
    #expect(result.sourceRefs.count == 1)
    #expect(result.trace.metadata["distiller"] == "llm")
    #expect(result.trace.triggerReasons == [.explicitRememberRequest])
}

@Test func llmMemoryDistillerFallsBackToDeterministicDistillerOnFailure() async throws {
    let bundle = ConversationTurnBundle(
        id: "bundle-fallback",
        sessionID: "session-1",
        userMessages: [ConversationTurnMessage(id: "user-1", role: .user, content: "请记住我喜欢结构化推进")],
        assistantMessage: ConversationTurnMessage(id: "assistant-1", role: .assistant, content: "已记录。"),
        status: .closed
    )
    let buffer = MemoryStagingBuffer(id: "buffer-1", sessionID: "session-1", pendingBundles: [bundle])
    let client = ClosureMemoryDistillationLLMClient(completion: { _ in
        throw StubMemoryDistillationError.failed
    })
    let distiller = LLMMemoryDistiller(client: client)

    let result = await distiller.distill(buffer: buffer)

    #expect(result.preferenceCandidates.count == 1)
    #expect(result.trace.metadata["distiller"] == "deterministic_fallback")
    #expect(result.trace.metadata["llm_distiller_error"] != nil)
}
