import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Source Refresh Task Materializer Tests")
struct SourceRefreshTaskMaterializerTests {
    @Test func materializerCreatesOneRSSRefreshTaskPerSource() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let taskRepository = AppTaskManagementRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))
        let rssRepository = InMemoryRSSSourceRepository(sources: [
            makeSource(id: "feed-a", name: "Feed A", intervalMinutes: 15),
            makeSource(id: "feed-b", name: "Feed B", intervalMinutes: 60)
        ])
        let materializer = SourceRefreshTaskMaterializer(taskRepository: taskRepository, rssSourceRepository: rssRepository)

        let tasks = try await materializer.reconcileRSSSourceRefreshTasks(now: Date(timeIntervalSince1970: 10))
        let feedA = try #require(tasks.first { $0.id == "system.rss.source.feed-a.refresh" })
        let feedB = try #require(tasks.first { $0.id == "system.rss.source.feed-b.refresh" })

        #expect(feedA.trigger.intervalSeconds == 900)
        #expect(feedB.trigger.intervalSeconds == 3_600)
        #expect(feedA.target.parameters["sourceInstanceID"] == "feed-a")
        #expect(feedB.target.parameters["sourceInstanceID"] == "feed-b")
        #expect(feedA.metadata.isProtectedSystemTask)
        #expect(feedA.metadata.tags.contains("source-instance"))
    }

    @Test func materializerUpdatesExistingRSSRefreshTaskIntervalWithoutChangingID() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let taskRepository = AppTaskManagementRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))
        let rssRepository = InMemoryRSSSourceRepository(sources: [makeSource(id: "feed-a", name: "Feed A", intervalMinutes: 15)])
        let materializer = SourceRefreshTaskMaterializer(taskRepository: taskRepository, rssSourceRepository: rssRepository)
        _ = try await materializer.reconcileRSSSourceRefreshTasks(now: Date(timeIntervalSince1970: 10))

        try await rssRepository.saveSource(makeSource(id: "feed-a", name: "Feed A", intervalMinutes: 30))
        let tasks = try await materializer.reconcileRSSSourceRefreshTasks(now: Date(timeIntervalSince1970: 20))
        let feedA = try #require(tasks.first { $0.id == "system.rss.source.feed-a.refresh" })

        #expect(feedA.id == "system.rss.source.feed-a.refresh")
        #expect(feedA.trigger.intervalSeconds == 1_800)
    }

    @Test func materializerStopsOrphanedRSSRefreshTasksWhenSourceIsRemoved() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let taskRepository = AppTaskManagementRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))
        let rssRepository = InMemoryRSSSourceRepository(sources: [makeSource(id: "feed-a", name: "Feed A", intervalMinutes: 15)])
        let materializer = SourceRefreshTaskMaterializer(taskRepository: taskRepository, rssSourceRepository: rssRepository)
        _ = try await materializer.reconcileRSSSourceRefreshTasks(now: Date(timeIntervalSince1970: 10))

        try await rssRepository.deleteSource(id: RSSSourceID(rawValue: "feed-a"))
        let tasks = try await materializer.reconcileRSSSourceRefreshTasks(now: Date(timeIntervalSince1970: 20))
        let feedA = try #require(tasks.first { $0.id == "system.rss.source.feed-a.refresh" })

        #expect(feedA.lifecycle.status == .stopped)
        #expect(feedA.lifecycle.lastErrorMessage?.contains("no longer exists") == true)
        #expect(feedA.metadata.tags.contains("orphaned-source"))
    }

    @Test func materializerDeprecatesLegacyGlobalRSSTask() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let taskRepository = AppTaskManagementRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))
        let rssRepository = InMemoryRSSSourceRepository(sources: [makeSource(id: "feed-a", name: "Feed A", intervalMinutes: 15)])
        let materializer = SourceRefreshTaskMaterializer(taskRepository: taskRepository, rssSourceRepository: rssRepository)

        let tasks = try await materializer.reconcileRSSSourceRefreshTasks(now: Date(timeIntervalSince1970: 10))
        let legacy = try #require(tasks.first { $0.id == SourceRefreshTaskMaterializer.legacyGlobalRSSTaskID })

        #expect(legacy.lifecycle.status == .stopped)
        #expect(legacy.lifecycle.lastErrorMessage == "Replaced by RSS source-instance refresh tasks.")
        #expect(legacy.metadata.tags.contains("deprecated"))
        #expect(legacy.metadata.tags.contains("source-type-refresh"))
    }

    private func makeSource(id: String, name: String, intervalMinutes: Int) -> RSSSource {
        RSSSource(
            id: RSSSourceID(rawValue: id),
            feedURL: URL(string: "https://example.com/\(id).xml")!,
            displayName: name,
            fetchPolicy: RSSSourceFetchPolicy(intervalMinutes: intervalMinutes)
        )
    }
}
