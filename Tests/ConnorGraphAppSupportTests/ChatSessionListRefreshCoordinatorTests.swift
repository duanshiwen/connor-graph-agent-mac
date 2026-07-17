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
        try repository.saveSession(AgentSession(
            id: "session-active",
            title: "Active",
            messages: [AgentMessage(role: .user, content: "persisted transcript")],
            governance: AgentSessionGovernanceMetadata(status: .inProgress)
        ))
        try repository.saveSession(AgentSession(id: "session-done", title: "Done", governance: AgentSessionGovernanceMetadata(status: .done)))
        let coordinator = ChatSessionListRefreshCoordinator()

        let loaded = try repository.loadSession(id: "session-active")
        var preserved = try #require(loaded)
        preserved.messages = [AgentMessage(role: .user, content: "preserved transcript")]
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

    @Test func refreshReplacesStaleCardMessagesWhenPersistedSessionHasChanged() async throws {
        let store = try SQLiteGraphKernelStore(path: temporaryChatSessionListRefreshURL().path)
        try store.migrate()
        let repository = AppChatSessionRepository(store: store)
        let oldMessages = (1...3).map { AgentMessage(role: .user, content: "old-\($0)") }
        let oldSnapshot = AgentSession(
            id: "session",
            messages: oldMessages,
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        try repository.saveSession(oldSnapshot)
        var latest = oldSnapshot
        latest.messages.append(AgentMessage(role: .assistant, content: "new-4"))
        latest.updatedAt = Date(timeIntervalSince1970: 2_000)
        try repository.saveSession(latest, previousMessageCount: oldMessages.count)
        let coordinator = ChatSessionListRefreshCoordinator()

        let result = try await coordinator.refresh(
            repository: repository,
            filter: .all,
            preserving: [oldSnapshot]
        )

        #expect(result.visibleSessions.first?.messages.count == 4)
        #expect(result.visibleSessions.first?.messages.last?.content == "new-4")
    }
}

private func temporaryChatSessionListRefreshURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("chat-session-list-refresh-\(UUID().uuidString).sqlite")
}
