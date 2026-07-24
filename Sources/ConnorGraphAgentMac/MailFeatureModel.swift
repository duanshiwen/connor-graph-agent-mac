import Foundation
import Observation
import ConnorGraphCore
import ConnorGraphAppSupport

@MainActor
@Observable
final class MailFeatureModel {
    enum Event { case operationSucceeded; case operationFailed(String) }
    typealias SyncServiceFactory = @Sendable () -> MailIMAPInitialSyncService

    var presentation: NativeMailBrowserPresentation = .empty {
        didSet {
            bodyDisplayCache.removeAll()
            bodyDisplayCacheOrder.removeAll()
            preparedHTMLCache.removeAll()
            rebuildListProjection()
        }
    }
    var searchQuery = "" {
        didSet {
            guard searchQuery != oldValue else { return }
            rebuildListProjection()
            reloadForCurrentListFilters()
        }
    }
    var listDirectionFilter: MailMessageDirectionFilter = .all {
        didSet {
            guard listDirectionFilter != oldValue else { return }
            rebuildListProjection()
            reloadForCurrentListFilters()
        }
    }
    private(set) var filteredListMessages: [MailMessageSummary] = []
    private(set) var visibleListMessages: [MailMessageSummary] = []
    private(set) var visibleListMessageIDs: Set<MailMessageID> = []
    private(set) var listProjectionRevision: UInt64 = 0
    private(set) var isLoadingNextPage = false
    var selectedAccountID: MailAccountID?
    var selectedMailboxID: MailMailboxID?
    var selectedMessageID: MailMessageID?
    private(set) var selectedMessageSummary: MailMessageSummary?
    private(set) var navigationTargetID: MailMessageID?
    private(set) var navigationMessage: String?
    private(set) var preferences = MailPreferences()
    var isPresentingAddAccountSheet = false
    private(set) var syncMessage: String?
    private(set) var errorMessage: String?

    @ObservationIgnored private let store: FileBackedMailSourceStore?
    @ObservationIgnored private let preferencesStore: (any MailPreferencesStore)?
    @ObservationIgnored private let credentialStore: AppMailCredentialStore
    @ObservationIgnored private let syncServiceFactory: SyncServiceFactory
    @ObservationIgnored private var cacheObserver: NSObjectProtocol?
    @ObservationIgnored private var reloadGeneration: UInt64 = 0
    @ObservationIgnored private let listPageSize = 50
    @ObservationIgnored private var nextListPageCursor: String?
    @ObservationIgnored private var loadedListQuery = ""
    @ObservationIgnored private var loadedListDirection: MailMessageDirectionFilter = .all
    @ObservationIgnored private var bodyDisplayCache: [MailMessageID: MailBodyDisplayPresentation] = [:]
    @ObservationIgnored private var bodyDisplayCacheOrder: [MailMessageID] = []
    @ObservationIgnored let preparedHTMLCache = MailHTMLRenderCache(capacity: 8, byteCapacity: 4 * 1_024 * 1_024)
    @ObservationIgnored private var ownedTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var isShutdown = false
    @ObservationIgnored var sourceSetChanged: @MainActor () async throws -> Void = {}
    @ObservationIgnored var onEvent: ((Event) -> Void)?

    init(
        store: FileBackedMailSourceStore?,
        preferencesStore: (any MailPreferencesStore)?,
        credentialStore: AppMailCredentialStore = AppMailCredentialStore(),
        syncServiceFactory: @escaping SyncServiceFactory = { MailIMAPInitialSyncService(messageLimit: 0) },
        notificationCenter: NotificationCenter = .default
    ) {
        self.store = store
        self.preferencesStore = preferencesStore
        self.credentialStore = credentialStore
        self.syncServiceFactory = syncServiceFactory
        cacheObserver = notificationCenter.addObserver(forName: .connorMailCacheDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.reload() }
        }
    }

    var agentRuntime: MailRuntime? {
        guard let store else { return nil }
        return MailRuntime(repository: store, cache: store, credentialStore: credentialStore, preferencesStore: preferencesStore)
    }
    var sourceRepository: (any MailSourceRepository)? { store }
    var sharedStoreForTests: FileBackedMailSourceStore? { store }

    func reload() async {
        guard !isShutdown, let store else { return }
        reloadGeneration &+= 1
        let generation = reloadGeneration
        do {
            let requestedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            let requestedDirection = listDirectionFilter
            let (loaded, nextCursor) = try await store.presentationPage(MailMessagePageRequest(
                query: requestedQuery,
                direction: requestedDirection,
                pageSize: listPageSize
            ))
            let loadedPreferences = try await reconciledPreferences(accounts: loaded.accounts)
            guard !Task.isCancelled, !isShutdown, generation == reloadGeneration else { return }
            loadedListQuery = requestedQuery
            loadedListDirection = requestedDirection
            nextListPageCursor = nextCursor
            presentation = loaded
            preferences = loadedPreferences
            repairSelection()
            reportSuccess()
        } catch is CancellationError { return }
        catch {
            guard !isShutdown, generation == reloadGeneration else { return }
            reportFailure("无法加载邮件缓存：\(error.localizedDescription)")
        }
    }

    func fallbackSearchResults(query: String, now: Date, limit: Int) -> [NativeSearchResult] {
        let normalized = query.lowercased()
        return presentation.messages.filter { message in
            normalized.isEmpty || message.subject.lowercased().contains(normalized)
                || message.snippet.lowercased().contains(normalized)
                || message.from.email.lowercased().contains(normalized)
                || (message.from.name?.lowercased().contains(normalized) ?? false)
                || message.to.contains { $0.email.lowercased().contains(normalized) || ($0.name?.lowercased().contains(normalized) ?? false) }
        }.sorted { $0.date > $1.date }.prefix(limit).map { message in
            NativeSearchResult(id: "mail:\(message.id.rawValue)", sourceKind: .mail, externalID: message.id.rawValue, sourceInstanceID: message.accountID.rawValue, title: message.subject.isEmpty ? "(No subject)" : message.subject, snippet: [message.from.name ?? message.from.email, message.snippet].filter { !$0.isEmpty }.joined(separator: " · "), score: 1, lexicalScore: 1, freshnessScore: 0, fieldScore: 0, temporal: NativeSearchTemporalMetadata(primaryTime: message.date, primaryTimeKind: .sentAt, receivedAt: message.date, sentAt: message.date, indexedAt: now), resultTimeLabel: message.date.connorLocalFormatted(date: .medium, time: .short))
        }
    }

    func openSearchResult(_ result: NativeSearchResult) {
        searchQuery = ""
        guard let messageID = Self.messageID(from: result) else {
            syncMessage = "无法打开这封邮件：搜索结果缺少有效 messageID。"; return
        }
        if let message = presentation.message(id: messageID) ?? legacyMatch(messageID) { selectMessage(message); return }
        selectedMessageID = messageID
        navigationTargetID = messageID
        navigationMessage = "正在打开搜索结果中的邮件…"
        startOwnedTask { [weak self] in await self?.loadAndSelectMessageIfNeeded(messageID) }
    }

    static func normalizeIDForSearchIndex(_ rawID: String) -> String {
        var value = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("mail:") { value = String(value.dropFirst(5)) }
        if value.hasPrefix("mail-") { value = String(value.dropFirst(5)) }
        return value.replacingOccurrences(of: "_", with: "-").replacingOccurrences(of: "@", with: "-").replacingOccurrences(of: ".", with: "-")
    }

    func selectMessageFromList(_ message: MailMessageSummary) { selectMessage(message) }
    func selectedMessageForDetail() -> MailMessageSummary? {
        if let message = presentation.message(id: selectedMessageID) { return message }
        return selectedMessageSummary?.id == selectedMessageID ? selectedMessageSummary : nil
    }
    func listMessages(direction: MailMessageDirectionFilter = .all) -> [MailMessageSummary] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? presentation.unqueriedMessages(direction: direction) : presentation.messages(accountID: nil, mailboxID: nil, query: query, direction: direction)
    }

    func loadMoreListMessagesIfNeeded(currentMessageID: MailMessageID) {
        guard visibleListMessages.last?.id == currentMessageID,
              nextListPageCursor != nil,
              !isLoadingNextPage else { return }
        startOwnedTask { [weak self] in await self?.loadNextListPage() }
    }

    func presentAddAccountSheet() { isPresentingAddAccountSheet = true }

    func setDefaultSendAccount(_ accountID: MailAccountID) async {
        do {
            guard let account = presentation.account(id: accountID) else { reportFailure("无法设置默认发信账户：账户不存在"); return }
            guard let identity = account.identities.first(where: \.canSend) else { reportFailure("无法设置默认发信账户：该账户没有可发送身份"); return }
            let value = MailPreferences(defaultSendAccountID: account.id, defaultSendIdentityID: identity.id)
            preferences = value
            try await preferencesStore?.save(value)
            reportSuccess()
        } catch { reportFailure("无法保存默认发信账户：\(error.localizedDescription)") }
    }

    func loadBodyDisplay(for messageID: MailMessageID) async -> MailBodyDisplayPresentation {
        if let cached = bodyDisplayCache[messageID] { return cached }
        do {
            guard let detail = try await store?.message(id: messageID) else { return .init(kind: .error, text: "无法读取邮件正文：本地缓存中找不到这封邮件") }
            guard !Task.isCancelled else { return .loading }
            if MailBodyOnDemandFetchPlanner.hasDisplayableBody(detail) {
                let display = await MailBodyDisplayPresentation.preparing(detail: detail)
                cacheBodyDisplay(display, for: messageID)
                return display
            }
            do {
                let fetched = try await fetchAndCacheBody(detail)
                try Task.checkCancellation()
                let display = await MailBodyDisplayPresentation.preparing(detail: fetched)
                cacheBodyDisplay(display, for: messageID)
                return display
            } catch is CancellationError { return .loading }
            catch { let message = "无法按需读取邮件正文：\(error.localizedDescription)"; reportFailure(message); return .error(message, fallback: detail.summary.snippet) }
        } catch is CancellationError { return .loading }
        catch { let message = "无法读取邮件正文：\(error.localizedDescription)"; reportFailure(message); return .init(kind: .error, text: message) }
    }

    func addAccountAndPrepareSync(preset: MailAccountProviderPreset, displayName: String, email: String, credential: String, incomingHost: String, incomingPort: Int, outgoingHost: String, outgoingPort: Int) async throws {
        try await addAccountAndPrepareSync(displayName: displayName, email: email, provider: .genericIMAPSMTP, incomingHost: incomingHost, incomingPort: incomingPort, incomingSecurity: preset.incomingSecurity, outgoingHost: outgoingHost, outgoingPort: outgoingPort, outgoingSecurity: preset.outgoingSecurity, username: email, password: credential, authMode: preset.authMode)
    }

    func addAccountAndPrepareSync(displayName: String, email: String, provider: MailProviderKind, incomingHost: String, incomingPort: Int, incomingSecurity: MailConnectionSecurity, outgoingHost: String, outgoingPort: Int, outgoingSecurity: MailConnectionSecurity, username: String, password: String, authMode: MailAuthMode) async throws {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let accountID = MailAccountID(rawValue: normalizedEmail)
        let resolvedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? normalizedEmail : username.trimmingCharacters(in: .whitespacesAndNewlines)
        let identity = MailIdentity(id: MailIdentityID(rawValue: "identity-\(accountID.rawValue)"), displayName: displayName, address: MailAddress(name: displayName, email: normalizedEmail))
        let binding = AppMailCredentialStore.binding(accountID: accountID, email: resolvedUsername, authMode: authMode)
        let account = MailAccount(id: accountID, provider: provider, displayName: displayName.isEmpty ? email : displayName, identities: [identity], incoming: MailServerEndpoint(host: incomingHost, port: incomingPort, security: incomingSecurity, protocolKind: .imap), outgoing: MailServerEndpoint(host: outgoingHost, port: outgoingPort, security: outgoingSecurity, protocolKind: .smtp), credentialBinding: binding, health: MailAccountHealth(status: .unknown, summary: "Ready to sync"))
        let inbox = MailMailbox(id: MailMailboxID(rawValue: "\(accountID.rawValue)-inbox"), accountID: accountID, name: "Inbox", path: "INBOX", role: .inbox)
        try credentialStore.saveCredential(password, binding: binding)
        try await store?.saveAccount(account); try await store?.saveMailbox(inbox)
        selectedAccountID = accountID; selectedMailboxID = inbox.id
        syncMessage = "已添加邮箱：\(account.displayName)，正在同步最近邮件…"
        await reload()
        isPresentingAddAccountSheet = false
        do { try await sourceSetChanged(); let summary = try await refreshForScheduledTask(sourceInstanceID: accountID.rawValue, runID: nil); syncMessage = summary; try await sourceSetChanged() }
        catch { let message = String(describing: error); syncMessage = "邮箱已添加，但同步失败：\(message)"; reportFailure(message) }
    }

    func rebuildCacheAndRefresh() async -> String {
        do {
            guard let store else { return "Mail store unavailable" }
            try await store.clearCachedMailData(); await reload()
            let result = try await refreshForScheduledTask(sourceInstanceID: nil, runID: nil)
            let message = "已清空本地邮件缓存并重新同步。\(result)"; syncMessage = message; return message
        } catch { let message = "无法重建邮件缓存：\(error.localizedDescription)"; syncMessage = message; reportFailure(message); return message }
    }

    func refreshForScheduledTask(sourceInstanceID: String?, runID: String?) async throws -> String {
        guard let store else { return "Mail store unavailable" }
        let accounts: [MailAccount]
        if let sourceInstanceID, !sourceInstanceID.isEmpty {
            guard let account = try await store.account(id: MailAccountID(rawValue: sourceInstanceID)) else { return "Mail account not found: \(sourceInstanceID)" }
            accounts = [account]
        } else { accounts = try await store.listAccounts() }
        guard !accounts.isEmpty else { return "No mail accounts configured" }
        let syncService = syncServiceFactory(); var count = 0; var summaries: [String] = []
        for account in accounts {
            let boxes = try await store.listMailboxes(accountID: account.id)
            let uids = try await storedUIDs(accountID: account.id, mailboxes: boxes, store: store)
            let validity = Dictionary(uniqueKeysWithValues: boxes.map { ($0.id, $0.status.syncCursor?.uidValidity) })
            let result = (!uids.isEmpty || boxes.contains { $0.status.lastSyncedAt != nil }) ? try await syncService.syncIncremental(account: account, storedUIDsByMailboxID: uids, storedUIDValidityByMailboxID: validity) : try await syncService.sync(account: account)
            try await store.saveAccount(result.account)
            for box in result.mailboxes { try await store.saveMailbox(box) }
            if !result.messages.isEmpty { try await store.saveMessagesBatch(result.messages) }
            count += result.messages.count; summaries.append("\(result.account.displayName)：\(result.account.health.summary)")
        }
        await reload(); let summary = summaries.joined(separator: "；")
        if let sourceInstanceID, !sourceInstanceID.isEmpty { return "Mail refreshed account \(sourceInstanceID); synced \(count) message(s). \(summary)" }
        return "Mail refreshed \(accounts.count) account(s); synced \(count) message(s). \(summary)"
    }

    func waitForPendingOperations() async { while !ownedTasks.isEmpty { for task in Array(ownedTasks.values) { await task.value } } }
    func shutdown(notificationCenter: NotificationCenter = .default) {
        guard !isShutdown else { return }; isShutdown = true; reloadGeneration &+= 1
        if let cacheObserver { notificationCenter.removeObserver(cacheObserver); self.cacheObserver = nil }
        for task in ownedTasks.values { task.cancel() }; ownedTasks.removeAll()
        bodyDisplayCache.removeAll()
        bodyDisplayCacheOrder.removeAll()
        preparedHTMLCache.removeAll()
    }

    private func rebuildListProjection() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if query == loadedListQuery, listDirectionFilter == loadedListDirection {
            filteredListMessages = presentation.messages
        } else {
            filteredListMessages = listMessages(direction: listDirectionFilter)
        }
        visibleListMessages = filteredListMessages
        visibleListMessageIDs = Set(filteredListMessages.map(\.id))
        listProjectionRevision &+= 1
    }

    private func reloadForCurrentListFilters() {
        guard !isShutdown else { return }
        startOwnedTask { [weak self] in await self?.reload() }
    }

    private func loadNextListPage() async {
        guard !isShutdown, !isLoadingNextPage, let cursor = nextListPageCursor, let store else { return }
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let direction = listDirectionFilter
        guard query == loadedListQuery, direction == loadedListDirection else { return }
        isLoadingNextPage = true
        defer { isLoadingNextPage = false }
        do {
            let page = try await store.messagePage(MailMessagePageRequest(
                query: query,
                direction: direction,
                pageSize: listPageSize,
                cursor: cursor
            ))
            guard !Task.isCancelled,
                  query == searchQuery.trimmingCharacters(in: .whitespacesAndNewlines),
                  direction == listDirectionFilter else { return }
            let existingIDs = Set(presentation.messages.map(\.id))
            let appended = page.messages.filter { !existingIDs.contains($0.id) }
            nextListPageCursor = page.nextCursor
            presentation = NativeMailBrowserPresentation(
                accounts: presentation.accounts,
                mailboxes: presentation.mailboxes,
                messages: presentation.messages + appended
            )
        } catch is CancellationError {
            return
        } catch {
            reportFailure("无法加载更多邮件：\(error.localizedDescription)")
        }
    }

    private func cacheBodyDisplay(_ display: MailBodyDisplayPresentation, for messageID: MailMessageID) {
        bodyDisplayCache[messageID] = display
        bodyDisplayCacheOrder.removeAll { $0 == messageID }
        bodyDisplayCacheOrder.append(messageID)
        while bodyDisplayCacheOrder.count > 8 {
            bodyDisplayCache.removeValue(forKey: bodyDisplayCacheOrder.removeFirst())
        }
    }

    private func reconciledPreferences(accounts: [MailAccount]) async throws -> MailPreferences {
        guard let preferencesStore else { return preferences }
        let loaded = try await preferencesStore.load(); let value = MailDefaultSendAccountReconciler.reconcile(preferences: loaded, accounts: accounts)
        if value != loaded { try await preferencesStore.save(value) }; return value
    }
    private func repairSelection() {
        if selectedAccountID == nil || presentation.account(id: selectedAccountID) == nil { selectedAccountID = presentation.defaultAccountID() }
        if selectedMailboxID == nil || presentation.mailbox(id: selectedMailboxID) == nil { selectedMailboxID = presentation.defaultMailboxID(for: selectedAccountID) }
        if let message = presentation.message(id: selectedMessageID) { selectedMessageSummary = message }
        else if selectedMessageID == nil || selectedMessageSummary?.id != selectedMessageID { selectedMessageID = presentation.defaultMessageID(accountID: selectedAccountID, mailboxID: selectedMailboxID); selectedMessageSummary = presentation.message(id: selectedMessageID) }
    }
    private func selectMessage(_ message: MailMessageSummary) { selectedAccountID = message.accountID; selectedMailboxID = message.mailboxID; selectedMessageID = message.id; selectedMessageSummary = message; navigationTargetID = nil; navigationMessage = nil }
    private func legacyMatch(_ id: MailMessageID) -> MailMessageSummary? { let key = Self.normalizeIDForSearchIndex(id.rawValue); return presentation.messages.first { Self.normalizeIDForSearchIndex($0.id.rawValue) == key } }
    private static func messageID(from result: NativeSearchResult) -> MailMessageID? { let raw = result.externalID.trimmingCharacters(in: .whitespacesAndNewlines); guard !raw.isEmpty else { return nil }; let value = raw.hasPrefix("mail:") ? String(raw.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines) : raw; return value.isEmpty ? nil : MailMessageID(rawValue: value) }
    private func loadAndSelectMessageIfNeeded(_ id: MailMessageID) async {
        guard selectedMessageID == id else { return }
        if let message = presentation.message(id: id) ?? legacyMatch(id) { selectMessage(message); return }
        do {
            guard let detail = try await store?.message(id: id) else { let message = "这封邮件可能已从本地缓存移除，请重新同步邮箱。"; syncMessage = message; navigationMessage = message; navigationTargetID = nil; return }
            selectMessage(detail.summary); await reload(); if let message = presentation.message(id: id) { selectMessage(message) }; syncMessage = nil; navigationTargetID = nil; navigationMessage = nil
        } catch { let message = "无法打开这封邮件：\(error.localizedDescription)"; NSLog("[Connor.Mail] failed to load message: id=%@, error=%@", id.rawValue, error.localizedDescription); syncMessage = message; navigationMessage = message; navigationTargetID = nil }
    }
    private func fetchAndCacheBody(_ detail: MailMessageDetail) async throws -> MailMessageDetail {
        guard let store else { return detail }; guard let account = try await store.account(id: detail.summary.accountID) else { throw NSError(domain: "Connor.MailBody", code: 1, userInfo: [NSLocalizedDescriptionKey: "找不到邮件账户"]) }
        guard let uid = MailBodyOnDemandFetchPlanner.imapUID(for: detail) else { throw NSError(domain: "Connor.MailBody", code: 2, userInfo: [NSLocalizedDescriptionKey: "缺少邮件 UID"]) }
        let boxes = try await store.listMailboxes(accountID: detail.summary.accountID); let box = boxes.first { $0.id == detail.summary.mailboxID }
        let service = MailIMAPInitialSyncService(credentialStore: credentialStore, messageLimit: 0)
        guard let fetched = try await service.fetchMessageBody(account: account, uid: uid, messageID: detail.id, mailboxID: detail.summary.mailboxID, mailboxPath: box?.path ?? "INBOX", mailboxRole: box?.role ?? .inbox, snippet: detail.summary.snippet) else { throw NSError(domain: "Connor.MailBody", code: 3, userInfo: [NSLocalizedDescriptionKey: "服务器未返回可显示正文"]) }
        guard MailBodyOnDemandFetchPlanner.hasDisplayableBody(fetched) else { throw NSError(domain: "Connor.MailBody", code: 4, userInfo: [NSLocalizedDescriptionKey: "服务器返回的正文为空"]) }
        try await store.saveMessage(fetched); await reload(); return fetched
    }
    private func storedUIDs(accountID: MailAccountID, mailboxes: [MailMailbox], store: any MailStoreProtocol) async throws -> [MailMailboxID: Set<String>] { let remotes = mailboxes.map { RemoteIMAPMailbox(name: $0.name, path: $0.path, role: $0.role) }; let ids = try await store.allMessageIDs(); var result: [MailMailboxID:Set<String>] = [:]; for remote in remotes { let id = remote.mailboxID(accountID: accountID); let values = Set(ids.compactMap { remote.uid(fromMessageID: $0, accountID: accountID) }); if !values.isEmpty { result[id] = values } }; return result }
    private func startOwnedTask(_ operation: @escaping @MainActor () async -> Void) { let id = UUID(); ownedTasks[id] = Task { @MainActor [weak self] in await operation(); self?.ownedTasks[id] = nil } }
    private func reportSuccess() { errorMessage = nil; onEvent?(.operationSucceeded) }
    private func reportFailure(_ message: String) { errorMessage = message; onEvent?(.operationFailed(message)) }
}
