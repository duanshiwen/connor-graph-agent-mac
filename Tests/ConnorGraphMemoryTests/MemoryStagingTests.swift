import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory

@Test func conversationTurnBundlesGroupConsecutiveUserMessagesUntilAssistantReply() throws {
    let base = Date(timeIntervalSince1970: 1_000)
    let messages = [
        AgentMessage(id: "u1", role: .user, content: "第一条", createdAt: base),
        AgentMessage(id: "u2", role: .user, content: "补充一条", createdAt: base.addingTimeInterval(1)),
        AgentMessage(id: "a1", role: .assistant, content: "回复", createdAt: base.addingTimeInterval(2)),
        AgentMessage(id: "u3", role: .user, content: "下一个问题", createdAt: base.addingTimeInterval(3))
    ]

    let bundles = ConversationTurnBundle.bundles(from: messages, sessionID: "session-1")

    #expect(bundles.count == 2)
    #expect(bundles[0].userMessages.map(\.id) == ["u1", "u2"])
    #expect(bundles[0].assistantMessage?.id == "a1")
    #expect(bundles[0].status == .closed)
    #expect(bundles[1].userMessages.map(\.id) == ["u3"])
    #expect(bundles[1].assistantMessage == nil)
    #expect(bundles[1].status == .open)
}

@Test func conversationTurnBundleCanCarryArtifactsAndCloseWithAssistantMessage() throws {
    let startedAt = Date(timeIntervalSince1970: 2_000)
    var bundle = ConversationTurnBundle(sessionID: "session-2", startedAt: startedAt)
    bundle.appendUserMessage("请分析这个网页", id: "u1", createdAt: startedAt)
    bundle.appendArtifact(
        MemoryStagingArtifact(
            id: "browser-1",
            kind: .browserContext,
            content: "网页正文",
            summary: "网页摘要"
        )
    )
    bundle.close(assistantContent: "分析结果", id: "a1", closedAt: startedAt.addingTimeInterval(5))

    #expect(bundle.messageCount == 2)
    #expect(bundle.artifacts.count == 1)
    #expect(bundle.artifacts[0].kind == .browserContext)
    #expect(bundle.isClosed)
    #expect(bundle.assistantMessage?.content == "分析结果")
}

@Test func memoryStagingBufferTriggersOnBatchSizeIdleSessionCloseRememberHighValueAndTokenBudget() throws {
    let base = Date(timeIntervalSince1970: 3_000)
    let policy = MemoryStagingTriggerPolicy(
        bundleBatchSize: 2,
        idleInterval: 60,
        tokenBudget: 100
    )
    let first = ConversationTurnBundle(
        sessionID: "session-3",
        startedAt: base,
        closedAt: base.addingTimeInterval(10),
        status: .closed
    )
    let second = ConversationTurnBundle(
        sessionID: "session-3",
        startedAt: base.addingTimeInterval(20),
        closedAt: base.addingTimeInterval(30),
        status: .closed
    )
    let buffer = MemoryStagingBuffer(
        sessionID: "session-3",
        pendingBundles: [first, second],
        tokenEstimate: 120,
        triggerPolicy: policy
    )

    let reasons = buffer.triggerReasons(
        at: base.addingTimeInterval(100),
        sessionClosed: true,
        explicitRememberRequest: true,
        highValueSignal: true
    )

    #expect(reasons.contains(.bundleCountReached))
    #expect(reasons.contains(.sessionIdle))
    #expect(reasons.contains(.sessionClosed))
    #expect(reasons.contains(.explicitRememberRequest))
    #expect(reasons.contains(.highValueSignal))
    #expect(reasons.contains(.tokenBudgetExceeded))
}

@Test func emptyMemoryStagingBufferDoesNotTriggerDistillation() throws {
    let buffer = MemoryStagingBuffer(sessionID: "empty")

    let reasons = buffer.triggerReasons(
        sessionClosed: true,
        explicitRememberRequest: true,
        highValueSignal: true
    )

    #expect(reasons.isEmpty)
}

@Test func memoryStagingBufferDrainsAfterDistillation() throws {
    let bundle = ConversationTurnBundle(sessionID: "session-4")
    let distilledAt = Date(timeIntervalSince1970: 4_000)
    var buffer = MemoryStagingBuffer(
        sessionID: "session-4",
        pendingBundles: [bundle],
        tokenEstimate: 42
    )

    buffer.markDistilling()
    #expect(buffer.status == .distilling)

    buffer.markDistilled(at: distilledAt)

    #expect(buffer.pendingBundles.isEmpty)
    #expect(buffer.bundleCount == 0)
    #expect(buffer.tokenEstimate == 0)
    #expect(buffer.lastDistilledAt == distilledAt)
    #expect(buffer.status == .drained)
}
