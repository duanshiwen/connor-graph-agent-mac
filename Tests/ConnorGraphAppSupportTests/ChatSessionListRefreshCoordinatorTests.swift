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
        #expect(result.summary.totalCount == 2)
        #expect(result.summary.countsByStatus[.inProgress] == 1)
        #expect(result.summary.countsByStatus[.done] == 1)
    }

    @Test func refreshDropsStaleMessagesWithoutDecodingFullSession() async throws {
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

        #expect(result.visibleSessions.first?.messages.isEmpty == true)
    }

    @Test func repositoryPagesFilteredSessionMetadataWithoutGaps() throws {
        let store = try SQLiteGraphKernelStore(path: temporaryChatSessionListRefreshURL().path)
        try store.migrate()
        let repository = AppChatSessionRepository(store: store)
        let label = AgentSessionLabel(id: "important")
        for index in 0..<137 {
            let status: AgentSessionStatus = index.isMultiple(of: 2) ? .done : .todo
            try repository.saveSession(AgentSession(
                id: String(format: "session-%03d", index),
                title: index.isMultiple(of: 3) ? "Needle \(index)" : "Session \(index)",
                messages: [AgentMessage(role: .user, content: "payload \(index)")],
                createdAt: Date(timeIntervalSince1970: 1_000),
                updatedAt: Date(timeIntervalSince1970: TimeInterval(10_000 - index / 4)),
                governance: AgentSessionGovernanceMetadata(status: status, labels: index.isMultiple(of: 5) ? [label] : [])
            ))
        }

        var cursor: String?
        var loaded: [AgentSession] = []
        repeat {
            let page = try repository.loadSessionPage(filter: .all, limit: 19, cursor: cursor)
            #expect(page.sessions.allSatisfy { $0.messages.isEmpty })
            loaded.append(contentsOf: page.sessions)
            cursor = page.nextCursor
        } while cursor != nil
        #expect(loaded.count == 137)
        #expect(Set(loaded.map(\.id)).count == 137)

        let done = try repository.loadSessionPage(filter: .status(.done), limit: 100)
        #expect(done.sessions.count == 69)
        let labeled = try repository.loadSessionPage(filter: .label("important"), limit: 100)
        #expect(labeled.sessions.count == 28)
        let searched = try repository.loadSessionPage(filter: .all, query: "Needle", limit: 100)
        #expect(searched.sessions.count == 46)

        let summary = try repository.loadSessionSummary()
        #expect(summary.totalCount == 137)
        #expect(summary.countsByStatus[.done] == 69)
        #expect(summary.countsByStatus[.todo] == 68)
        #expect(summary.countsByLabelID["important"] == 28)
    }
}

private func temporaryChatSessionListRefreshURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("chat-session-list-refresh-\(UUID().uuidString).sqlite")
}
