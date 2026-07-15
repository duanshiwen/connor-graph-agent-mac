import Testing
@testable import ConnorGraphAgentMac

@MainActor
@Suite("Session Attention Visibility Tests")
struct SessionAttentionVisibilityTests {
    @Test func selectedAgentChatSessionTreatsUpdatesAsReadEvenWhenAppIsNotActive() {
        let fixture = makeFixture(selection: .agentChat, selectedSessionID: "visible-session")

        #expect(fixture.coordinator.shouldTreatUpdateAsRead(sessionID: "visible-session"))
    }

    @Test func nonSelectedSessionDoesNotTreatUpdatesAsRead() {
        let fixture = makeFixture(selection: .agentChat, selectedSessionID: "visible-session")

        #expect(!fixture.coordinator.shouldTreatUpdateAsRead(sessionID: "background-session"))
    }

    @Test func selectedSessionOutsideChatViewDoesNotTreatUpdatesAsRead() {
        let fixture = makeFixture(selection: .search, selectedSessionID: "visible-session")

        #expect(!fixture.coordinator.shouldTreatUpdateAsRead(sessionID: "visible-session"))
    }

    private func makeFixture(
        selection: SidebarItem,
        selectedSessionID: String
    ) -> (model: ChatSessionListModel, coordinator: ChatAttentionCoordinator) {
        let model = ChatSessionListModel()
        model.selectedSessionID = selectedSessionID
        let coordinator = ChatAttentionCoordinator(model: model, repository: nil)
        coordinator.selectedNavigation = { selection }
        return (model, coordinator)
    }
}
