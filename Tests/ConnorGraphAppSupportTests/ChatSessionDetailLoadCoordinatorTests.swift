import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphStore
@testable import ConnorGraphAppSupport

@Suite("Chat Session Detail Load Coordinator Tests")
struct ChatSessionDetailLoadCoordinatorTests {
    @Test func loadBuildsSnapshotAndPrefersActivityTimelineCache() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-session-detail-load-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppStoragePaths.resolving(applicationSupportBaseDirectory: root)
        try paths.ensureDirectoryHierarchy()
        let store = try SQLiteGraphKernelStore(path: paths.databaseURL.path)
        try store.migrate()
        let repository = AppChatSessionRepository(store: store, storagePaths: paths)
        var session = try repository.createSession(title: "Detail")
        session.messages = [AgentMessage(role: .user, content: "Hello")]
        session = try repository.saveSession(session)
        let cached = [AgentEventPresentation(
            kind: "tool",
            title: "Cached",
            detail: "From cache",
            severity: .info,
            runID: nil,
            sessionID: session.id
        )]
        try repository.saveActivityTimelineCache(sessionID: session.id, timeline: cached)

        let snapshot = try #require(await ChatSessionDetailLoadCoordinator().load(
            repository: repository,
            sessionID: session.id
        ))

        #expect(snapshot.session.id == session.id)
        #expect(snapshot.session.title == session.title)
        #expect(snapshot.session.messages.map(\.id) == session.messages.map(\.id))
        #expect(snapshot.session.messages.map(\.role) == session.messages.map(\.role))
        #expect(snapshot.session.messages.map(\.content) == ["Hello"])
        #expect(snapshot.timeline == cached)
        #expect(snapshot.artifactDirectories != nil)
    }

    @Test func loadReturnsNilForMissingSession() async throws {
        let store = try SQLiteGraphKernelStore(path: temporaryDatabaseURL().path)
        try store.migrate()
        let repository = AppChatSessionRepository(store: store)

        let snapshot = try await ChatSessionDetailLoadCoordinator().load(
            repository: repository,
            sessionID: "missing"
        )

        #expect(snapshot == nil)
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-session-detail-load-\(UUID().uuidString).sqlite")
    }
}
