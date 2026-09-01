import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore

@Suite("Native Session Manager Message Merge Tests")
struct NativeSessionManagerMergeTests {
    private func userMessage(id: String, content: String) -> AgentMessage {
        AgentMessage(id: id, role: .user, content: content)
    }

    private func assistantMessage(id: String, content: String, runID: String? = nil) -> AgentMessage {
        var message = AgentMessage(id: id, role: .assistant, content: content)
        message.runID = runID
        return message
    }

    @Test func noteEditChangeIsNotRevertedByRunPersist() {
        // note_edit 已把正文改成“新正文”并落库（persisted）；
        // run 是编辑前启动的，内存里还是“旧正文”。合并后必须保留“新正文”。
        let persisted = [
            userMessage(id: "note-1", content: "新正文"),
            assistantMessage(id: "a-old", content: "之前的回复", runID: "run-0"),
        ]
        let inMemory = [
            userMessage(id: "note-1", content: "旧正文"),
            assistantMessage(id: "a-stream", content: "回复中…", runID: "run-1"),
        ]
        let merged = NativeSessionManager.mergedMessages(
            inMemory: inMemory,
            persisted: persisted,
            activeRunID: "run-1"
        )
        #expect(merged.count == 2)
        #expect(merged[0].id == "note-1")
        #expect(merged[0].content == "新正文")
        #expect(merged[1].id == "a-stream")
        #expect(merged[1].content == "回复中…")
    }

    @Test func runOwnedAssistantMessageStaysInMemory() {
        // 没有外部修改：本 run 的 assistant 消息以内存为准。
        let persisted = [userMessage(id: "note-1", content: "正文")]
        let inMemory = [
            userMessage(id: "note-1", content: "正文"),
            assistantMessage(id: "a-stream", content: "最终回复", runID: "run-9"),
        ]
        let merged = NativeSessionManager.mergedMessages(
            inMemory: inMemory,
            persisted: persisted,
            activeRunID: "run-9"
        )
        #expect(merged.map(\.content) == ["正文", "最终回复"])
    }

    @Test func prefixPreservesMessagesBeforeFirstLoaded() {
        // 会话窗口外（首条之前）的持久化消息要保留。
        let persisted = [
            userMessage(id: "old", content: "更早的消息"),
            userMessage(id: "note-1", content: "正文"),
        ]
        let inMemory = [userMessage(id: "note-1", content: "正文")]
        let merged = NativeSessionManager.mergedMessages(
            inMemory: inMemory,
            persisted: persisted,
            activeRunID: nil
        )
        #expect(merged.map(\.id) == ["old", "note-1"])
    }

    @Test func noteEditBodySurvivesFailurePathPersistWhenActiveRunCleared() {
        // 回归：run 失败/取消后 activeRunID 被清空（nil），兜底持久化仍必须保留 note_edit 已落库的
        // 新正文，不能拿 run 开始时加载的旧内存副本把正文回滚掉（否则笔记永远“更新不到”）。
        let persisted = [
            userMessage(id: "note-1", content: "新正文"),
        ]
        let inMemory = [
            userMessage(id: "note-1", content: "旧正文"),
            assistantMessage(id: "a-stream", content: "回复（未完成）", runID: "run-1"),
        ]
        let merged = NativeSessionManager.mergedMessages(
            inMemory: inMemory,
            persisted: persisted,
            activeRunID: nil
        )
        #expect(merged.map(\.id) == ["note-1", "a-stream"])
        #expect(merged[0].content == "新正文")
        #expect(merged[1].content == "回复（未完成）")
    }
}
