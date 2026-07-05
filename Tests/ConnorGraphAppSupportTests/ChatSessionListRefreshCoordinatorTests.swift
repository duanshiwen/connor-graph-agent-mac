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

        let result = try await coordinator.refresh(repository: repository, filter: AgentSessionListFilter.status(.inProgress))

        #expect(result.visibleSessions.map(\.id) == ["session-active"])
        #expect(Set(result.allSessions.map(\.id)) == ["session-active", "session-done"])
    }
}

private func temporaryChatSessionListRefreshURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("chat-session-list-refresh-\(UUID().uuidString).sqlite")
}
