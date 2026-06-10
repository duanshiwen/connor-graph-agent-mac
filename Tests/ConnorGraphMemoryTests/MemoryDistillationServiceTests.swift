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
    #expect(result.episodeCandidates.count == 1)
    #expect(result.episodeCandidates[0].kind == .episode)
    #expect(result.episodeCandidates[0].content.contains("User: 请记住我喜欢结构化推进"))
    #expect(result.episodeCandidates[0].content.contains("Assistant: 好的，我会保持结构化。"))
    #expect(result.sourceRefs.count == 1)
    #expect(result.sourceRefs[0].messageIDs == ["user-1", "assistant-1"])
    #expect(result.trace.inputBundleCount == 1)
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
