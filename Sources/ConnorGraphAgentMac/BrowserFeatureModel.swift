import AppKit
import Foundation
import Observation
import SwiftUI
import WebKit
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore

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
    @ObservationIgnored private var workspaceSessionBinding = BrowserWorkspaceSessionBinding()
    @ObservationIgnored private var isShutdown = false
    @ObservationIgnored private(set) var automationRuntime: BrowserAutomationRuntime!

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
    }

    func saveWorkspaceSnapshot(_ snapshot: AppBrowserStateSnapshot, for sessionID: String) {
        var normalized = snapshot
        normalized.updatedAt = Date()
        workspaceSnapshotsBySessionID[sessionID] = normalized
        persistWorkspaceSnapshot(normalized, sessionID)
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
        let timeout = max(3_000, min(request.timeoutMilliseconds, 720_000))
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
        historyRecords = historyStore.loadHistory()
        applyHistoryFilter()
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
        historyRecords = historyStore.loadHistory()
        applyHistoryFilter()
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
        if trimmed.isEmpty { filteredHistoryRecords = historyRecords }
        else if let historyStore { filteredHistoryRecords = historyStore.searchHistory(query: trimmed) }
        else { filteredHistoryRecords = historyRecords.filter { Self.historyRecord($0, matches: trimmed) } }
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
        let records = historyStore?.loadHistory() ?? historyRecords
        try await nativeSourceSearchBackend.rebuildSource(
            kind: .browserHistory,
            sourceInstanceID: nil,
            documents: records.map { NativeSourceSearchAdapters.browserHistoryDocument(from: $0) }
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
