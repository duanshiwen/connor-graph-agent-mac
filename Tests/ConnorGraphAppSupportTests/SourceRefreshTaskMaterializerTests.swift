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

    @Test func materializerPurgesOrphanedRSSRefreshTasksWhenSourceIsRemoved() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let taskRepository = AppTaskManagementRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))
        let rssRepository = InMemoryRSSSourceRepository(sources: [makeSource(id: "feed-a", name: "Feed A", intervalMinutes: 15)])
        let materializer = SourceRefreshTaskMaterializer(taskRepository: taskRepository, rssSourceRepository: rssRepository)
        _ = try await materializer.reconcileRSSSourceRefreshTasks(now: Date(timeIntervalSince1970: 10))

        try await rssRepository.deleteSource(id: RSSSourceID(rawValue: "feed-a"))
        let tasks = try await materializer.reconcileRSSSourceRefreshTasks(now: Date(timeIntervalSince1970: 20))

        #expect(tasks.contains { $0.id == "system.rss.source.feed-a.refresh" } == false)
    }

    @Test func materializerPurgesLegacyGlobalRSSTask() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let taskRepository = AppTaskManagementRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))
        let rssRepository = InMemoryRSSSourceRepository(sources: [makeSource(id: "feed-a", name: "Feed A", intervalMinutes: 15)])
        let materializer = SourceRefreshTaskMaterializer(taskRepository: taskRepository, rssSourceRepository: rssRepository)
        try taskRepository.saveTask(ConnorTaskDefinition(
            id: "system.rss.check-every-30-minutes",
            name: "检查 RSS",
            origin: .system,
            trigger: ConnorTaskTrigger(kind: .scheduled, intervalSeconds: 1_800, recurrence: .interval),
            target: .sourceRuntimeRefresh(sourceID: "rss"),
            lifecycle: ConnorTaskLifecycle(status: .active),
            metadata: .protectedSystem,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        ))

        let tasks = try await materializer.reconcileRSSSourceRefreshTasks(now: Date(timeIntervalSince1970: 10))

        #expect(tasks.contains { $0.id == "system.rss.check-every-30-minutes" } == false)
        #expect(tasks.contains { $0.id == "system.rss.source.feed-a.refresh" })
    }

    @Test func materializerCreatesOneMailRefreshTaskPerAccount() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let taskRepository = AppTaskManagementRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))
        let mailRepository = InMemoryMailSourceRepository(accounts: [
            makeMailAccount(id: "mail-a", displayName: "Mail A"),
            makeMailAccount(id: "mail-b", displayName: "Mail B")
        ])
        let materializer = MailRefreshTaskMaterializer(taskRepository: taskRepository, mailSourceRepository: mailRepository)

        let tasks = try await materializer.reconcileMailAccountRefreshTasks(now: Date(timeIntervalSince1970: 10))
        let mailA = try #require(tasks.first { $0.id == "system.mail.account.mail-a.refresh" })
        let mailB = try #require(tasks.first { $0.id == "system.mail.account.mail-b.refresh" })

        #expect(mailA.name == "检查邮件：Mail A")
        #expect(mailA.trigger.intervalSeconds == 600)
        #expect(mailA.target.targetKind == "source.runtime")
        #expect(mailA.target.targetID == "mail")
        #expect(mailA.target.operationName == "refresh")
        #expect(mailA.target.parameters["sourceKind"] == "mail")
        #expect(mailA.target.parameters["sourceInstanceID"] == "mail-a")
        #expect(mailA.metadata.isProtectedSystemTask)
        #expect(mailA.metadata.tags.contains("source-instance"))
        #expect(mailB.target.parameters["sourceInstanceID"] == "mail-b")
        #expect(tasks.contains { $0.id == "system.mail.check-every-10-minutes" } == false)
    }

    @Test func materializerPurgesOrphanedMailRefreshTasksWhenAccountIsRemoved() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let taskRepository = AppTaskManagementRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))
        let mailRepository = InMemoryMailSourceRepository(accounts: [makeMailAccount(id: "mail-a", displayName: "Mail A")])
        let materializer = MailRefreshTaskMaterializer(taskRepository: taskRepository, mailSourceRepository: mailRepository)
        _ = try await materializer.reconcileMailAccountRefreshTasks(now: Date(timeIntervalSince1970: 10))

        let emptyMailRepository = InMemoryMailSourceRepository(accounts: [])
        let emptyMaterializer = MailRefreshTaskMaterializer(taskRepository: taskRepository, mailSourceRepository: emptyMailRepository)
        let tasks = try await emptyMaterializer.reconcileMailAccountRefreshTasks(now: Date(timeIntervalSince1970: 20))

        #expect(tasks.contains { $0.id == "system.mail.account.mail-a.refresh" } == false)
    }

    @Test func materializerPurgesLegacyGlobalMailTask() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let taskRepository = AppTaskManagementRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))
        let mailRepository = InMemoryMailSourceRepository(accounts: [makeMailAccount(id: "mail-a", displayName: "Mail A")])
        let materializer = MailRefreshTaskMaterializer(taskRepository: taskRepository, mailSourceRepository: mailRepository)
        try taskRepository.saveTask(ConnorTaskDefinition(
            id: "system.mail.check-every-10-minutes",
            name: "检查邮件",
            origin: .system,
            trigger: ConnorTaskTrigger(kind: .scheduled, intervalSeconds: 600, recurrence: .interval),
            target: .sourceRuntimeRefresh(sourceID: "mail"),
            lifecycle: ConnorTaskLifecycle(status: .active),
            metadata: .protectedSystem,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        ))

        let tasks = try await materializer.reconcileMailAccountRefreshTasks(now: Date(timeIntervalSince1970: 10))

        #expect(tasks.contains { $0.id == "system.mail.check-every-10-minutes" } == false)
        #expect(tasks.contains { $0.id == "system.mail.account.mail-a.refresh" })
    }

    @Test func materializerCreatesOneCalendarRefreshTaskPerAccount() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let taskRepository = AppTaskManagementRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))
        let calendarRepository = InMemoryCalendarSourceRepository(accounts: [
            makeCalendarAccount(id: "calendar-account-a", displayName: "Calendar A"),
            makeCalendarAccount(id: "calendar-account-b", displayName: "Calendar B")
        ])
        let materializer = CalendarRefreshTaskMaterializer(taskRepository: taskRepository, calendarSourceRepository: calendarRepository)

        let tasks = try await materializer.reconcileCalendarAccountRefreshTasks(now: Date(timeIntervalSince1970: 10))
        let calendarA = try #require(tasks.first { $0.id == "system.calendar.account.calendar-account-a.refresh" })
        let calendarB = try #require(tasks.first { $0.id == "system.calendar.account.calendar-account-b.refresh" })

        #expect(calendarA.name == "检查日历：Calendar A")
        #expect(calendarA.trigger.intervalSeconds == 600)
        #expect(calendarA.target.targetKind == "source.runtime")
        #expect(calendarA.target.targetID == "calendar")
        #expect(calendarA.target.operationName == "refresh")
        #expect(calendarA.target.parameters["sourceKind"] == "calendar")
        #expect(calendarA.target.parameters["sourceInstanceID"] == "calendar-account-a")
        #expect(calendarA.metadata.isProtectedSystemTask)
        #expect(calendarA.metadata.tags.contains("source-instance"))
        #expect(calendarB.target.parameters["sourceInstanceID"] == "calendar-account-b")
        #expect(tasks.contains { $0.id == "system.calendar.check-every-10-minutes" } == false)
    }

    @Test func materializerPurgesOrphanedCalendarRefreshTasksWhenAccountIsRemoved() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let taskRepository = AppTaskManagementRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))
        let calendarRepository = InMemoryCalendarSourceRepository(accounts: [makeCalendarAccount(id: "calendar-account-a", displayName: "Calendar A")])
        let materializer = CalendarRefreshTaskMaterializer(taskRepository: taskRepository, calendarSourceRepository: calendarRepository)
        _ = try await materializer.reconcileCalendarAccountRefreshTasks(now: Date(timeIntervalSince1970: 10))

        let emptyCalendarRepository = InMemoryCalendarSourceRepository(accounts: [])
        let emptyMaterializer = CalendarRefreshTaskMaterializer(taskRepository: taskRepository, calendarSourceRepository: emptyCalendarRepository)
        let tasks = try await emptyMaterializer.reconcileCalendarAccountRefreshTasks(now: Date(timeIntervalSince1970: 20))

        #expect(tasks.contains { $0.id == "system.calendar.account.calendar-account-a.refresh" } == false)
    }

    @Test func materializerPurgesLegacyGlobalCalendarTask() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let taskRepository = AppTaskManagementRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))
        let calendarRepository = InMemoryCalendarSourceRepository(accounts: [makeCalendarAccount(id: "calendar-account-a", displayName: "Calendar A")])
        let materializer = CalendarRefreshTaskMaterializer(taskRepository: taskRepository, calendarSourceRepository: calendarRepository)
        try taskRepository.saveTask(ConnorTaskDefinition(
            id: "system.calendar.check-every-10-minutes",
            name: "检查日历",
            origin: .system,
            trigger: ConnorTaskTrigger(kind: .scheduled, intervalSeconds: 600, recurrence: .interval),
            target: .sourceRuntimeRefresh(sourceID: "calendar"),
            lifecycle: ConnorTaskLifecycle(status: .active),
            metadata: .protectedSystem,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        ))

        let tasks = try await materializer.reconcileCalendarAccountRefreshTasks(now: Date(timeIntervalSince1970: 10))

        #expect(tasks.contains { $0.id == "system.calendar.check-every-10-minutes" } == false)
        #expect(tasks.contains { $0.id == "system.calendar.account.calendar-account-a.refresh" })
    }

    private func makeSource(id: String, name: String, intervalMinutes: Int) -> RSSSource {
        RSSSource(
            id: RSSSourceID(rawValue: id),
            feedURL: URL(string: "https://example.com/\(id).xml")!,
            displayName: name,
            fetchPolicy: RSSSourceFetchPolicy(intervalMinutes: intervalMinutes)
        )
    }


    private func makeCalendarAccount(id: String, displayName: String) -> CalendarAccount {
        let now = Date(timeIntervalSince1970: 0)
        return CalendarAccount(
            id: CalendarAccountID(rawValue: id),
            provider: .genericCalDAVCardDAV,
            displayName: displayName,
            health: CalendarAccountHealth(status: .ready, checkedAt: now, summary: "Ready"),
            createdAt: now,
            updatedAt: now
        )
    }

    private func makeMailAccount(id: String, displayName: String) -> MailAccount {
        let now = Date(timeIntervalSince1970: 0)
        return MailAccount(
            id: MailAccountID(rawValue: id),
            provider: .genericIMAPSMTP,
            displayName: displayName,
            identities: [
                MailIdentity(
                    id: MailIdentityID(rawValue: "identity-\(id)"),
                    displayName: displayName,
                    address: MailAddress(name: displayName, email: "\(id)@example.com")
                )
            ],
            incoming: MailServerEndpoint(host: "imap.example.com", port: 993, security: .tls, protocolKind: .imap),
            outgoing: MailServerEndpoint(host: "smtp.example.com", port: 587, security: .startTLS, protocolKind: .smtp),
            health: MailAccountHealth(status: .ready, checkedAt: now, summary: "Ready"),
            createdAt: now,
            updatedAt: now
        )
    }
}


private actor InMemoryCalendarSourceRepository: CalendarSourceRepository {
    private var accounts: [CalendarAccountID: CalendarAccount]

    init(accounts: [CalendarAccount] = []) {
        self.accounts = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
    }

    func listAccounts() async throws -> [CalendarAccount] {
        accounts.values.sorted { $0.displayName < $1.displayName }
    }
}
