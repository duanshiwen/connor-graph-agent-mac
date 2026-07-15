import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore
@testable import ConnorGraphAppSupport

@Suite("Chat Session List Refresh Coordinator Tests")
struct ChatSessionListRefreshCoordinatorTests {
    @Test func refreshLoadsVisibleAndAllSessions() async throws {
        let store = try SQLiteGraphKernelStore(path: temporaryChatSessionListRefreshURL().path)
        try store.migrate()
        let repository = AppChatSessionRepository(store: store)
        try repository.saveSession(AgentSession(id: "session-active", title: "Active", governance: AgentSessionGovernanceMetadata(status: .inProgress)))
        try repository.saveSession(AgentSession(id: "session-done", title: "Done", governance: AgentSessionGovernanceMetadata(status: .done)))
        let coordinator = ChatSessionListRefreshCoordinator()

        let preserved = AgentSession(
            id: "session-active",
            messages: [AgentMessage(role: .user, content: "preserved transcript")]
        )
        let result = try await coordinator.refresh(
            repository: repository,
            filter: AgentSessionListFilter.status(.inProgress),
            preserving: [preserved]
        )

        #expect(result.visibleSessions.map(\.id) == ["session-active"])
        #expect(Set(result.allSessions.map(\.id)) == ["session-active", "session-done"])
        #expect(result.visibleSessions.first?.messages.map(\.content) == ["preserved transcript"])
        #expect(result.allSessions.first(where: { $0.id == "session-done" })?.messages.isEmpty == true)
    }
}

private func temporaryChatSessionListRefreshURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("chat-session-list-refresh-\(UUID().uuidString).sqlite")
}
