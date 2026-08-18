import Foundation
import Testing
import ConnorGraphCore
@testable import ConnorGraphAgentMac

@Suite("Note session presentation policy")
struct NoteSessionPresentationPolicyTests {
    @Test("only an empty idle note uses initial capture presentation")
    func emptyIdleNoteUsesInitialCapturePresentation() {
        #expect(AgentChatMessagePresentationPolicy.isBeforeFirstNoteMessage(
            sessionKind: .note,
            sessionMessageCount: 0,
            persistedMessageCount: 0,
            transcriptMessageCount: 0,
            isSubmitting: false
        ))
        #expect(!AgentChatMessagePresentationPolicy.isBeforeFirstNoteMessage(
            sessionKind: .chat,
            sessionMessageCount: 0,
            persistedMessageCount: 0,
            transcriptMessageCount: 0,
            isSubmitting: false
        ))
        #expect(!AgentChatMessagePresentationPolicy.isBeforeFirstNoteMessage(
            sessionKind: .note,
            sessionMessageCount: 0,
            persistedMessageCount: 0,
            transcriptMessageCount: 0,
            isSubmitting: true
        ))
    }

    @Test("completed first turn cannot fall back to initial capture when list snapshot is stale")
    func completedFirstTurnUsesConversationPresentation() {
        #expect(!AgentChatMessagePresentationPolicy.isBeforeFirstNoteMessage(
            sessionKind: .note,
            sessionMessageCount: 0,
            persistedMessageCount: 0,
            transcriptMessageCount: 2,
            isSubmitting: false
        ))
        #expect(!AgentChatMessagePresentationPolicy.isBeforeFirstNoteMessage(
            sessionKind: .note,
            sessionMessageCount: 0,
            persistedMessageCount: 2,
            transcriptMessageCount: 0,
            isSubmitting: false
        ))
    }

    @Test("note body row exposes the edit-mode entry action")
    func noteBodyRowExposesEditModeEntryAction() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ConnorGraphAgentMac/AgentChatMessageRows.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("Image(systemName: \"square.and.pencil\")"))
        #expect(source.contains("onBeginEditingNoteBody"))
        #expect(!source.contains("AgentNoteBodyEditorSheet"))
    }
}
