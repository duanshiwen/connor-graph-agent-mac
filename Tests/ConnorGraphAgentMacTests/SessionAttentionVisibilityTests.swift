import AppKit
import Testing
@testable import ConnorGraphAgentMac

@MainActor
@Suite("Session Attention Visibility Tests")
struct SessionAttentionVisibilityTests {
    @Test func selectedAgentChatSessionTreatsUpdatesAsReadEvenWhenAppIsNotActive() {
        _ = NSApplication.shared
        let viewModel = AppViewModel(
            entities: [],
            statements: [],
            observeLogEntries: []
        )
        viewModel.selection = .agentChat
        viewModel.chatFeatureModel.sessions.selectedSessionID = "visible-session"

        #expect(!NSApp.isActive)
        #expect(viewModel.shouldTreatSessionUpdateAsRead(sessionID: "visible-session"))
    }

    @Test func nonSelectedSessionDoesNotTreatUpdatesAsRead() {
        _ = NSApplication.shared
        let viewModel = AppViewModel(
            entities: [],
            statements: [],
            observeLogEntries: []
        )
        viewModel.selection = .agentChat
        viewModel.chatFeatureModel.sessions.selectedSessionID = "visible-session"

        #expect(!viewModel.shouldTreatSessionUpdateAsRead(sessionID: "background-session"))
    }

    @Test func selectedSessionOutsideChatViewDoesNotTreatUpdatesAsRead() {
        _ = NSApplication.shared
        let viewModel = AppViewModel(
            entities: [],
            statements: [],
            observeLogEntries: []
        )
        viewModel.selection = .search
        viewModel.chatFeatureModel.sessions.selectedSessionID = "visible-session"

        #expect(!viewModel.shouldTreatSessionUpdateAsRead(sessionID: "visible-session"))
    }
}
