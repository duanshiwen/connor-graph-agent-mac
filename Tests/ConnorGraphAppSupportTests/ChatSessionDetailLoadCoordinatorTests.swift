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
        #expect(snapshot.sessionRecords.isEmpty)
        #expect(snapshot.backgroundTasks.isEmpty)
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

    @Test func loadReconcilesOnlyOrphanedBackgroundTasks() async throws {
        let store = try SQLiteGraphKernelStore(path: temporaryDatabaseURL().path)
        try store.migrate()
        let repository = AppChatSessionRepository(store: store)
        let session = try repository.createSession(title: "Tasks")
        let now = Date()
        let orphaned = PersistedSessionBackgroundTask(
            id: "orphaned",
            sessionID: session.id,
            kind: "test",
            title: "Orphaned",
            detail: "",
            status: .running,
            createdAt: now,
            updatedAt: now
        )
        let active = PersistedSessionBackgroundTask(
            id: "active",
            sessionID: session.id,
            kind: "test",
            title: "Active",
            detail: "",
            status: .running,
            createdAt: now,
            updatedAt: now
        )
        try repository.saveBackgroundTask(orphaned)
        try repository.saveBackgroundTask(active)

        let snapshot = try #require(await ChatSessionDetailLoadCoordinator().load(
            repository: repository,
            sessionID: session.id,
            activeBackgroundTaskIDs: [active.id]
        ))

        let loadedOrphanedStatus = snapshot.backgroundTasks.first { $0.id == "orphaned" }?.status
        let loadedActiveStatus = snapshot.backgroundTasks.first { $0.id == "active" }?.status
        let persistedTasks = try repository.loadBackgroundTasks(sessionID: session.id)
        let persistedOrphanedStatus = persistedTasks.first { $0.id == "orphaned" }?.status
        #expect(loadedOrphanedStatus == .interrupted)
        #expect(loadedActiveStatus == .running)
        #expect(persistedOrphanedStatus == .interrupted)
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-session-detail-load-\(UUID().uuidString).sqlite")
    }
}
