import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory

@Test func memoryIngestionCreatesOpenBundleForUserMessageThenClosesItWithAssistantMessage() throws {
    let base = Date(timeIntervalSince1970: 10_000)
    let service = MemoryIngestionService()
    let user = AgentMessage(id: "u1", role: .user, content: "请继续设计 memory staging", createdAt: base)
    let assistant = AgentMessage(id: "a1", role: .assistant, content: "好的，下一步是 ingestion service。", createdAt: base.addingTimeInterval(5))

    let userResult = service.ingestUserMessage(user, sessionID: "session-1")
    #expect(userResult.buffer.pendingBundles.count == 1)
    #expect(userResult.buffer.pendingBundles[0].status == .open)
    #expect(userResult.buffer.pendingBundles[0].userMessages.map(\.id) == ["u1"])

    let assistantResult = service.ingestAssistantMessage(assistant, sessionID: "session-1", into: userResult.buffer)

    #expect(assistantResult.buffer.pendingBundles.count == 1)
    #expect(assistantResult.buffer.pendingBundles[0].status == .closed)
    #expect(assistantResult.buffer.pendingBundles[0].assistantMessage?.id == "a1")
    #expect(assistantResult.appendedBundleIDs.isEmpty)
    #expect(assistantResult.updatedBundleIDs.count == 1)
}

@Test func memoryIngestionGroupsFullSessionAndDeduplicatesExistingMessages() throws {
    let base = Date(timeIntervalSince1970: 11_000)
    let service = MemoryIngestionService()
    let session = AgentSession(
        id: "session-2",
        messages: [
            AgentMessage(id: "u1", role: .user, content: "第一条", createdAt: base),
            AgentMessage(id: "u2", role: .user, content: "补充", createdAt: base.addingTimeInterval(1)),
            AgentMessage(id: "a1", role: .assistant, content: "回复", createdAt: base.addingTimeInterval(2))
        ],
        createdAt: base,
        updatedAt: base.addingTimeInterval(2)
    )

    let first = service.ingest(session: session)
    let second = service.ingest(session: session, into: first.buffer)

    #expect(first.buffer.pendingBundles.count == 1)
    #expect(first.buffer.pendingBundles[0].userMessages.map(\.id) == ["u1", "u2"])
    #expect(first.buffer.pendingBundles[0].assistantMessage?.id == "a1")
    #expect(second.buffer.pendingBundles.count == 1)
    #expect(second.appendedBundleIDs.isEmpty)
    #expect(second.updatedBundleIDs.isEmpty)
}

@Test func memoryIngestionAttachesArtifactsToCurrentOpenBundle() throws {
    let base = Date(timeIntervalSince1970: 12_000)
    let service = MemoryIngestionService()
    let user = AgentMessage(id: "u1", role: .user, content: "分析这个网页", createdAt: base)
    let artifact = MemoryStagingArtifact(
        id: "browser-1",
        kind: .browserContext,
        content: "网页正文",
        summary: "网页摘要",
        createdAt: base.addingTimeInterval(1)
    )

    let result = service.ingestUserMessage(user, sessionID: "session-3", artifacts: [artifact])

    #expect(result.buffer.pendingBundles.count == 1)
    #expect(result.buffer.pendingBundles[0].userMessages.map(\.id) == ["u1"])
    #expect(result.buffer.pendingBundles[0].artifacts.map(\.id) == ["browser-1"])
}

@Test func memoryIngestionCreatesArtifactOnlyOpenBundleWhenNoMessageExists() throws {
    let base = Date(timeIntervalSince1970: 13_000)
    let service = MemoryIngestionService()
    let artifact = MemoryStagingArtifact(
        id: "file-1",
        kind: .attachment,
        content: "文件内容",
        createdAt: base
    )
    let session = AgentSession(id: "session-4", messages: [], createdAt: base, updatedAt: base)

    let result = service.ingest(session: session, artifacts: [artifact])

    #expect(result.buffer.pendingBundles.count == 1)
    #expect(result.buffer.pendingBundles[0].userMessages.isEmpty)
    #expect(result.buffer.pendingBundles[0].artifacts.map(\.id) == ["file-1"])
    #expect(result.buffer.pendingBundles[0].status == .open)
}

@Test func memoryIngestionReturnsTriggerReasonsAfterUpdatingTokenEstimate() throws {
    let base = Date(timeIntervalSince1970: 14_000)
    let service = MemoryIngestionService()
    let policy = MemoryStagingTriggerPolicy(bundleBatchSize: 10, idleInterval: 60, tokenBudget: 5)
    let buffer = MemoryStagingBuffer(sessionID: "session-5", triggerPolicy: policy)
    let session = AgentSession(
        id: "session-5",
        messages: [AgentMessage(id: "u1", role: .user, content: "这是一段超过 token budget 粗略估算阈值的文本", createdAt: base)],
        createdAt: base,
        updatedAt: base
    )

    let result = service.ingest(
        session: session,
        into: buffer,
        options: MemoryIngestionOptions(explicitRememberRequest: true, now: base.addingTimeInterval(120))
    )

    #expect(result.triggerReasons.contains(.explicitRememberRequest))
    #expect(result.triggerReasons.contains(.sessionIdle))
    #expect(result.triggerReasons.contains(.tokenBudgetExceeded))
}
