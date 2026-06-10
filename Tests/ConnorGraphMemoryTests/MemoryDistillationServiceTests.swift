import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory

@Test func memoryDistillationServiceCreatesEpisodeCandidateForClosedBundle() throws {
    let now = Date(timeIntervalSince1970: 1_000)
    let user = ConversationTurnMessage(id: "user-1", role: .user, content: "请记住我喜欢结构化推进", createdAt: now)
    let assistant = ConversationTurnMessage(id: "assistant-1", role: .assistant, content: "好的，我会保持结构化。", createdAt: now)
    let bundle = ConversationTurnBundle(
        id: "bundle-1",
        sessionID: "session-1",
        userMessages: [user],
        assistantMessage: assistant,
        startedAt: now,
        closedAt: now,
        status: .closed
    )
    let buffer = MemoryStagingBuffer(id: "buffer-1", sessionID: "session-1", pendingBundles: [bundle])

    let result = MemoryDistillationService().distill(buffer: buffer, at: now)

    #expect(result.sessionID == "session-1")
    #expect(result.sourceBufferID == "buffer-1")
    #expect(result.preferenceCandidates.count == 1)
    #expect(result.preferenceCandidates[0].kind == .preference)
    #expect(result.preferenceCandidates[0].content.contains("User: 请记住我喜欢结构化推进"))
    #expect(result.preferenceCandidates[0].content.contains("Assistant: 好的，我会保持结构化。"))
    #expect(result.sourceRefs.count == 1)
    #expect(result.sourceRefs[0].messageIDs == ["user-1", "assistant-1"])
    #expect(result.trace.inputBundleCount == 1)
}

@Test func memoryDistillationServiceClassifiesPreferencesAndDecisions() throws {
    let now = Date(timeIntervalSince1970: 1_000)
    let preferenceBundle = ConversationTurnBundle(
        id: "bundle-preference",
        sessionID: "session-1",
        userMessages: [ConversationTurnMessage(id: "user-preference", role: .user, content: "请记住我喜欢结构化推进", createdAt: now)],
        assistantMessage: ConversationTurnMessage(id: "assistant-preference", role: .assistant, content: "已记录这个偏好。", createdAt: now),
        startedAt: now,
        closedAt: now,
        status: .closed
    )
    let decisionBundle = ConversationTurnBundle(
        id: "bundle-decision",
        sessionID: "session-1",
        userMessages: [ConversationTurnMessage(id: "user-decision", role: .user, content: "我们决定采用 SQLite 作为 staging buffer 的持久化层", createdAt: now)],
        assistantMessage: ConversationTurnMessage(id: "assistant-decision", role: .assistant, content: "这个决策已进入后台记忆。", createdAt: now),
        startedAt: now,
        closedAt: now,
        status: .closed
    )
    let buffer = MemoryStagingBuffer(id: "buffer-1", sessionID: "session-1", pendingBundles: [preferenceBundle, decisionBundle])

    let result = MemoryDistillationService().distill(buffer: buffer, at: now)

    #expect(result.preferenceCandidates.count == 1)
    #expect(result.preferenceCandidates[0].metadata["classification_method"] == "deterministic_keywords")
    #expect(result.decisionCandidates.count == 1)
    #expect(result.episodeCandidates.isEmpty)
    #expect(result.proposedCandidates.count == 2)
}

@Test func memoryDistillationServiceRejectsLowValueChitChat() throws {
    let bundle = ConversationTurnBundle(
        id: "bundle-low-value",
        sessionID: "session-1",
        userMessages: [ConversationTurnMessage(id: "user-low", role: .user, content: "好")],
        assistantMessage: ConversationTurnMessage(id: "assistant-low", role: .assistant, content: "好的"),
        status: .closed
    )
    let buffer = MemoryStagingBuffer(id: "buffer-1", sessionID: "session-1", pendingBundles: [bundle])

    let result = MemoryDistillationService().distill(buffer: buffer)

    #expect(result.proposedCandidates.isEmpty)
    #expect(result.discardedItems.count == 1)
    #expect(result.discardedItems[0].reason == "quality_gate_rejected")
}

@Test func memoryDistillationServiceDiscardsOpenBundles() throws {
    let openBundle = ConversationTurnBundle(
        id: "bundle-open",
        sessionID: "session-1",
        userMessages: [ConversationTurnMessage(id: "user-1", role: .user, content: "未完成的问题")],
        status: .open
    )
    let buffer = MemoryStagingBuffer(id: "buffer-1", sessionID: "session-1", pendingBundles: [openBundle])

    let result = MemoryDistillationService().distill(buffer: buffer)

    #expect(result.episodeCandidates.isEmpty)
    #expect(result.discardedItems.count == 1)
    #expect(result.discardedItems[0].reason == "bundle_not_closed")
}
