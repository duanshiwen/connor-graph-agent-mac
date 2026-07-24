import AppKit
import Foundation
import Observation
import SwiftUI
import WebKit
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore

enum BrowserLocalFilePreviewError: LocalizedError, Equatable {
    case unsupportedFile(String)
    case fileOutsideWorkspace(String)
    case fileMissing(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFile(let path): "只能在浏览器中预览 HTML 文件：\(path)"
        case .fileOutsideWorkspace(let path): "文件不在当前工作区范围内：\(path)"
        case .fileMissing(let path): "找不到要预览的文件：\(path)"
        }
    }
}

struct BrowserGlobalTabReference: Codable, Hashable, Identifiable, Sendable {
    var sessionID: String
    var tabID: UUID

    var id: String { "\(sessionID):\(tabID.uuidString)" }
}

struct BrowserGlobalTabItem: Identifiable, Equatable, Sendable {
    var reference: BrowserGlobalTabReference
    var sessionTitle: String
    var tab: AppBrowserTabSnapshot

    var id: String { reference.id }

    var displayTitle: String {
        let title = tab.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        if let host = URL(string: displayURL)?.host, !host.isEmpty { return host }
        return "新标签页"
    }

    var displayURL: String { tab.restoredURLString }
}

enum BrowserTabLayoutMode: String, Sendable, Equatable {
    case horizontal
    case vertical
}

struct BrowserGlobalTabGroup: Identifiable, Equatable, Sendable {
    var sessionID: String
    var sessionTitle: String
    var tabs: [BrowserGlobalTabItem]

    var id: String { sessionID }
}

struct BrowserGlobalTabGroupBuilder: Sendable {
    func groups(from tabs: [BrowserGlobalTabItem], query: String = "") -> [BrowserGlobalTabGroup] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var sessionOrder: [String] = []
        var groupsBySessionID: [String: BrowserGlobalTabGroup] = [:]

        for tab in tabs {
            let sessionID = tab.reference.sessionID
            if groupsBySessionID[sessionID] == nil {
                sessionOrder.append(sessionID)
                groupsBySessionID[sessionID] = BrowserGlobalTabGroup(
                    sessionID: sessionID,
                    sessionTitle: tab.sessionTitle,
                    tabs: []
                )
            }
            groupsBySessionID[sessionID]?.tabs.append(tab)
        }

        return sessionOrder.compactMap { sessionID in
            guard var group = groupsBySessionID[sessionID] else { return nil }
            guard !normalizedQuery.isEmpty else { return group }
            if group.sessionTitle.localizedCaseInsensitiveContains(normalizedQuery) {
                return group
            }
            group.tabs = group.tabs.filter { tab in
                tab.displayTitle.localizedCaseInsensitiveContains(normalizedQuery)
                    || tab.displayURL.localizedCaseInsensitiveContains(normalizedQuery)
            }
            return group.tabs.isEmpty ? nil : group
        }
    }
}

@MainActor
@Observable
final class BrowserFeatureModel {
    enum Event {
        case operationSucceeded
        case operationFailed(String)
    }

    struct SessionContext {
        var selectedSessionID: String?
        var activeSessionID: String
        var sessionTitlesByID: [String: String]
    }

    var isVisible = false
    private(set) var workspaceSessionID: String?
    var targetURLString = BrowserBuiltInPage.blankURLString
    private(set) var workspaceSnapshotsBySessionID: [String: AppBrowserStateSnapshot] = [:]
    private(set) var globalTabOrder: [BrowserGlobalTabReference] = []
    private(set) var tabLayoutMode: BrowserTabLayoutMode = .horizontal
    private(set) var isVerticalTabSidebarPinned = false
    let liveWebViewStore = BrowserLiveWebViewStore()
    private(set) var assistedTasksByID: [UUID: BrowserAssistedTaskState] = [:]
    private(set) var isBookmarksPanelVisible = false
    private(set) var bookmarkRecords: [BrowserBookmarkRecord] = []
    private(set) var filteredBookmarkRecords: [BrowserBookmarkRecord] = []
    private(set) var selectedBookmarkGroupName: String?
    private(set) var isHistoryPanelVisible = false
    private(set) var isDownloadsPanelVisible = false
    private(set) var historyRecords: [BrowserHistoryRecord] = []
    private(set) var filteredHistoryRecords: [BrowserHistoryRecord] = []
    private(set) var downloadItems: [BrowserDownloadItem] = []
    private(set) var sitePermissionRecords: [String: BrowserSitePermissionRecord] = [:]
    private(set) var formAssistantDisabledHosts: Set<String> = []
    var historySearchQuery = ""
    var internalBrowserEnabled = true
    private(set) var errorMessage: String?

    @ObservationIgnored private let historyStore: BrowserHistoryStore?
    @ObservationIgnored private let bookmarkStore: BrowserBookmarkStore?
    @ObservationIgnored private let nativeSourceSearchBackend: (any NativeSourceSearchBackend)?
    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private var assistedFetchRequestsByTaskID: [UUID: BrowserAssistedWebFetchRequest] = [:]
    @ObservationIgnored private var assistedFetchContinuationsByTaskID: [UUID: CheckedContinuation<BrowserAssistedWebFetchResult, Never>] = [:]
    @ObservationIgnored private var assistedFetchTimeoutTasksByID: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var historyContentFetchTasksByID: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var historyIndexMutationTask: Task<Void, Never>?
    @ObservationIgnored private var historyIndexMutationGeneration: UInt64 = 0
    @ObservationIgnored private var historyIndexRequiresRebuild = false
    @ObservationIgnored private var nextHistoryCursor: String?
    @ObservationIgnored private var workspaceSessionBinding = BrowserWorkspaceSessionBinding()
    @ObservationIgnored private var isShutdown = false
    @ObservationIgnored private(set) var automationRuntime: BrowserAutomationRuntime!
    private static let historyPageSize = 50

    @ObservationIgnored var sessionContextProvider: () -> SessionContext = {
        SessionContext(selectedSessionID: nil, activeSessionID: "__fallback__", sessionTitlesByID: [:])
    }
    @ObservationIgnored var persistWorkspaceSnapshot: (AppBrowserStateSnapshot, String) -> Void = { _, _ in }
    @ObservationIgnored var onShowWorkspace: (String) -> Void = { _ in }
    @ObservationIgnored var onReturnFromWorkspace: (String?) -> Void = { _ in }
    @ObservationIgnored var onNavigateHistoryRecord: (BrowserHistoryRecord, URL) -> Void = { _, _ in }
    @ObservationIgnored var onEvent: ((Event) -> Void)?

    init(
        historyStore: BrowserHistoryStore?,
        bookmarkStore: BrowserBookmarkStore?,
        nativeSourceSearchBackend: (any NativeSourceSearchBackend)?,
        userDefaults: UserDefaults = .standard
    ) {
        self.historyStore = historyStore
        self.bookmarkStore = bookmarkStore
        self.nativeSourceSearchBackend = nativeSourceSearchBackend
        self.userDefaults = userDefaults
        loadSitePermissions()
        loadFormAssistantPreferences()
        loadGlobalTabOrder()
        loadTabLayoutPreferences()
        liveWebViewStore.onWillEvict = { [weak self] key, webView, metadata in
            MainActor.assumeIsolated {
                self?.recordWebViewEviction(key: key, webView: webView, metadata: metadata)
            }
        }
        automationRuntime = BrowserAutomationRuntime(
            liveStore: liveWebViewStore,
            snapshotProvider: { [weak self] sessionID in self?.workspaceSnapshotsBySessionID[sessionID] },
            snapshotSaver: { [weak self] snapshot, sessionID in self?.saveWorkspaceSnapshot(snapshot, for: sessionID) },
            showWorkspace: { [weak self] sessionID in self?.showWorkspace(for: sessionID) }
        )
    }

    func toggleDownloadsPanel() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isDownloadsPanelVisible.toggle()
            if isDownloadsPanelVisible {
                isBookmarksPanelVisible = false
                isHistoryPanelVisible = false
            }
        }
    }

    func closeDownloadsPanel() { isDownloadsPanelVisible = false }

    func updateDownload(_ item: BrowserDownloadItem) {
        if let index = downloadItems.firstIndex(where: { $0.id == item.id }) {
            if downloadItems[index].status == .cancelled, item.status != .cancelled { return }
            downloadItems[index] = item
        } else {
            downloadItems.insert(item, at: 0)
        }
        if item.status == .preparing || item.status == .downloading {
            isDownloadsPanelVisible = true
            isBookmarksPanelVisible = false
            isHistoryPanelVisible = false
        }
    }

    func clearCompletedDownloads() {
        downloadItems.removeAll { [.finished, .failed, .cancelled].contains($0.status) }
    }

    func markDownloadCancelled(_ id: UUID) {
        guard let index = downloadItems.firstIndex(where: { $0.id == id }) else { return }
        downloadItems[index].status = .cancelled
    }

    func permissionDecision(for origin: String, kind: BrowserSitePermissionKind) -> BrowserSitePermissionDecision? {
        sitePermissionRecords[origin]?.decisions[kind]
    }

    func setPermissionDecision(_ decision: BrowserSitePermissionDecision, for origin: String, kind: BrowserSitePermissionKind) {
        var record = sitePermissionRecords[origin] ?? BrowserSitePermissionRecord(origin: origin, decisions: [:])
        record.decisions[kind] = decision
        sitePermissionRecords[origin] = record
        persistSitePermissions()
    }

    func resetPermissions(for origin: String) {
        sitePermissionRecords.removeValue(forKey: origin)
        persistSitePermissions()
    }

    private static let sitePermissionsDefaultsKey = "browser.site-permissions.v1"
    private static let formAssistantDisabledHostsDefaultsKey = "browser.form-assistant.disabled-hosts.v1"
    private static let globalTabOrderDefaultsKey = "browser.global-tab-order.v1"
    private static let tabLayoutModeDefaultsKey = "browser.tab-layout-mode.v1"
    private static let verticalTabSidebarPinnedDefaultsKey = "browser.vertical-tab-sidebar-pinned.v1"

    func setTabLayoutMode(_ mode: BrowserTabLayoutMode) {
        guard tabLayoutMode != mode else { return }
        tabLayoutMode = mode
        userDefaults.set(mode.rawValue, forKey: Self.tabLayoutModeDefaultsKey)
    }

    func toggleTabLayoutMode() {
        setTabLayoutMode(tabLayoutMode == .horizontal ? .vertical : .horizontal)
    }

    func setVerticalTabSidebarPinned(_ isPinned: Bool) {
        guard isVerticalTabSidebarPinned != isPinned else { return }
        isVerticalTabSidebarPinned = isPinned
        userDefaults.set(isPinned, forKey: Self.verticalTabSidebarPinnedDefaultsKey)
    }

    func toggleVerticalTabSidebarPinned() {
        setVerticalTabSidebarPinned(!isVerticalTabSidebarPinned)
    }

    private func loadTabLayoutPreferences() {
        if let rawValue = userDefaults.string(forKey: Self.tabLayoutModeDefaultsKey),
           let mode = BrowserTabLayoutMode(rawValue: rawValue) {
            tabLayoutMode = mode
        }
        isVerticalTabSidebarPinned = userDefaults.bool(forKey: Self.verticalTabSidebarPinnedDefaultsKey)
    }

    private func loadSitePermissions() {
        guard let data = userDefaults.data(forKey: Self.sitePermissionsDefaultsKey),
              let records = try? JSONDecoder().decode([BrowserSitePermissionRecord].self, from: data)
        else { return }
        sitePermissionRecords = Dictionary(uniqueKeysWithValues: records.map { ($0.origin, $0) })
    }

    private func persistSitePermissions() {
        let records = sitePermissionRecords.values.sorted { $0.origin < $1.origin }
        guard let data = try? JSONEncoder().encode(records) else { return }
        userDefaults.set(data, forKey: Self.sitePermissionsDefaultsKey)
    }

    func isFormAssistantEnabled(for host: String) -> Bool {
        !formAssistantDisabledHosts.contains(host.lowercased())
    }

    func setFormAssistantEnabled(_ isEnabled: Bool, for host: String) {
        let normalized = host.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        if isEnabled {
            formAssistantDisabledHosts.remove(normalized)
        } else {
            formAssistantDisabledHosts.insert(normalized)
        }
        userDefaults.set(Array(formAssistantDisabledHosts).sorted(), forKey: Self.formAssistantDisabledHostsDefaultsKey)
    }

    private func loadFormAssistantPreferences() {
        let values = userDefaults.stringArray(forKey: Self.formAssistantDisabledHostsDefaultsKey) ?? []
        formAssistantDisabledHosts = Set(values.map { $0.lowercased() })
    }

    var currentSessionID: String {
        sessionContextProvider().selectedSessionID ?? sessionContextProvider().activeSessionID
    }

    var bookmarkGroupNames: [String] {
        let names = Set(bookmarkRecords.map {
            $0.groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? BrowserBookmarkRecord.defaultGroupName
                : $0.groupName
        })
        return names.sorted { lhs, rhs in
            if lhs == BrowserBookmarkRecord.defaultGroupName { return true }
            if rhs == BrowserBookmarkRecord.defaultGroupName { return false }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    func installLoadedWorkspaceSnapshot(_ snapshot: AppBrowserStateSnapshot, for sessionID: String) {
        workspaceSnapshotsBySessionID[sessionID] = snapshot
        reconcileGlobalTabOrder(for: sessionID)
    }

    func saveWorkspaceSnapshot(_ snapshot: AppBrowserStateSnapshot, for sessionID: String) {
        var normalized = snapshot
        normalized.updatedAt = Date()
        workspaceSnapshotsBySessionID[sessionID] = normalized
        reconcileGlobalTabOrder(for: sessionID)
        persistWorkspaceSnapshot(normalized, sessionID)
    }

    var globalTabs: [BrowserGlobalTabItem] {
        let titles = sessionContextProvider().sessionTitlesByID
        var tabsByReference: [BrowserGlobalTabReference: AppBrowserTabSnapshot] = [:]
        tabsByReference.reserveCapacity(globalTabOrder.count)
        for (sessionID, snapshot) in workspaceSnapshotsBySessionID {
            for tab in snapshot.tabs {
                tabsByReference[BrowserGlobalTabReference(sessionID: sessionID, tabID: tab.id)] = tab
            }
        }
        return globalTabOrder.compactMap { reference in
            guard let tab = tabsByReference[reference] else { return nil }
            return BrowserGlobalTabItem(
                reference: reference,
                sessionTitle: titles[reference.sessionID] ?? "未命名会话",
                tab: tab
            )
        }
    }

    @discardableResult
    func activateGlobalTab(_ reference: BrowserGlobalTabReference) -> Bool {
        guard var snapshot = workspaceSnapshotsBySessionID[reference.sessionID],
              snapshot.tabs.contains(where: { $0.id == reference.tabID }) else { return false }
        snapshot.selectedTabID = reference.tabID
        snapshot.selectionPopover = nil
        saveWorkspaceSnapshot(snapshot, for: reference.sessionID)
        showWorkspace(for: reference.sessionID)
        return true
    }

    func removeGlobalTab(_ reference: BrowserGlobalTabReference) {
        guard var snapshot = workspaceSnapshotsBySessionID[reference.sessionID],
              let index = snapshot.tabs.firstIndex(where: { $0.id == reference.tabID }) else { return }
        let wasSelected = snapshot.selectedTabID == reference.tabID
        snapshot.tabs.remove(at: index)
        snapshot.selectionPopover = snapshot.selectionPopover?.tabID == reference.tabID ? nil : snapshot.selectionPopover
        if wasSelected {
            snapshot.selectedTabID = snapshot.tabs.isEmpty ? nil : snapshot.tabs[min(index, snapshot.tabs.count - 1)].id
        }
        saveWorkspaceSnapshot(snapshot, for: reference.sessionID)
    }

    func replacementGlobalTab(afterClosing reference: BrowserGlobalTabReference) -> BrowserGlobalTabReference? {
        let references = globalTabs.map(\.reference)
        guard let index = references.firstIndex(of: reference), references.count > 1 else { return nil }
        return references[index == references.count - 1 ? index - 1 : index + 1]
    }

    func removeWorkspaceSnapshot(for sessionID: String) {
        workspaceSnapshotsBySessionID.removeValue(forKey: sessionID)
        globalTabOrder.removeAll { $0.sessionID == sessionID }
        persistGlobalTabOrder()
        if workspaceSessionID == sessionID { resetWorkspaceBinding() }
    }

    func retainWorkspaceSessions(_ sessionIDs: Set<String>) {
        workspaceSnapshotsBySessionID = workspaceSnapshotsBySessionID.filter { sessionIDs.contains($0.key) }
        globalTabOrder.removeAll { reference in
            guard sessionIDs.contains(reference.sessionID),
                  let snapshot = workspaceSnapshotsBySessionID[reference.sessionID] else { return true }
            return !snapshot.tabs.contains(where: { $0.id == reference.tabID })
        }
        persistGlobalTabOrder()
    }

    private func reconcileGlobalTabOrder(for sessionID: String) {
        guard let snapshot = workspaceSnapshotsBySessionID[sessionID] else { return }
        let validTabIDs = Set(snapshot.tabs.map(\.id))
        var updated = globalTabOrder.filter { reference in
            reference.sessionID != sessionID || validTabIDs.contains(reference.tabID)
        }
        let existing = Set(updated)
        updated.append(contentsOf: snapshot.tabs.compactMap { tab in
            let reference = BrowserGlobalTabReference(sessionID: sessionID, tabID: tab.id)
            return existing.contains(reference) ? nil : reference
        })
        guard updated != globalTabOrder else { return }
        globalTabOrder = updated
        persistGlobalTabOrder()
    }

    private func loadGlobalTabOrder() {
        guard let data = userDefaults.data(forKey: Self.globalTabOrderDefaultsKey),
              let references = try? JSONDecoder().decode([BrowserGlobalTabReference].self, from: data) else { return }
        globalTabOrder = references
    }

    private func persistGlobalTabOrder() {
        guard let data = try? JSONEncoder().encode(globalTabOrder) else { return }
        userDefaults.set(data, forKey: Self.globalTabOrderDefaultsKey)
    }

    @discardableResult
    func focusExistingTab(urlString: String, preferredSessionID: String) -> Bool {
        focusExistingTabIfPresent(urlString: urlString, preferredSessionID: preferredSessionID)
    }

    func openURL(_ url: URL, preferredSessionID: String? = nil) {
        let sessionID = preferredSessionID ?? currentSessionID
        let urlString = url.absoluteString
        let planner = BrowserExternalOpenPlanner()
        if focusExistingTabIfPresent(urlString: urlString, preferredSessionID: sessionID, planner: planner) { return }
        let current = workspaceSnapshotsBySessionID[sessionID] ?? AppBrowserStateSnapshot()
        targetURLString = urlString
        saveWorkspaceSnapshot(planner.openOrFocus(urlString: urlString, in: current), for: sessionID)
        showWorkspace(for: sessionID)
    }

    func openLocalHTMLPreview(fileURL: URL, readAccessRootURL: URL, preferredSessionID: String? = nil) {
        do {
            let file = fileURL.standardizedFileURL.resolvingSymlinksInPath()
            let root = readAccessRootURL.standardizedFileURL.resolvingSymlinksInPath()
            guard ["html", "htm"].contains(file.pathExtension.lowercased()) else {
                throw BrowserLocalFilePreviewError.unsupportedFile(file.path)
            }
            guard FileManager.default.fileExists(atPath: file.path) else {
                throw BrowserLocalFilePreviewError.fileMissing(file.path)
            }
            let rootPrefix = root.path == "/" ? "/" : root.path + "/"
            guard file.path == root.path || file.path.hasPrefix(rootPrefix) else {
                throw BrowserLocalFilePreviewError.fileOutsideWorkspace(file.path)
            }

            let sessionID = preferredSessionID ?? currentSessionID
            let urlString = file.absoluteString
            var snapshot = workspaceSnapshotsBySessionID[sessionID] ?? AppBrowserStateSnapshot()
            let tabID: UUID
            if let index = snapshot.tabs.firstIndex(where: {
                $0.initialURLString == urlString || $0.currentURLString == urlString
            }) {
                snapshot.tabs[index].localFileReadAccessPath = root.path
                snapshot.selectedTabID = snapshot.tabs[index].id
                tabID = snapshot.tabs[index].id
            } else {
                let tab = AppBrowserTabSnapshot(
                    initialURLString: urlString,
                    title: file.deletingPathExtension().lastPathComponent,
                    currentURLString: urlString,
                    localFileReadAccessPath: root.path
                )
                snapshot.tabs.append(tab)
                snapshot.selectedTabID = tab.id
                tabID = tab.id
            }
            errorMessage = nil
            saveWorkspaceSnapshot(snapshot, for: sessionID)
            if let webView = liveWebViewStore.webView(for: BrowserLiveWebViewKey(sessionID: sessionID, tabID: tabID)) {
                webView.loadFileURL(file, allowingReadAccessTo: root)
            }
            showWorkspace(for: sessionID)
        } catch {
            errorMessage = error.localizedDescription
            onEvent?(.operationFailed(error.localizedDescription))
        }
    }

    func showWorkspace() {
        showWorkspace(for: currentSessionID)
    }

    func showWorkspace(for sessionID: String) {
        workspaceSessionBinding.bindBrowserWorkspace(to: sessionID)
        workspaceSessionID = workspaceSessionBinding.boundSessionID
        isVisible = true
        if workspaceSnapshotsBySessionID[sessionID] == nil {
            targetURLString = BrowserBuiltInPage.blankURLString
        }
        onShowWorkspace(sessionID)
    }

    func returnFromWorkspace() {
        let context = sessionContextProvider()
        let target = workspaceSessionBinding.sessionIDForReturningFromBrowser(
            currentSelectedSessionID: context.selectedSessionID ?? context.activeSessionID
        )
        workspaceSessionID = target
        isVisible = false
        onReturnFromWorkspace(target)
    }

    func toggleWorkspaceVisibility() {
        isVisible ? returnFromWorkspace() : showWorkspace()
    }

    func restoreWorkspaceMode(isBrowser: Bool, sessionID: String) {
        isVisible = isBrowser
        workspaceSessionID = isBrowser ? sessionID : nil
        if isBrowser { workspaceSessionBinding.bindBrowserWorkspace(to: sessionID) }
    }

    func resetWorkspaceBinding() {
        workspaceSessionID = nil
        isVisible = false
        workspaceSessionBinding = BrowserWorkspaceSessionBinding()
    }

    // MARK: Assisted browser work

    func performBrowserControl(_ request: BrowserControlRequest) async throws -> BrowserControlResponse {
        guard !isShutdown else { throw BrowserAutomationRuntimeError.invalidRequest("Browser feature is shut down") }
        return try await automationRuntime.perform(request)
    }

    func shouldAttachAssistedTaskInBackground(_ task: BrowserAssistedTaskState) -> Bool {
        guard isVisible, workspaceSessionID == task.sessionID else { return true }
        return workspaceSnapshotsBySessionID[task.sessionID]?.selectedTabID != task.tabID
    }

    func assistedTaskWebView(for task: BrowserAssistedTaskState) -> WKWebView {
        automationRuntime.ensureWebView(
            sessionID: task.sessionID,
            tabID: task.tabID,
            initialURLString: task.urlString,
            onDidFinish: { [weak self] webView in self?.handleAssistedNavigationFinished(taskID: task.id, webView: webView) },
            onDidFail: { [weak self] webView, error in self?.handleAssistedNavigationFailure(taskID: task.id, webView: webView, error: error) }
        ).webView
    }

    private func handleAssistedNavigationFinished(taskID: UUID, webView: WKWebView) {
        guard let task = assistedTasksByID[taskID], task.status == .running else { return }
        let urlString = webView.url?.absoluteString ?? task.urlString
        let title = webView.title ?? task.title
        if let reason = BrowserAssistedInterventionDetector().interventionReason(urlString: urlString, title: title) {
            automationRuntime.clearAutomationCallbacks(sessionID: task.sessionID, tabID: task.tabID)
            revealAssistedTask(task.id, reason: reason)
            return
        }
        guard task.kind == .fetch else {
            automationRuntime.clearAutomationCallbacks(sessionID: task.sessionID, tabID: task.tabID)
            completeAssistedTask(task.id, message: "Completed in background")
            return
        }
        let script = """
        (() => JSON.stringify({
          title: document.title || '',
          url: location.href || '',
          text: document.body ? document.body.innerText.slice(0, 100001) : '',
          lang: document.documentElement ? (document.documentElement.lang || '') : ''
        }))()
        """
        webView.evaluateJavaScript(script) { [weak self] result, error in
            let json = result as? String ?? ""
            Task { @MainActor [weak self] in
                let payload = await Task.detached(priority: .utility) { () -> (String?, String?, String) in
                    guard let data = json.data(using: .utf8),
                          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    else { return (nil, nil, "") }
                    return (object["title"] as? String, object["url"] as? String, object["text"] as? String ?? "")
                }.value
                guard let self, let current = self.assistedTasksByID[taskID], current.status == .running else { return }
                self.automationRuntime.clearAutomationCallbacks(sessionID: current.sessionID, tabID: current.tabID)
                if let error {
                    self.failAssistedTask(taskID, message: error.localizedDescription)
                    return
                }
                let extractedTitle = payload.0?.trimmingCharacters(in: .whitespacesAndNewlines)
                let extractedURL = payload.1?.trimmingCharacters(in: .whitespacesAndNewlines)
                self.completeAssistedWebFetch(
                    taskID,
                    title: extractedTitle?.isEmpty == false ? extractedTitle! : title,
                    finalURLString: extractedURL?.isEmpty == false ? extractedURL! : urlString,
                    text: payload.2
                )
            }
        }
    }

    private func handleAssistedNavigationFailure(taskID: UUID, webView: WKWebView, error: Error) {
        guard let task = assistedTasksByID[taskID], task.status == .running else { return }
        let urlString = webView.url?.absoluteString ?? task.urlString
        let title = webView.title ?? task.title
        let message = error.localizedDescription
        automationRuntime.clearAutomationCallbacks(sessionID: task.sessionID, tabID: task.tabID)
        if let reason = BrowserAssistedInterventionDetector().interventionReason(urlString: urlString, title: title, errorMessage: message) {
            revealAssistedTask(task.id, reason: reason)
        } else if (error as NSError).code != NSURLErrorCancelled {
            failAssistedTask(task.id, message: message)
        }
    }

    @discardableResult
    func startAssistedSearch(urlString: String, title: String, revealImmediately: Bool = false) -> BrowserAssistedTaskState {
        let sessionID = currentSessionID
        let request = BrowserAssistedTaskRequest(
            kind: .search,
            sessionID: sessionID,
            urlString: urlString,
            title: title,
            visibility: revealImmediately ? .foreground : .background
        )
        let plan = BrowserAssistedTaskPlanner().start(
            request,
            in: workspaceSnapshotsBySessionID[sessionID] ?? AppBrowserStateSnapshot()
        )
        assistedTasksByID[plan.task.id] = plan.task
        targetURLString = urlString
        saveWorkspaceSnapshot(plan.snapshot, for: sessionID)
        if plan.shouldRevealBrowser { showWorkspace(for: sessionID) }
        return plan.task
    }

    func performAssistedWebFetch(_ request: BrowserAssistedWebFetchRequest) async -> BrowserAssistedWebFetchResult? {
        guard !isShutdown else { return nil }
        let task = startAssistedWebFetch(request)
        let timeout = max(3_000, min(request.timeoutMilliseconds, 60_000))
        return await withCheckedContinuation { continuation in
            assistedFetchContinuationsByTaskID[task.id] = continuation
            assistedFetchTimeoutTasksByID[task.id]?.cancel()
            assistedFetchTimeoutTasksByID[task.id] = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(timeout)) }
                catch { return }
                guard !Task.isCancelled, let self else { return }
                self.finishAssistedFetch(taskID: task.id, result: BrowserAssistedWebFetchResult(
                    status: .timedOut,
                    urlString: request.urlString,
                    finalURLString: request.urlString,
                    title: "",
                    contentText: "",
                    taskID: task.id.uuidString,
                    sessionID: task.sessionID,
                    tabID: task.tabID.uuidString,
                    errorMessage: "Connor WKWebView web_fetch(js) timed out after \(timeout)ms",
                    interventionReason: nil,
                    truncated: false,
                    originalCharacterCount: 0
                ), failureMessage: "Timed out")
            }
        }
    }

    func completeAssistedWebFetch(_ taskID: UUID, title: String, finalURLString: String, text: String) {
        guard let task = assistedTasksByID[taskID], let request = assistedFetchRequestsByTaskID[taskID] else { return }
        let originalCount = text.count
        let maxCharacters = 100_000
        let truncated = originalCount > maxCharacters
        let returnedText = truncated ? String(text.prefix(maxCharacters)) : text
        let suffix = truncated ? "\n\n[Content truncated by Connor web_fetch(js-wkwebview): original characters = \(originalCount), returned characters = \(maxCharacters)]" : ""
        let content: String
        if request.extractMode == "text" {
            content = returnedText + suffix
        } else {
            let heading = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Fetched Page" : title
            content = """
            # \(heading)
            **Source:** \(finalURLString.isEmpty ? request.urlString : finalURLString)
            **Render mode:** js-wkwebview

            ---

            \(returnedText)\(suffix)
            """
        }
        finishAssistedFetch(taskID: taskID, result: BrowserAssistedWebFetchResult(
            status: .fetched,
            urlString: request.urlString,
            finalURLString: finalURLString.isEmpty ? request.urlString : finalURLString,
            title: title,
            contentText: content,
            taskID: task.id.uuidString,
            sessionID: task.sessionID,
            tabID: task.tabID.uuidString,
            errorMessage: nil,
            interventionReason: nil,
            truncated: truncated,
            originalCharacterCount: originalCount
        ), completionMessage: "Fetched rendered page content")
    }

    func revealAssistedTask(_ taskID: UUID, reason: String) {
        guard let task = assistedTasksByID[taskID] else { return }
        let updated = BrowserAssistedTaskPlanner().requireUserIntervention(task, reason: reason)
        assistedTasksByID[taskID] = updated
        if let request = assistedFetchRequestsByTaskID[taskID] {
            finishAssistedFetch(taskID: taskID, result: BrowserAssistedWebFetchResult(
                status: .needsUserIntervention,
                urlString: request.urlString,
                finalURLString: updated.urlString,
                title: updated.title,
                contentText: "",
                taskID: updated.id.uuidString,
                sessionID: updated.sessionID,
                tabID: updated.tabID.uuidString,
                errorMessage: nil,
                interventionReason: reason,
                truncated: false,
                originalCharacterCount: 0
            ))
        }
        focusTab(updated.tabID, in: updated.sessionID, urlString: updated.urlString)
        showWorkspace(for: updated.sessionID)
    }

    func completeAssistedTask(_ taskID: UUID, message: String) {
        guard let task = assistedTasksByID[taskID] else { return }
        assistedTasksByID[taskID] = BrowserAssistedTaskPlanner().complete(task, message: message)
    }

    func failAssistedTask(_ taskID: UUID, message: String) {
        guard let task = assistedTasksByID[taskID] else { return }
        assistedTasksByID[taskID] = BrowserAssistedTaskPlanner().fail(task, message: message)
        if let request = assistedFetchRequestsByTaskID[taskID] {
            finishAssistedFetch(taskID: taskID, result: BrowserAssistedWebFetchResult(
                status: .failed,
                urlString: request.urlString,
                finalURLString: task.urlString,
                title: task.title,
                contentText: "",
                taskID: task.id.uuidString,
                sessionID: task.sessionID,
                tabID: task.tabID.uuidString,
                errorMessage: message,
                interventionReason: nil,
                truncated: false,
                originalCharacterCount: 0
            ))
        }
    }

    private func startAssistedWebFetch(_ request: BrowserAssistedWebFetchRequest) -> BrowserAssistedTaskState {
        let sessionID = currentSessionID
        let taskRequest = BrowserAssistedTaskRequest(
            kind: .fetch,
            sessionID: sessionID,
            urlString: request.urlString,
            title: "Fetch: \(request.urlString)",
            visibility: request.revealImmediately ? .foreground : .background
        )
        let plan = BrowserAssistedTaskPlanner().start(
            taskRequest,
            in: workspaceSnapshotsBySessionID[sessionID] ?? AppBrowserStateSnapshot()
        )
        assistedTasksByID[plan.task.id] = plan.task
        assistedFetchRequestsByTaskID[plan.task.id] = request
        targetURLString = request.urlString
        saveWorkspaceSnapshot(plan.snapshot, for: sessionID)
        if plan.shouldRevealBrowser { showWorkspace(for: sessionID) }
        return plan.task
    }

    private func finishAssistedFetch(
        taskID: UUID,
        result: BrowserAssistedWebFetchResult,
        completionMessage: String? = nil,
        failureMessage: String? = nil
    ) {
        guard let continuation = assistedFetchContinuationsByTaskID.removeValue(forKey: taskID) else { return }
        assistedFetchTimeoutTasksByID.removeValue(forKey: taskID)?.cancel()
        assistedFetchRequestsByTaskID.removeValue(forKey: taskID)
        if let task = assistedTasksByID[taskID] {
            if let completionMessage {
                assistedTasksByID[taskID] = BrowserAssistedTaskPlanner().complete(task, message: completionMessage)
            } else if let failureMessage {
                assistedTasksByID[taskID] = BrowserAssistedTaskPlanner().fail(task, message: result.errorMessage ?? failureMessage)
            }
        }
        continuation.resume(returning: result)
    }

    private func focusTab(_ tabID: UUID, in sessionID: String, urlString: String) {
        var snapshot = workspaceSnapshotsBySessionID[sessionID] ?? AppBrowserStateSnapshot()
        if snapshot.tabs.contains(where: { $0.id == tabID }) { snapshot.selectedTabID = tabID }
        else { snapshot = BrowserExternalOpenPlanner().open(urlString: urlString, in: snapshot) }
        targetURLString = urlString
        saveWorkspaceSnapshot(snapshot, for: sessionID)
    }

    // MARK: Bookmarks

    func loadBookmarks() {
        guard let bookmarkStore else { return }
        bookmarkRecords = bookmarkStore.loadBookmarks()
        applyBookmarkFilter()
    }

    func toggleBookmarksPanel() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isBookmarksPanelVisible.toggle()
            if isBookmarksPanelVisible { isHistoryPanelVisible = false; isDownloadsPanelVisible = false }
        }
        if isBookmarksPanelVisible { loadBookmarks() }
    }

    func addBookmark(url: String, title: String, groupName: String? = nil) {
        guard let bookmarkStore else { return }
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty, !trimmedURL.hasPrefix("connor://"), !trimmedURL.hasPrefix("about:"), !trimmedURL.hasPrefix("data:") else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedGroup = groupName?.trimmingCharacters(in: .whitespacesAndNewlines)
        bookmarkStore.upsertBookmark(BrowserBookmarkRecord(
            url: trimmedURL,
            title: trimmedTitle.isEmpty ? (URL(string: trimmedURL)?.host ?? trimmedURL) : trimmedTitle,
            groupName: resolvedGroup?.isEmpty == false ? resolvedGroup! : BrowserBookmarkRecord.defaultGroupName,
            createdAt: Date(),
            updatedAt: Date()
        ))
        loadBookmarks()
    }

    func toggleBookmark(url: String, title: String, groupName: String? = nil) {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return }
        if isBookmarked(url: trimmedURL) { bookmarkStore?.deleteBookmark(url: trimmedURL); loadBookmarks() }
        else { addBookmark(url: trimmedURL, title: title, groupName: groupName) }
    }

    func isBookmarked(url: String) -> Bool {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedURL.isEmpty && bookmarkRecords.contains { $0.url == trimmedURL }
    }

    func filterBookmarks(query: String, groupName: String? = nil) {
        selectedBookmarkGroupName = groupName
        applyBookmarkFilter(query: query)
    }

    func deleteBookmark(_ id: UUID) { bookmarkStore?.deleteBookmark(id: id); loadBookmarks() }
    func navigateToBookmark(_ bookmark: BrowserBookmarkRecord) { if let url = URL(string: bookmark.url) { openURL(url) } }

    private func applyBookmarkFilter(query: String = "") {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let group = selectedBookmarkGroupName?.trimmingCharacters(in: .whitespacesAndNewlines)
        filteredBookmarkRecords = bookmarkRecords.filter {
            (group?.isEmpty != false || $0.groupName == group)
                && (trimmed.isEmpty || $0.url.lowercased().contains(trimmed) || $0.title.lowercased().contains(trimmed) || $0.groupName.lowercased().contains(trimmed))
        }
    }

    // MARK: History

    func applyStartupHistory(_ result: StartupDomainResult<[BrowserHistoryRecord]>) {
        guard let history = result.value else { return }
        historyRecords = history
        applyHistoryFilter()
        enqueueHistoryIndexMutation(repairsIndex: true) { [weak self] in
            guard let self else { return }
            try await self.rebuildHistorySearchIndexIfNeeded()
        }
    }

    func loadHistory() {
        guard let historyStore else { return }
        let page = historyStore.loadHistoryPage(pageSize: Self.historyPageSize)
        historyRecords = page.records
        filteredHistoryRecords = page.records
        nextHistoryCursor = page.nextCursor
    }

    func recordHistory(url: String, title: String, sessionID: String) {
        guard let historyStore else { return }
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty, !trimmedURL.hasPrefix("connor://"), !trimmedURL.hasPrefix("about:"), !trimmedURL.hasPrefix("data:") else { return }
        let context = sessionContextProvider()
        let record = BrowserHistoryRecord(
            url: trimmedURL,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            sessionID: sessionID,
            sessionTitle: context.sessionTitlesByID[sessionID] ?? sessionID,
            contentFetchStatus: .pending
        )
        guard let appended = historyStore.appendRecord(record) else { return }
        loadHistory()
        indexHistoryRecord(appended)
        fetchContent(for: appended)
    }

    func toggleHistoryPanel() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isHistoryPanelVisible.toggle()
            if isHistoryPanelVisible { isBookmarksPanelVisible = false; isDownloadsPanelVisible = false }
        }
        if isHistoryPanelVisible { loadHistory() }
    }

    func filterHistory(query: String) {
        historySearchQuery = query
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let historyStore {
            let page = historyStore.loadHistoryPage(query: trimmed, pageSize: Self.historyPageSize)
            filteredHistoryRecords = page.records
            if trimmed.isEmpty { historyRecords = page.records }
            nextHistoryCursor = page.nextCursor
        }
        else if trimmed.isEmpty { filteredHistoryRecords = historyRecords }
        else { filteredHistoryRecords = historyRecords.filter { Self.historyRecord($0, matches: trimmed) } }
    }

    func loadMoreHistoryIfNeeded(currentRecordID: UUID) {
        guard currentRecordID == filteredHistoryRecords.last?.id,
              let cursor = nextHistoryCursor,
              let historyStore else { return }
        let page = historyStore.loadHistoryPage(
            cursor: cursor,
            query: historySearchQuery,
            pageSize: Self.historyPageSize
        )
        let existingIDs = Set(filteredHistoryRecords.map(\.id))
        let additions = page.records.filter { !existingIDs.contains($0.id) }
        filteredHistoryRecords.append(contentsOf: additions)
        if historySearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            historyRecords = filteredHistoryRecords
        }
        nextHistoryCursor = page.nextCursor
    }

    func deleteHistoryRecord(_ id: UUID) {
        historyStore?.deleteRecord(id: id)
        deleteHistorySearchRecord(id: id)
        loadHistory()
    }

    func clearHistory() {
        historyStore?.clearHistory()
        clearHistorySearchIndex()
        historyRecords = []
        filteredHistoryRecords = []
        historySearchQuery = ""
    }

    func navigateToHistoryRecord(_ record: BrowserHistoryRecord) {
        guard let url = URL(string: record.url) else { reportFailure("这条浏览历史没有可打开的 URL。"); return }
        if focusExistingTabIfPresent(urlString: record.url, preferredSessionID: record.sessionID) { reportSuccess(); return }
        onNavigateHistoryRecord(record, url)
    }

    func searchHistory(query: String, limit: Int) -> [BrowserHistoryRecord] {
        let values = historyStore?.searchHistory(query: query) ?? historyRecords.filter { Self.historyRecord($0, matches: query) }
        return Array(values.sorted { $0.visitedAt > $1.visitedAt }.prefix(limit))
    }

    func historyRecord(id: UUID) -> BrowserHistoryRecord? {
        historyRecords.first(where: { $0.id == id }) ?? historyStore?.record(id: id)
    }

    func fallbackSearchResults(query: String, now: Date, limit: Int) -> [NativeSearchResult] {
        searchHistory(query: query, limit: limit).map { record in
            Self.searchResult(for: record, now: now)
        }
    }

    func openHistorySearch(query: String) {
        historySearchQuery = query
        isHistoryPanelVisible = true
        showWorkspace()
        loadHistory()
        filterHistory(query: query)
    }

    func shutdown() {
        guard !isShutdown else { return }
        isShutdown = true
        automationRuntime.shutdown()
        for task in assistedFetchTimeoutTasksByID.values { task.cancel() }
        assistedFetchTimeoutTasksByID.removeAll()
        for task in historyContentFetchTasksByID.values { task.cancel() }
        historyContentFetchTasksByID.removeAll()
        historyIndexMutationTask?.cancel()
        historyIndexMutationTask = nil
        for (taskID, continuation) in assistedFetchContinuationsByTaskID {
            let task = assistedTasksByID[taskID]
            continuation.resume(returning: BrowserAssistedWebFetchResult(
                status: .failed,
                urlString: assistedFetchRequestsByTaskID[taskID]?.urlString ?? task?.urlString ?? "",
                finalURLString: task?.urlString ?? "",
                title: task?.title ?? "",
                contentText: "",
                taskID: taskID.uuidString,
                sessionID: task?.sessionID ?? "",
                tabID: task?.tabID.uuidString ?? "",
                errorMessage: "Browser feature shut down",
                interventionReason: nil,
                truncated: false,
                originalCharacterCount: 0
            ))
        }
        assistedFetchContinuationsByTaskID.removeAll()
        assistedFetchRequestsByTaskID.removeAll()
    }

    private func fetchContent(for record: BrowserHistoryRecord) {
        guard let historyStore, historyContentFetchTasksByID[record.id] == nil else { return }
        let recordID = record.id
        let task = Task.detached(priority: .utility) { [weak self] in
            let tool = NativeWebFetchTool()
            let arguments = AgentToolArguments(values: [
                "url": .string(record.url), "extract_mode": .string("markdown"),
                "render_mode": .string("auto"), "timeout_ms": .int(60_000)
            ])
            let context = AgentToolExecutionContext(
                runID: "browser-history-content-fetch-\(recordID.uuidString)", sessionID: record.sessionID,
                groupID: "browser-history", userPrompt: "Fetch browser history page content",
                toolCallID: UUID().uuidString, policyEngine: AgentPolicyEngine(permissionMode: .allowAll),
                approvedCapabilities: [.externalNetwork]
            )
            let updatedRecord: BrowserHistoryRecord?
            do {
                let result = try await tool.execute(arguments: arguments, context: context)
                guard !Task.isCancelled else { return }
                updatedRecord = historyStore.updateContent(id: recordID, markdown: result.contentText, status: .fetched)
            } catch {
                guard !Task.isCancelled else { return }
                updatedRecord = historyStore.updateContent(id: recordID, markdown: nil, status: .failed, error: String(describing: error))
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if let updatedRecord { self?.applyFetchedHistoryRecord(updatedRecord) }
                self?.historyContentFetchTasksByID[recordID] = nil
            }
        }
        historyContentFetchTasksByID[recordID] = task
    }

    private static func historyRecord(_ record: BrowserHistoryRecord, matches query: String) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty || record.url.lowercased().contains(normalized)
            || record.title.lowercased().contains(normalized)
            || record.sessionTitle.lowercased().contains(normalized)
            || (record.contentMarkdown?.lowercased().contains(normalized) ?? false)
    }

    private static func searchResult(for record: BrowserHistoryRecord, now: Date) -> NativeSearchResult {
        NativeSearchResult(
            id: "browser-history:\(record.id.uuidString)",
            sourceKind: .browserHistory,
            externalID: record.id.uuidString,
            sourceInstanceID: record.sessionID,
            title: record.title.isEmpty ? record.url : record.title,
            snippet: [record.sessionTitle, record.url].filter { !$0.isEmpty }.joined(separator: " · "),
            score: 1, lexicalScore: 1, freshnessScore: 0, fieldScore: 0,
            temporal: NativeSearchTemporalMetadata(primaryTime: record.visitedAt, primaryTimeKind: .updatedAt, updatedAt: record.visitedAt, indexedAt: now),
            resultTimeLabel: record.visitedAt.connorLocalFormatted(date: .medium, time: .short)
        )
    }

    private func applyFetchedHistoryRecord(_ record: BrowserHistoryRecord) {
        if let index = historyRecords.firstIndex(where: { $0.id == record.id }) {
            historyRecords[index] = record
        }
        applyHistoryFilter()
        indexHistoryRecord(record)
    }

    private func applyHistoryFilter() { filterHistory(query: historySearchQuery) }

    private func focusExistingTabIfPresent(urlString: String, preferredSessionID: String, planner: BrowserExternalOpenPlanner = BrowserExternalOpenPlanner()) -> Bool {
        for sessionID in workspaceSearchOrder(preferredSessionID: preferredSessionID) {
            guard var snapshot = workspaceSnapshotsBySessionID[sessionID],
                  let tabID = planner.matchingTabID(urlString: urlString, in: snapshot) else { continue }
            snapshot.updatedAt = Date(); snapshot.selectionPopover = nil; snapshot.selectedTabID = tabID
            targetURLString = urlString
            saveWorkspaceSnapshot(snapshot, for: sessionID)
            showWorkspace(for: sessionID)
            return true
        }
        return false
    }

    private func workspaceSearchOrder(preferredSessionID: String) -> [String] {
        let context = sessionContextProvider()
        var ordered: [String] = []
        func append(_ value: String?) { if let value, !value.isEmpty, !ordered.contains(value) { ordered.append(value) } }
        append(preferredSessionID); append(workspaceSessionID); append(context.activeSessionID)
        workspaceSnapshotsBySessionID.keys.sorted().forEach { append($0) }
        return ordered
    }

    private func recordWebViewEviction(key: BrowserLiveWebViewKey, webView: WKWebView, metadata: BrowserLiveWebViewStore.SnapshotMetadata) {
        var snapshot = workspaceSnapshotsBySessionID[key.sessionID] ?? AppBrowserStateSnapshot()
        guard let index = snapshot.tabs.firstIndex(where: { $0.id == key.tabID }) else { return }
        var tab = snapshot.tabs[index]
        tab.title = webView.title ?? tab.title; tab.currentURLString = webView.url?.absoluteString ?? tab.currentURLString
        tab.isLoading = false; tab.canGoBack = webView.canGoBack; tab.canGoForward = webView.canGoForward; tab.lastAccessedAt = Date()
        tab.scrollX = metadata.scrollX ?? tab.scrollX; tab.scrollY = metadata.scrollY ?? tab.scrollY
        tab.viewportWidth = metadata.viewportWidth ?? tab.viewportWidth; tab.viewportHeight = metadata.viewportHeight ?? tab.viewportHeight
        tab.contentFingerprint = metadata.contentFingerprint ?? tab.contentFingerprint
        tab.focusedElementHint = metadata.focusedElementHint ?? tab.focusedElementHint; tab.restorationStatus = .evicted
        snapshot.tabs[index] = tab
        saveWorkspaceSnapshot(snapshot, for: key.sessionID)
    }

    private func rebuildHistorySearchIndexIfNeeded() async throws {
        guard let nativeSourceSearchBackend else { return }
        guard let historyStore else {
            try await nativeSourceSearchBackend.rebuildSource(
                kind: .browserHistory,
                sourceInstanceID: nil,
                documents: historyRecords.map { NativeSourceSearchAdapters.browserHistoryDocument(from: $0) }
            )
            return
        }
        var documents: [NativeSearchDocument] = []
        var cursor: String?
        repeat {
            let page = historyStore.loadHistoryPage(cursor: cursor, pageSize: 200)
            documents.append(contentsOf: page.records.map { NativeSourceSearchAdapters.browserHistoryDocument(from: $0) })
            cursor = page.nextCursor
        } while cursor != nil
        try await nativeSourceSearchBackend.rebuildSource(
            kind: .browserHistory,
            sourceInstanceID: nil,
            documents: documents
        )
    }

    private func indexHistoryRecord(_ record: BrowserHistoryRecord) {
        guard let nativeSourceSearchBackend else { return }
        enqueueHistoryIndexMutation {
            try await nativeSourceSearchBackend.upsert([NativeSourceSearchAdapters.browserHistoryDocument(from: record)])
        }
    }

    private func deleteHistorySearchRecord(id: UUID) {
        guard let nativeSourceSearchBackend else { return }
        enqueueHistoryIndexMutation {
            try await nativeSourceSearchBackend.delete(documentIDs: ["browser-history:\(id.uuidString)"])
        }
    }

    private func clearHistorySearchIndex() {
        guard let nativeSourceSearchBackend else { return }
        enqueueHistoryIndexMutation {
            try await nativeSourceSearchBackend.deleteBySource(kind: .browserHistory, sourceInstanceID: nil)
        }
    }

    func synchronizeHistorySearchIndex() async {
        var repairAttempted = false
        while !Task.isCancelled {
            let generation = historyIndexMutationGeneration
            await historyIndexMutationTask?.value
            guard generation == historyIndexMutationGeneration else { continue }
            guard historyIndexRequiresRebuild, !repairAttempted else { return }
            repairAttempted = true
            enqueueHistoryIndexMutation(repairsIndex: true) { [weak self] in
                guard let self else { return }
                try await self.rebuildHistorySearchIndexIfNeeded()
            }
        }
    }

    private func enqueueHistoryIndexMutation(
        repairsIndex: Bool = false,
        _ operation: @escaping @MainActor () async throws -> Void
    ) {
        let precedingMutation = historyIndexMutationTask
        historyIndexMutationGeneration &+= 1
        historyIndexMutationTask = Task { [weak self] in
            await precedingMutation?.value
            guard !Task.isCancelled else { return }
            do {
                try await operation()
                if repairsIndex { self?.historyIndexRequiresRebuild = false }
            } catch {
                self?.historyIndexRequiresRebuild = true
            }
        }
    }

    private func reportSuccess() { errorMessage = nil; onEvent?(.operationSucceeded) }
    private func reportFailure(_ message: String) { errorMessage = message; onEvent?(.operationFailed(message)) }
}
