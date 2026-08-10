import Foundation
import Observation
import ConnorGraphCore
import ConnorGraphAppSupport

@MainActor
@Observable
final class CalendarFeatureModel {
    enum Event {
        case operationSucceeded
        case operationFailed(String)
        case presentationChanged([CalendarEvent])
    }

    typealias SystemSnapshotLoader = @Sendable () async throws -> CalendarEventKitSnapshot
    typealias RemoteAccountSynchronizer = @Sendable (
        _ account: CalendarAccount,
        _ credential: String?,
        _ runID: String?,
        _ runtimeStore: FileBackedCalendarSourceRuntimeStore
    ) async throws -> CalendarSourceSyncResult

    var presentation: NativeCalendarBrowserPresentation = .empty
    var searchQuery = ""
    private(set) var accounts: [CalendarAccount] = []
    private(set) var collections: [CalendarCollection] = []
    private(set) var events: [CalendarEvent] = []
    var selectedEventID: CalendarEventID?
    var isPresentingAddSourceSheet = false
    private(set) var isSyncingSystemCalendar = false
    private(set) var isSyncingAll = false
    private(set) var syncMessage: String?
    private(set) var isSyncStatusBannerDismissed = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let legacyStore: FileBackedCalendarSourceStore?
    @ObservationIgnored private let runtimeStore: FileBackedCalendarSourceRuntimeStore?
    @ObservationIgnored private let credentialStore: AppCalendarCredentialStore
    @ObservationIgnored private let systemSnapshotLoader: SystemSnapshotLoader
    @ObservationIgnored private let remoteAccountSynchronizer: RemoteAccountSynchronizer
    @ObservationIgnored private let notificationCenter: NotificationCenter
    @ObservationIgnored private var cacheObserver: NSObjectProtocol?
    @ObservationIgnored private var reloadGeneration: UInt64 = 0
    @ObservationIgnored private var ownedTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var isShutdown = false
    @ObservationIgnored var sourceSetChanged: @MainActor () async throws -> Void = {}
    @ObservationIgnored var onOpenSettingsRequest: (() -> Void)?
    @ObservationIgnored var onEvent: ((Event) -> Void)?

    init(
        legacyStore: FileBackedCalendarSourceStore?,
        runtimeStore: FileBackedCalendarSourceRuntimeStore?,
        credentialStore: AppCalendarCredentialStore = AppCalendarCredentialStore(),
        systemSnapshotLoader: @escaping SystemSnapshotLoader = {
            try await CalendarEventKitAdapter.fetchSystemSnapshot()
        },
        remoteAccountSynchronizer: @escaping RemoteAccountSynchronizer = { account, credential, runID, runtimeStore in
            let engine = CalendarSourceSyncEngine(
                connectors: [
                    CalendarICSSubscriptionConnector(),
                    CalendarCalDAVConnector(kind: .genericCalDAV),
                    CalendarCalDAVConnector(kind: .appleICloudCalDAV),
                    CalendarCalDAVConnector(kind: .fastmailCalDAV),
                    CalendarCalDAVConnector(kind: .nextcloudCalDAV)
                ],
                runtimeStore: runtimeStore
            )
            return try await engine.sync(
                request: CalendarSourceSyncRequest(account: account, credential: credential, runID: runID)
            )
        },
        notificationCenter: NotificationCenter = .default
    ) {
        self.legacyStore = legacyStore
        self.runtimeStore = runtimeStore
        self.credentialStore = credentialStore
        self.systemSnapshotLoader = systemSnapshotLoader
        self.remoteAccountSynchronizer = remoteAccountSynchronizer
        self.notificationCenter = notificationCenter
        cacheObserver = notificationCenter.addObserver(
            forName: .connorCalendarCacheDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.startOwnedTask { [weak self] in
                    await self?.reload()
                }
            }
        }
    }

    var agentRuntimeStore: FileBackedCalendarSourceRuntimeStore? { runtimeStore }
    var accountRepository: any CalendarSourceRepository {
        CalendarAccountSnapshotRepository(accounts: accounts)
    }

    func reload() async {
        guard !isShutdown else { return }
        reloadGeneration &+= 1
        let generation = reloadGeneration
        do {
            async let legacyRequest = loadLegacySnapshot()
            async let runtimeRequest = loadRuntimeSnapshot()
            let (legacySnapshot, runtimeSnapshot) = try await (legacyRequest, runtimeRequest)
            guard !Task.isCancelled, !isShutdown, generation == reloadGeneration else { return }
            accounts = mergeAccounts(legacySnapshot?.accounts ?? [], runtimeSnapshot?.accounts ?? [])
            collections = mergeCollections(legacySnapshot?.collections ?? [], runtimeSnapshot?.collections ?? [])
            let deletedEventIDs = Set(
                runtimeSnapshot?.mutationAudits.compactMap { audit in
                    audit.status == .confirmed && audit.operation == .delete ? audit.eventID : nil
                } ?? []
            )
            let retainedLegacyEvents = (legacySnapshot?.events ?? []).filter { !deletedEventIDs.contains($0.id) }
            events = mergeEvents(retainedLegacyEvents, runtimeSnapshot?.events ?? [])
            rebuildPresentation()
            reportSuccess()
        } catch is CancellationError {
            return
        } catch {
            guard !isShutdown, generation == reloadGeneration else { return }
            reportFailure("无法加载日历缓存：\(error.localizedDescription)")
        }
    }

    func selectEvent(id: CalendarEventID?) {
        selectedEventID = id
    }

    func requestOpenSettings() {
        isPresentingAddSourceSheet = false
        onOpenSettingsRequest?()
    }

    func syncSystemCalendar() {
        guard !isShutdown else { return }
        startOwnedTask { [weak self] in
            _ = await self?.syncSystemCalendarNow()
        }
    }

    @discardableResult
    func syncSystemCalendarNow() async -> Bool {
        guard !isShutdown, !isSyncingSystemCalendar else { return false }
        isSyncingSystemCalendar = true
        syncMessage = "正在请求日历权限并同步…"
        defer { isSyncingSystemCalendar = false }
        do {
            let snapshot = try await systemSnapshotLoader()
            guard !Task.isCancelled, !isShutdown else { return false }
            upsertSystemCalendarSnapshot(snapshot)
            await persistSnapshot()
            guard !Task.isCancelled, !isShutdown else { return false }
            try await sourceSetChanged()
            syncMessage = "已同步本机日历：\(snapshot.collections.count) 个日历，\(snapshot.events.count) 个日程"
            reportSuccess()
            return true
        } catch is CancellationError {
            return false
        } catch {
            guard !isShutdown else { return false }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            syncMessage = message
            reportFailure(message)
            return false
        }
    }

    func addSource(
        provider: ConnectedAccountProviderKind,
        displayName rawDisplayName: String,
        calendarName rawCalendarName: String
    ) {
        guard !isShutdown else { return }
        if provider == .localFixture {
            syncSystemCalendar()
            isPresentingAddSourceSheet = false
            return
        }
        let displayName = rawDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let calendarName = rawCalendarName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDisplayName = displayName.isEmpty ? calendarProviderDisplayName(provider) : displayName
        let resolvedCalendarName = calendarName.isEmpty ? "默认日历" : calendarName
        let slugBase = AccountConnectionRuntime.slug(for: "\(provider.rawValue)-\(resolvedDisplayName)-\(accounts.count + 1)")
        let accountID = CalendarAccountID(rawValue: "calendar-account-\(slugBase)")
        let collectionID = CalendarID(rawValue: "calendar-\(slugBase)")
        let now = Date()
        let account = CalendarAccount(
            id: accountID,
            provider: provider,
            displayName: resolvedDisplayName,
            health: CalendarAccountHealth(status: .ready, checkedAt: now, summary: "已添加，等待同步日程"),
            createdAt: now,
            updatedAt: now
        )
        let collection = CalendarCollection(
            id: collectionID,
            accountID: accountID,
            displayName: resolvedCalendarName,
            colorHex: "#F97316",
            isReadOnly: false,
            source: "connor-calendar-source"
        )
        accounts = mergeAccounts(accounts, [account])
        collections = mergeCollections(collections, [collection])
        selectedEventID = nil
        isPresentingAddSourceSheet = false
        rebuildPresentation()
        syncMessage = "已添加日历源：\(resolvedDisplayName)"
        persistAndNotifySourceSetChanged(failurePrefix: nil)
    }

    func addSourceFromWizard(account: CalendarAccount, credential: String?) {
        guard !isShutdown else { return }
        if let credential, !credential.isEmpty, let username = account.configuration.username {
            let binding = AppCalendarCredentialStore.binding(
                accountID: account.id,
                username: username,
                authMode: account.configuration.authMode
            )
            try? credentialStore.saveCredential(credential, binding: binding)
        }
        accounts = mergeAccounts(accounts, [account])
        selectedEventID = nil
        isPresentingAddSourceSheet = false
        syncMessage = "已添加日历源：\(account.displayName)，正在同步…"
        rebuildPresentation()
        persistAndNotifySourceSetChanged(failurePrefix: "日历源同步失败：")
    }

    func setSyncMode(accountID: CalendarAccountID, mode: CalendarSourceSyncMode) {
        guard !isShutdown, let index = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        guard accounts[index].sourceKind.supportsWrite else { return }
        accounts[index].configuration.syncMode = mode
        accounts[index].updatedAt = Date()
        startOwnedTask { [weak self] in
            guard let self else { return }
            do {
                await self.persistSnapshot()
            }
        }
    }

    func deleteSource(_ account: CalendarAccount) {
        guard !isShutdown else { return }
        let collectionIDs = Set(collections.filter { $0.accountID == account.id }.map(\.id))
        accounts.removeAll { $0.id == account.id }
        collections.removeAll { $0.accountID == account.id }
        events.removeAll { collectionIDs.contains($0.calendarID) }
        if let selectedEventID, !events.contains(where: { $0.id == selectedEventID }) {
            self.selectedEventID = nil
        }
        rebuildPresentation()
        syncMessage = "已移除日历源：\(account.displayName)"
        persistAndNotifySourceSetChanged(failurePrefix: nil)
    }

    func refreshForScheduledTask(sourceInstanceID: String?, runID: String?) async -> String {
        if let sourceInstanceID, !sourceInstanceID.isEmpty,
           sourceInstanceID != CalendarEventKitAdapter.systemAccountID.rawValue {
            guard let account = accounts.first(where: { $0.id.rawValue == sourceInstanceID }) else {
                return "Calendar account not found: \(sourceInstanceID)"
            }
            guard let runtimeStore else { return "Calendar runtime store unavailable" }
            do {
                let result = try await remoteAccountSynchronizer(
                    account,
                    readCredential(for: account),
                    runID,
                    runtimeStore
                )
                let snapshot = try await runtimeStore.loadSnapshot()
                guard !Task.isCancelled, !isShutdown else { return "Calendar refresh failed for account \(sourceInstanceID): cancelled" }
                accounts = mergeAccounts(accounts, snapshot.accounts)
                collections = mergeCollections(collections, snapshot.collections)
                events = mergeEvents(events, snapshot.events)
                rebuildPresentation()
                await persistSnapshot()
                return "Calendar refreshed account \(sourceInstanceID); synced \(result.events.count) events across \(result.collections.count) calendars"
            } catch {
                return "Calendar refresh failed for account \(sourceInstanceID): \(error.localizedDescription)"
            }
        }
        let succeeded = await syncSystemCalendarNow()
        return succeeded ? (syncMessage ?? "Calendar refreshed") : (syncMessage ?? "Calendar refresh failed")
    }

    /// 手动刷新全部日历源：本机日历 + 所有已配置的远程账户（CalDAV/ICS）。
    var showsSyncStatusBanner: Bool {
        isSyncingAll && syncMessage != nil && !isSyncStatusBannerDismissed
    }

    /// 关闭当前同步状态提示；下一次新同步开始时自动恢复显示。
    func dismissSyncStatusBanner() {
        isSyncStatusBannerDismissed = true
    }

    func syncAllSources() {
        guard !isShutdown, !isSyncingAll else { return }
        isSyncingAll = true
        isSyncStatusBannerDismissed = false
        syncMessage = "正在同步全部日历源…"
        startOwnedTask { [weak self] in
            guard let self else { return }
            defer { self.isSyncingAll = false }
            var summaries: [String] = []
            var failures: [String] = []
            // 1) 本机系统日历（EventKit）
            let systemOK = await self.syncSystemCalendarNow()
            if systemOK, let message = self.syncMessage { summaries.append(message) }
            // 2) 远程账户（CalDAV / ICS 订阅）
            for account in self.accounts where account.id.rawValue != CalendarEventKitAdapter.systemAccountID.rawValue {
                guard let runtimeStore = self.runtimeStore else { continue }
                do {
                    let result = try await self.remoteAccountSynchronizer(
                        account,
                        self.readCredential(for: account),
                        nil,
                        runtimeStore
                    )
                    let snapshot = try await runtimeStore.loadSnapshot()
                    guard !Task.isCancelled, !self.isShutdown else { return }
                    self.accounts = self.mergeAccounts(self.accounts, snapshot.accounts)
                    self.collections = self.mergeCollections(self.collections, snapshot.collections)
                    self.events = self.mergeEvents(self.events, snapshot.events)
                    self.rebuildPresentation()
                    await self.persistSnapshot()
                    summaries.append("\(account.displayName)：\(result.events.count) 个日程")
                } catch is CancellationError {
                    return
                } catch {
                    failures.append("\(account.displayName)：\(error.localizedDescription)")
                }
            }
            if summaries.isEmpty { summaries.append("已同步全部日历源") }
            let combined = summaries.joined(separator: "；")
            if failures.isEmpty {
                self.syncMessage = combined
                self.reportSuccess()
            } else {
                let failureSummary = failures.joined(separator: "；")
                self.syncMessage = combined + "；失败：\(failureSummary)"
                self.reportFailure(failureSummary)
            }
        }
    }

    func waitForPendingOperations() async {
        await Task.yield()
        while !ownedTasks.isEmpty {
            for task in Array(ownedTasks.values) { await task.value }
        }
    }

    func shutdown() {
        guard !isShutdown else { return }
        isShutdown = true
        reloadGeneration &+= 1
        if let cacheObserver {
            notificationCenter.removeObserver(cacheObserver)
            self.cacheObserver = nil
        }
        for task in ownedTasks.values { task.cancel() }
        ownedTasks.removeAll()
    }

    private func loadLegacySnapshot() async throws -> FileBackedCalendarSourceStore.Snapshot? {
        guard let legacyStore else { return nil }
        return try await legacyStore.loadSnapshot()
    }

    private func loadRuntimeSnapshot() async throws -> CalendarSourceRuntimeSnapshot? {
        guard let runtimeStore else { return nil }
        return try await runtimeStore.loadSnapshot()
    }

    private func persistAndNotifySourceSetChanged(failurePrefix: String?) {
        startOwnedTask { [weak self] in
            guard let self else { return }
            do {
                let persisted = await self.persistSnapshot()
                guard !Task.isCancelled, !self.isShutdown else { return }
                try await self.sourceSetChanged()
                if persisted { self.reportSuccess() }
            } catch is CancellationError {
                return
            } catch {
                let message = (failurePrefix ?? "") + error.localizedDescription
                self.syncMessage = failurePrefix == nil ? self.syncMessage : message
                self.reportFailure(message)
            }
        }
    }

    @discardableResult
    private func persistSnapshot() async -> Bool {
        do {
            let accounts = accounts
            let collections = collections
            let events = events
            if let legacyStore {
                try await legacyStore.saveSnapshot(
                    FileBackedCalendarSourceStore.Snapshot(
                        accounts: accounts,
                        collections: collections,
                        events: events
                    )
                )
            }
            if let runtimeStore {
                let existing = try await runtimeStore.loadSnapshot()
                try await runtimeStore.saveSnapshot(
                    CalendarSourceRuntimeSnapshot(
                        accounts: accounts,
                        collections: collections,
                        events: events,
                        syncStates: existing.syncStates,
                        diagnostics: existing.diagnostics,
                        mutationAudits: existing.mutationAudits
                    )
                )
            }
            return true
        } catch {
            reportFailure("无法保存日历缓存：\(error.localizedDescription)")
            return false
        }
    }

    private func upsertSystemCalendarSnapshot(_ snapshot: CalendarEventKitSnapshot) {
        let systemAccountIDs = Set(snapshot.accounts.map(\.id))
        let systemCalendarIDs = Set(snapshot.collections.map(\.id))
        accounts = (accounts.filter { !systemAccountIDs.contains($0.id) } + snapshot.accounts)
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        collections = (collections.filter {
            $0.accountID != CalendarEventKitAdapter.systemAccountID && !systemCalendarIDs.contains($0.id)
        } + snapshot.collections)
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        events = (events.filter { !systemCalendarIDs.contains($0.calendarID) } + snapshot.events)
            .sorted { $0.start.date < $1.start.date }
        rebuildPresentation()
    }

    private func rebuildPresentation() {
        presentation = NativeCalendarBrowserPresentation.build(events: events, collections: collections)
        if let selectedEventID, !events.contains(where: { $0.id == selectedEventID }) {
            self.selectedEventID = events.first?.id
        }
        onEvent?(.presentationChanged(events))
    }

    private func readCredential(for account: CalendarAccount) -> String? {
        if account.configuration.authMode == .none { return nil }
        if let username = account.configuration.username {
            let binding = AppCalendarCredentialStore.binding(
                accountID: account.id,
                username: username,
                authMode: account.configuration.authMode
            )
            return try? credentialStore.readCredential(binding: binding)
        }
        if let binding = account.credentialBinding {
            return try? credentialStore.credentialStore.readSecret(
                service: binding.credentialNamespace,
                account: binding.accountName
            )
        }
        return nil
    }

    private func mergeAccounts(_ primary: [CalendarAccount], _ overlay: [CalendarAccount]) -> [CalendarAccount] {
        var byID = Dictionary(uniqueKeysWithValues: primary.map { ($0.id, $0) })
        for account in overlay { byID[account.id] = account }
        return byID.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private func mergeCollections(_ primary: [CalendarCollection], _ overlay: [CalendarCollection]) -> [CalendarCollection] {
        var byID = Dictionary(uniqueKeysWithValues: primary.map { ($0.id, $0) })
        for collection in overlay { byID[collection.id] = collection }
        return byID.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private func mergeEvents(_ primary: [CalendarEvent], _ overlay: [CalendarEvent]) -> [CalendarEvent] {
        var byID = Dictionary(uniqueKeysWithValues: primary.map { ($0.id, $0) })
        for event in overlay { byID[event.id] = event }
        return byID.values.sorted { $0.start.date < $1.start.date }
    }

    private func calendarProviderDisplayName(_ provider: ConnectedAccountProviderKind) -> String {
        switch provider {
        case .appleICloud: "Apple iCloud"
        case .microsoft365, .google: "已停止支持的旧账户"
        case .qq: "QQ"
        case .netEase: "网易"
        case .genericIMAPSMTP: "自定义 IMAP/SMTP"
        case .genericCalDAVCardDAV: "自定义 CalDAV / CardDAV"
        case .localFixture: "本机日历"
        }
    }

    private func startOwnedTask(_ operation: @escaping @MainActor () async -> Void) {
        let id = UUID()
        ownedTasks[id] = Task { @MainActor [weak self] in
            await operation()
            self?.ownedTasks[id] = nil
        }
    }

    private func reportSuccess() {
        errorMessage = nil
        onEvent?(.operationSucceeded)
    }

    private func reportFailure(_ message: String) {
        errorMessage = message
        onEvent?(.operationFailed(message))
    }
}
