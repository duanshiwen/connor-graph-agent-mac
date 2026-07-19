import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit
import ConnorGraphCore
import ConnorGraphAppSupport

typealias BrowserWorkspaceSnapshot = AppBrowserStateSnapshot
typealias BrowserTabSnapshot = AppBrowserTabSnapshot
typealias BrowserSelectionPopoverSnapshot = AppBrowserSelectionPopoverSnapshot
typealias BrowserSelectionThreadSnapshot = AppBrowserSelectionThreadSnapshot
typealias BrowserSelectionThreadMessageSnapshot = AppBrowserSelectionThreadMessageSnapshot
typealias BrowserSelectionRect = AppBrowserSelectionRect

@MainActor
struct BrowserWorkspaceChatActions {
    var selectedSessionID: String?
    var isSubmitting: Bool
    var defaultSearchEngine: DefaultSearchEngine
    var shortcutSettings: AgentRuntimeShortcutSettings
    var cancelActiveRun: () -> Void
    var appendToDraft: (String) -> Void
    var appendSessionRecord: (String, String?, String?, [String: String], String?) -> Void
    var submit: (String, String) async -> String?
    var currentErrorMessage: () -> String?
    var reportError: (String) -> Void
}

struct BrowserWorkspaceView: View {
    @Bindable var model: BrowserFeatureModel
    var chat: BrowserWorkspaceChatActions
    @State private var webViewsByTabID: [UUID: WKWebView] = [:]
    @State private var addressText: String = ""
    @State private var isAddressEditing = false
    @State private var focusAddressRequestID = UUID()
    @State private var questionText = ""
    @State private var browserKeyMonitor: Any?
    @State private var privateTabIDs: Set<UUID> = []
    @State private var processRecoveryAttempts: Set<UUID> = []
    @State private var isFindBarVisible = false
    @State private var findQuery = ""
    @State private var findResultText = ""
    @State private var readerHTMLByTabID: [UUID: String] = [:]
    @State private var formAssistant: BrowserFormAssistantState?
    @State private var formAssistantQuestion = ""
    @State private var formGenerationTask: Task<Void, Never>?
    @State private var formCandidateCache: [String: BrowserFormCandidateCacheEntry] = [:]
    @State private var formUndoReceipt: BrowserFormInsertionReceipt?

    var body: some View {
        VStack(spacing: 0) {
            tabBar
                .padding(.horizontal, 8)
                .padding(.top, 5)
                .padding(.bottom, 4)
                .background(Color(nsColor: .windowBackgroundColor))

            toolbar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(nsColor: .windowBackgroundColor))

            if isFindBarVisible { findBar }

            Divider()

            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    if activeTabs.isEmpty {
                        ContentUnavailableView(
                            "没有打开的网页",
                            systemImage: "safari",
                            description: Text("新建一个标签页开始浏览。")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ZStack {
                            ForEach(activeTabs) { tab in
                                EmbeddedWebView(
                                    webView: liveWebView(for: tab),
                                    initialURLString: tab.restoredURLString,
                                    onWebViewCreated: { webView in
                                        DispatchQueue.main.async { setWebView(webView, for: tab.id) }
                                    }
                                )
                                .id(tab.id)
                                .opacity(tab.id == activeSelectedTabID ? 1 : 0)
                                .allowsHitTesting(tab.id == activeSelectedTabID)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                    }

                    if activeTab?.navigationState.isLoading == true && activeTab?.navigationState.errorMessage == nil {
                        BrowserLoadingOverlay(message: "加载中…")
                            .position(x: geometry.size.width - 78, y: geometry.size.height - 34)
                    }

                    if let navigationErrorMessage = activeTab?.navigationState.errorMessage {
                        BrowserLoadingOverlay(message: navigationErrorMessage, systemImage: "exclamationmark.triangle")
                            .position(x: geometry.size.width - 120, y: geometry.size.height - 34)
                    }

                    if let popover = activeSession.selectionPopover {
                        let layout = selectionPopoverLayout(for: popover.rect, in: geometry.size)
                        BrowserSelectionPopover(
                            popover: popover,
                            thread: activeSession.thread(for: popover.threadID),
                            question: $questionText,
                            isSubmitting: chat.isSubmitting,
                            onAsk: {
                                sendSelectionQuestion(popover)
                            },
                            onSummarizePage: {
                                let summaryQuestion = BrowserLLMContextBuilder().makePageSummaryQuestion(selection: popover.context)
                                sendSelectionQuestion(popover, questionOverride: summaryQuestion)
                            },
                            onCancel: {
                                chat.cancelActiveRun()
                            },
                            onClose: { closeSelectionPopover(policy: .explicitClose) }
                        )
                        .frame(width: layout.width)
                        .frame(maxHeight: layout.maxHeight)
                        .position(layout.position)
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
                    }

                    if let assistant = formAssistant, assistant.tabID == activeSelectedTabID {
                        let layout = selectionPopoverLayout(for: assistant.field.rect, in: geometry.size)
                        BrowserFormAssistantPopover(
                            state: assistant,
                            question: $formAssistantQuestion,
                            tone: formToneBinding,
                            length: formLengthBinding,
                            language: formLanguageBinding,
                            siteEnabled: isFormAssistantSiteEnabled(assistant.field.pageURL),
                            canUndo: formUndoReceipt?.token == assistant.field.token,
                            onTask: generateFormCandidates,
                            onAsk: askFormAssistant,
                            onCancel: cancelFormGeneration,
                            onUpdateCandidate: updateFormCandidate,
                            onInsert: insertFormCandidate,
                            onUndo: undoFormInsertion,
                            onToggleSite: toggleFormAssistantForCurrentSite,
                            onClose: closeFormAssistant
                        )
                        .frame(width: layout.width)
                        .frame(maxHeight: layout.maxHeight)
                        .position(layout.position)
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
                    }
                }

                // Floating panels overlay on the right side
                if model.isBookmarksPanelVisible {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        BrowserBookmarksPanelView(
                            model: model,
                            currentPageURL: activeTabCanBeBookmarked ? activeTab?.displayURL : nil,
                            currentPageTitle: activeTabCanBeBookmarked ? activeTab?.displayTitle : nil
                        )
                        .transition(AnyTransition.move(edge: Edge.trailing).combined(with: AnyTransition.opacity))
                    }
                }

                if model.isHistoryPanelVisible {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        BrowserHistoryPanelView(model: model)
                            .transition(AnyTransition.move(edge: Edge.trailing).combined(with: AnyTransition.opacity))
                    }
                }

                if model.isDownloadsPanelVisible {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        BrowserDownloadsPanelView(
                            items: model.downloadItems,
                            onClose: model.closeDownloadsPanel,
                            onCancel: { id in
                                model.liveWebViewStore.cancelDownload(id)
                                model.markDownloadCancelled(id)
                            },
                            onOpen: openDownloadedFile,
                            onReveal: revealDownloadedFile,
                            onClearCompleted: model.clearCompletedDownloads
                        )
                        .transition(AnyTransition.move(edge: Edge.trailing).combined(with: AnyTransition.opacity))
                    }
                }
            }
        }
        .onAppear {
            ensureInitialTab()
            model.loadBookmarks()
            markVisibleTabInLiveStore()
            installBrowserKeyMonitorIfNeeded()
        }
        .onDisappear {
            cancelFormGeneration()
            captureRestorationSnapshotsForLiveTabs()
            pauseAllBrowserMedia()
            markAllBrowserTabsHidden()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                model.liveWebViewStore.enforceBudget()
            }
            removeBrowserKeyMonitor()
        }
        .onChange(of: model.targetURLString) { _, newValue in
            ensureInitialTab()
            navigate(to: newValue)
        }
        .onChange(of: chat.selectedSessionID) { _, _ in
            pauseAllBrowserMedia()
            ensureInitialTab()
            isAddressEditing = false
            syncAddressTextWithActiveTab()
            questionText = ""
        }
        .onChange(of: activeSelectedTabID) { _, _ in
            closeFormAssistant()
            isAddressEditing = false
            syncAddressTextWithActiveTab()
            markVisibleTabInLiveStore()
            questionText = ""
        }
    }

    private var activeSessionID: String {
        chat.selectedSessionID ?? "__fallback__"
    }

    private var activeSession: BrowserSessionState {
        let snapshot = model.workspaceSnapshotsBySessionID[activeSessionID]
        return BrowserSessionState(snapshot: snapshot, webViewsByTabID: webViewsByTabID, fallbackURLString: defaultURLString)
    }

    private var activeTabs: [BrowserTabState] {
        activeSession.tabs
    }

    private var activeSelectedTabID: BrowserTabState.ID? {
        activeSession.selectedTabID
    }

    private var activeTab: BrowserTabState? {
        guard let selectedID = activeSelectedTabID else { return nil }
        return activeTabs.first { $0.id == selectedID }
    }

    private var activeWebView: WKWebView? {
        activeTab?.webView
    }

    private var defaultURLString: String {
        model.targetURLString.isEmpty ? BrowserBuiltInPage.blankURLString : model.targetURLString
    }

    private var activeTabCanBeBookmarked: Bool {
        guard let url = activeTab?.displayURL.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty else { return false }
        return !url.hasPrefix("connor://") && !url.hasPrefix("about:") && !url.hasPrefix("data:")
    }

    private var activeURLIsBookmarked: Bool {
        guard activeTabCanBeBookmarked, let url = activeTab?.displayURL else { return false }
        return model.isBookmarked(url: url)
    }

    private func liveWebViewKey(for tabID: BrowserTabState.ID) -> BrowserLiveWebViewKey {
        BrowserLiveWebViewKey(sessionID: activeSessionID, tabID: tabID)
    }

    private func liveWebView(for tab: BrowserTabState) -> WKWebView {
        let isSelected = tab.id == activeSelectedTabID
        let lease = model.liveWebViewStore.leaseWebView(
            key: liveWebViewKey(for: tab.id),
            initialURLString: tab.restoredURLString,
            onNavigationStateChanged: { state in updateNavigationState(state, for: tab.id) },
            onOpenInNewTab: { url in openNewTab(urlString: url.absoluteString, select: true) },
            onPopupCreated: { webView, coordinator, url in
                adoptPopup(webView: webView, coordinator: coordinator, url: url, parentTabID: tab.id)
            },
            onCloseRequested: closeWebViewTab,
            onDownloadChanged: model.updateDownload,
            onMediaPermissionRequest: { origin, kind, completion in
                requestMediaPermission(
                    origin: origin,
                    kind: kind,
                    isPrivate: privateTabIDs.contains(tab.id),
                    completion: completion
                )
            },
            onContentProcessTerminated: { webView in recoverWebContentProcess(webView, tabID: tab.id) },
            onSelectionChanged: { selection in showSelectionPopover(selection, tabID: tab.id) },
            onEditableFieldChanged: { payload in handleEditableField(payload, tabID: tab.id) },
            onRestorationReady: { webView in restoreSnapshotIfNeeded(for: tab.id, in: webView) },
            isPrivate: privateTabIDs.contains(tab.id),
            isVisible: isSelected
        )
        if lease.isNewlyCreated {
            if let readerHTML = readerHTMLByTabID[tab.id] {
                lease.webView.loadHTMLString(readerHTML, baseURL: nil)
            } else {
                lease.webView.loadBrowserURLString(tab.restoredURLString)
            }
            DispatchQueue.main.async { setWebView(lease.webView, for: tab.id) }
        }
        return lease.webView
    }

    private func pauseAllBrowserMedia() {
        webViewsByTabID.values.forEach { webView in
            webView.pauseBrowserMediaPlayback()
        }
    }

    private func markVisibleTabInLiveStore() {
        guard let selectedID = activeSelectedTabID else { return }
        for tab in activeTabs {
            let key = liveWebViewKey(for: tab.id)
            if tab.id == selectedID {
                model.liveWebViewStore.markVisible(key)
            } else {
                model.liveWebViewStore.markHidden(key)
            }
        }
    }

    private func markAllBrowserTabsHidden() {
        for tab in activeTabs {
            model.liveWebViewStore.markHidden(liveWebViewKey(for: tab.id))
        }
    }

    private func prepareWebViewForTabClose(_ webView: WKWebView?) {
        guard let webView else { return }
        webView.pauseBrowserMediaPlayback()
        if webView.isLoading { webView.stopLoading() }
    }

    private var tabBar: some View {
        GeometryReader { geometry in
            let addButtonWidth: CGFloat = 30
            let interItemSpacing: CGFloat = 8
            let availableTabWidth = max(0, geometry.size.width - addButtonWidth - interItemSpacing)
            let layout = BrowserTabStripLayoutCalculator().layout(tabCount: activeTabs.count, availableWidth: Double(availableTabWidth))

            HStack(spacing: interItemSpacing) {
                ScrollView(.horizontal, showsIndicators: layout.requiresHorizontalScroll) {
                    HStack(spacing: 4) {
                        ForEach(activeTabs) { tab in
                            BrowserTabChip(
                                title: tab.displayTitle,
                                url: tab.displayURL,
                                width: CGFloat(layout.tabWidth),
                                isSelected: tab.id == activeSelectedTabID,
                                isLoading: tab.navigationState.isLoading,
                                isPrivate: privateTabIDs.contains(tab.id),
                                onSelect: { selectTab(tab.id) },
                                onClose: { closeTab(tab.id) }
                            )
                        }
                    }
                }
                .frame(width: availableTabWidth, alignment: .leading)

                Button(action: { openNewTab(urlString: model.targetURLString, select: true) }) {
                    Image(systemName: "plus")
                        .font(BrowserFloatingTypography.toolbarIcon)
                        .foregroundStyle(.secondary)
                        .frame(width: addButtonWidth, height: 26)
                }
                .buttonStyle(.plain)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.secondary.opacity(0.08), lineWidth: 1)
                )
                .help("新建标签页")
            }
        }
        .frame(height: 30)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button(action: { activeWebView?.goBack() }) {
                BrowserToolbarIconButtonLabel(systemImage: "chevron.left")
            }
            .buttonStyle(.plain)
            .disabled(activeTab?.navigationState.canGoBack != true)
            .opacity(activeTab?.navigationState.canGoBack == true ? 1 : 0.48)
            .help("后退")

            Button(action: { activeWebView?.goForward() }) {
                BrowserToolbarIconButtonLabel(systemImage: "chevron.right")
            }
            .buttonStyle(.plain)
            .disabled(activeTab?.navigationState.canGoForward != true)
            .opacity(activeTab?.navigationState.canGoForward == true ? 1 : 0.48)
            .help("前进")

            Button(action: reloadOrStopActiveWebView) {
                BrowserToolbarIconButtonLabel(systemImage: activeTab?.navigationState.isLoading == true ? "xmark" : "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .disabled(activeWebView == nil)
            .opacity(activeWebView == nil ? 0.48 : 1)
            .help(activeTab?.navigationState.isLoading == true ? "停止加载" : "刷新")

            siteSecurityMenu

            BrowserAddressTextField(
                text: $addressText,
                placeholder: "输入网址或搜索词，按 Return 打开",
                focusRequestID: focusAddressRequestID,
                onEditingChanged: { isAddressEditing = $0 },
                onSubmit: navigateFromAddressBar
            )
            .frame(height: 28)

            Button(action: { model.toggleBookmarksPanel() }) {
                BrowserToolbarIconButtonLabel(
                    systemImage: activeURLIsBookmarked ? "star.fill" : "star",
                    isActive: model.isBookmarksPanelVisible || activeURLIsBookmarked,
                    iconFont: .system(size: 16, weight: .semibold)
                )
            }
            .buttonStyle(.plain)
            .help(activeURLIsBookmarked ? "当前页已收藏，打开收藏夹" : "打开收藏夹")
            .accessibilityLabel("收藏夹")

            Button(action: { model.toggleHistoryPanel() }) {
                BrowserToolbarIconButtonLabel(
                    systemImage: model.isHistoryPanelVisible ? "clock.arrow.circlepath" : "clock",
                    isActive: model.isHistoryPanelVisible,
                    iconFont: .system(size: 16, weight: .semibold)
                )
            }
            .buttonStyle(.plain)
            .help("浏览历史")
            .accessibilityLabel("历史")

            Button(action: { model.toggleDownloadsPanel() }) {
                BrowserToolbarIconButtonLabel(
                    systemImage: activeDownloadCount > 0 ? "arrow.down.circle.fill" : "arrow.down.circle",
                    isActive: model.isDownloadsPanelVisible || activeDownloadCount > 0,
                    iconFont: .system(size: 16, weight: .semibold)
                )
            }
            .buttonStyle(.plain)
            .help(activeDownloadCount > 0 ? "正在下载 \(activeDownloadCount) 个项目" : "下载")
            .accessibilityLabel("下载")

            browserToolsMenu

            Button(action: showPageQuestionPopover) {
                BrowserAskAIButtonLabel()
            }
            .buttonStyle(.plain)
            .disabled(activeWebView == nil || activeTab?.navigationState.isLoading == true)
            .opacity(activeWebView == nil || activeTab?.navigationState.isLoading == true ? 0.48 : 1)
            .help("基于当前网页全文提问")

            Button(action: { model.returnFromWorkspace() }) {
                SidebarActionButtonLabel(
                    title: "返回对话",
                    systemImage: "bubble.left.and.bubble.right",
                    fillsWidth: false,
                    titleFont: BrowserFloatingTypography.askButton,
                    iconFont: BrowserFloatingTypography.askButtonIcon
                )
            }
            .buttonStyle(SidebarActionButtonStyle())
            .help("关闭网页工作区，返回关联会话的对话时间线")
        }
    }

    private var activeDownloadCount: Int {
        model.downloadItems.filter { $0.status == .preparing || $0.status == .downloading }.count
    }

    private var activeOrigin: String? {
        guard let url = activeWebView?.url, let host = url.host else { return nil }
        let port = url.port.map { ":\($0)" } ?? ""
        return "\(url.scheme ?? "https")://\(host)\(port)"
    }

    private var siteSecurityMenu: some View {
        Menu {
            if let url = activeWebView?.url, let host = url.host {
                Text(host)
                Text(url.scheme == "https" ? "连接已加密" : "连接未加密")
                Divider()
                if let origin = activeOrigin {
                    ForEach(BrowserSitePermissionKind.allCases) { kind in
                        let decision = model.permissionDecision(for: origin, kind: kind)
                        Label(
                            "\(kind.displayName)：\(permissionLabel(decision))",
                            systemImage: kind.systemImage
                        )
                    }
                    Button("重置此网站权限") { model.resetPermissions(for: origin) }
                }
                Button("清除此网站数据") { clearWebsiteData(host: host) }
            } else {
                Text("当前页面没有站点信息")
            }
        } label: {
            BrowserToolbarIconButtonLabel(
                systemImage: activeWebView?.url?.scheme == "https" ? "lock.fill" : "exclamationmark.triangle",
                isActive: activeWebView?.url?.scheme == "https",
                iconFont: .system(size: 13, weight: .semibold)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("网站信息与权限")
        .accessibilityLabel("网站信息与权限")
    }

    private var browserToolsMenu: some View {
        Menu {
            Button("在页面中查找…", systemImage: "magnifyingglass") { showFindBar() }
            Button("新建私密标签页", systemImage: "hand.raised.fill") { openPrivateTab() }
            Divider()
            Menu("页面缩放") {
                Button("放大", systemImage: "plus.magnifyingglass") { adjustPageZoom(by: 0.1) }
                Button("缩小", systemImage: "minus.magnifyingglass") { adjustPageZoom(by: -0.1) }
                Button("实际大小", systemImage: "1.magnifyingglass") { setPageZoom(1) }
            }
            Button("阅读模式", systemImage: "doc.plaintext") { openReaderMode() }
            Divider()
            Button("打印…", systemImage: "printer") { printCurrentPage() }
            Button("导出为 PDF…", systemImage: "doc.richtext") { exportCurrentPagePDF() }
            Divider()
            Button("复制网址", systemImage: "doc.on.doc") { copyCurrentURL() }
            Button("分享…", systemImage: "square.and.arrow.up") { shareCurrentURL() }
            Button("在默认浏览器中打开", systemImage: "safari") { openCurrentURLInDefaultBrowser() }
            Divider()
            Button("清除全部网站数据…", systemImage: "trash") { confirmClearAllWebsiteData() }
            Label("Web 检查器已启用", systemImage: "hammer")
        } label: {
            BrowserToolbarIconButtonLabel(systemImage: "ellipsis.circle", iconFont: .system(size: 16, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("更多浏览工具")
        .accessibilityLabel("更多浏览工具")
    }

    private var findBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(BrowserFloatingTypography.hint)
                .foregroundStyle(.tertiary)
            TextField("在当前网页中查找", text: $findQuery)
                .textFieldStyle(.plain)
                .font(BrowserFloatingTypography.input)
                .onSubmit { findInPage(forward: true) }
            Text(findResultText)
                .font(BrowserFloatingTypography.hint)
                .foregroundStyle(.secondary)
                .frame(minWidth: 70, alignment: .trailing)
            Button(action: { findInPage(forward: false) }) {
                Image(systemName: "chevron.up").frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help("上一个匹配项")
            Button(action: { findInPage(forward: true) }) {
                Image(systemName: "chevron.down").frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help("下一个匹配项")
            Button(action: closeFindBar) {
                Image(systemName: "xmark").frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help("关闭查找")
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
    }

    private func permissionLabel(_ decision: BrowserSitePermissionDecision?) -> String {
        switch decision { case .allow: "允许"; case .deny: "拒绝"; case nil: "询问" }
    }

    private func showFindBar() { isFindBarVisible = true }
    private func closeFindBar() { isFindBarVisible = false; findResultText = "" }

    private func findInPage(forward: Bool) {
        guard let webView = activeWebView else { return }
        let query = findQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { findResultText = ""; return }
        let configuration = WKFindConfiguration()
        configuration.backwards = !forward
        configuration.wraps = true
        webView.find(query, configuration: configuration) { result in
            findResultText = result.matchFound ? "已找到" : "无匹配"
        }
    }

    private func adjustPageZoom(by delta: CGFloat) { setPageZoom((activeWebView?.pageZoom ?? 1) + delta) }
    private func setPageZoom(_ value: CGFloat) { activeWebView?.pageZoom = min(max(value, 0.5), 3) }

    private func printCurrentPage() {
        guard let webView = activeWebView else { return }
        webView.printOperation(with: NSPrintInfo.shared).run()
    }

    private func exportCurrentPagePDF() {
        guard let webView = activeWebView else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(activeTab?.displayTitle ?? "网页").pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        webView.createPDF(configuration: WKPDFConfiguration()) { result in
            switch result {
            case .success(let data): try? data.write(to: url, options: .atomic)
            case .failure(let error): chat.reportError("导出 PDF 失败：\(error.localizedDescription)")
            }
        }
    }

    private func copyCurrentURL() {
        guard let value = activeWebView?.url?.absoluteString else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func shareCurrentURL() {
        guard let webView = activeWebView, let url = webView.url else { return }
        NSSharingServicePicker(items: [url]).show(relativeTo: webView.bounds, of: webView, preferredEdge: .minY)
    }

    private func openCurrentURLInDefaultBrowser() {
        guard let url = activeWebView?.url else { return }
        NSWorkspace.shared.open(url)
    }

    private func openPrivateTab() {
        let id = UUID()
        privateTabIDs.insert(id)
        openNewTab(urlString: BrowserBuiltInPage.blankURLString, select: true, tabID: id)
    }

    private func clearWebsiteData(host: String) {
        let store = activeWebView?.configuration.websiteDataStore ?? .default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        store.fetchDataRecords(ofTypes: types) { records in
            let matching = records.filter { $0.displayName == host || host.hasSuffix(".\($0.displayName)") }
            store.removeData(ofTypes: types, for: matching) { activeWebView?.reload() }
        }
    }

    private func confirmClearAllWebsiteData() {
        let alert = NSAlert()
        alert.messageText = "清除全部网站数据？"
        alert.informativeText = "将删除 Cookie、缓存和本地存储，并可能退出已登录的网站。浏览历史和书签不会删除。"
        alert.addButton(withTitle: "清除")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) { activeWebView?.reload() }
    }

    private func openReaderMode() {
        guard let webView = activeWebView else { return }
        let sourceWasPrivate = activeSelectedTabID.map(privateTabIDs.contains) ?? false
        let script = """
        (() => JSON.stringify({
          title: document.title || '',
          url: location.href || '',
          text: ((document.querySelector('article') || document.querySelector('main') || document.body)?.innerText || '').trim()
        }))()
        """
        webView.evaluateJavaScript(script) { result, error in
            guard error == nil, let json = result as? String, let data = json.data(using: .utf8),
                  let payload = try? JSONDecoder().decode(BrowserReaderPayload.self, from: data), !payload.text.isEmpty
            else { chat.reportError("当前网页没有可用于阅读模式的正文。"); return }
            let tabID = UUID()
            readerHTMLByTabID[tabID] = BrowserReaderPage.html(payload)
            if sourceWasPrivate { privateTabIDs.insert(tabID) }
            openNewTab(urlString: BrowserBuiltInPage.blankURLString, select: true, tabID: tabID)
        }
    }

    private func requestMediaPermission(
        origin: String,
        kind: BrowserSitePermissionKind,
        isPrivate: Bool,
        completion: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
    ) {
        if !isPrivate, let decision = model.permissionDecision(for: origin, kind: kind) {
            completion(decision == .allow ? .grant : .deny)
            return
        }
        let alert = NSAlert()
        alert.messageText = "网站请求使用\(kind.displayName)"
        alert.informativeText = "\(origin) 希望访问你的\(kind.displayName)。你可以稍后从地址栏左侧的网站信息菜单重置此权限。"
        alert.addButton(withTitle: "允许")
        alert.addButton(withTitle: "拒绝")
        let response = alert.runModal()
        let decision: BrowserSitePermissionDecision = response == .alertFirstButtonReturn ? .allow : .deny
        if !isPrivate { model.setPermissionDecision(decision, for: origin, kind: kind) }
        completion(decision == .allow ? .grant : .deny)
    }

    private func openDownloadedFile(_ item: BrowserDownloadItem) {
        guard let url = item.destinationURL else { return }
        NSWorkspace.shared.open(url)
    }

    private func revealDownloadedFile(_ item: BrowserDownloadItem) {
        guard let url = item.destinationURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func ensureInitialTab() {
        if model.workspaceSnapshotsBySessionID[activeSessionID] == nil {
            let session = BrowserSessionState.default(urlString: defaultURLString)
            model.saveWorkspaceSnapshot(session.snapshot, for: activeSessionID)
            addressText = defaultURLString
        }
    }

    private func mutateActiveSession(_ update: (inout BrowserSessionState) -> Void) {
        var session = activeSession
        update(&session)
        model.saveWorkspaceSnapshot(session.snapshot, for: activeSessionID)
        webViewsByTabID = session.webViewsByTabID
    }

    @discardableResult
    private func openNewTab(urlString: String, select: Bool, tabID: UUID = UUID()) -> UUID {
        let normalized = normalizedURLString(from: urlString) ?? BrowserBuiltInPage.blankURLString
        let tab = BrowserTabState(id: tabID, initialURLString: normalized)
        mutateActiveSession { session in
            session.tabs.append(tab)
            if select { session.selectedTabID = tab.id }
        }
        if select {
            isAddressEditing = false
            addressText = normalized
        }
        return tab.id
    }

    private func adoptPopup(
        webView: WKWebView,
        coordinator: BrowserLiveWebViewStore.WebViewCoordinator,
        url: URL?,
        parentTabID: UUID
    ) {
        let tabID = UUID()
        var tab = BrowserTabState(id: tabID, initialURLString: url?.absoluteString ?? "about:blank")
        tab.webView = webView
        if privateTabIDs.contains(parentTabID) { privateTabIDs.insert(tabID) }
        coordinator.onNavigationStateChanged = { state in updateNavigationState(state, for: tabID) }
        coordinator.onSelectionChanged = { selection in showSelectionPopover(selection, tabID: tabID) }
        coordinator.onEditableFieldChanged = { payload in handleEditableField(payload, tabID: tabID) }
        coordinator.onRestorationReady = { view in restoreSnapshotIfNeeded(for: tabID, in: view) }
        coordinator.onContentProcessTerminated = { view in recoverWebContentProcess(view, tabID: tabID) }
        mutateActiveSession { session in
            session.tabs.append(tab)
            session.selectedTabID = tabID
            session.webViewsByTabID[tabID] = webView
        }
        webViewsByTabID[tabID] = webView
        model.liveWebViewStore.adoptPopup(
            key: liveWebViewKey(for: tabID),
            webView: webView,
            coordinator: coordinator,
            isVisible: true
        )
    }

    private func closeWebViewTab(_ webView: WKWebView) {
        guard let tabID = webViewsByTabID.first(where: { $0.value === webView })?.key else { return }
        closeTab(tabID)
    }

    private func recoverWebContentProcess(_ webView: WKWebView, tabID: UUID) {
        if processRecoveryAttempts.insert(tabID).inserted {
            updateNavigationState(
                WebNavigationState(
                    canGoBack: webView.canGoBack,
                    canGoForward: webView.canGoForward,
                    title: webView.title ?? "",
                    url: webView.url?.absoluteString ?? "",
                    isLoading: true,
                    errorMessage: nil
                ),
                for: tabID
            )
            webView.reload()
        } else {
            updateNavigationState(
                WebNavigationState(
                    canGoBack: false,
                    canGoForward: false,
                    title: webView.title ?? "",
                    url: webView.url?.absoluteString ?? "",
                    isLoading: false,
                    errorMessage: "网页进程意外终止，请手动刷新。"
                ),
                for: tabID
            )
        }
    }

    private func selectTab(_ id: BrowserTabState.ID) {
        closeFormAssistant()
        mutateActiveSession { session in
            session.selectedTabID = id
            session.selectionPopover = nil
        }
        isAddressEditing = false
        syncAddressTextWithActiveTab()
    }

    private func closeTab(_ id: BrowserTabState.ID) {
        if formAssistant?.tabID == id { closeFormAssistant() }
        var shouldReturnToConversation = false
        let wasPrivate = privateTabIDs.contains(id)
        let closingWebView = webViewsByTabID[id]
        prepareWebViewForTabClose(closingWebView)
        model.liveWebViewStore.remove(liveWebViewKey(for: id))
        privateTabIDs.remove(id)
        readerHTMLByTabID[id] = nil
        if wasPrivate, privateTabIDs.isEmpty { model.liveWebViewStore.clearPrivateWebsiteData() }
        processRecoveryAttempts.remove(id)
        mutateActiveSession { session in
            guard let index = session.tabs.firstIndex(where: { $0.id == id }) else { return }
            let wasSelected = session.selectedTabID == id
            session.tabs.remove(at: index)
            session.webViewsByTabID[id] = nil
            session.selectionPopover = session.selectionPopover?.tabID == id ? nil : session.selectionPopover
            webViewsByTabID[id] = nil

            if session.tabs.isEmpty {
                session.selectedTabID = nil
                shouldReturnToConversation = true
                return
            }

            if wasSelected {
                let nextIndex = min(index, session.tabs.count - 1)
                session.selectedTabID = session.tabs[nextIndex].id
            }
        }

        if shouldReturnToConversation {
            model.returnFromWorkspace()
        } else {
            isAddressEditing = false
            syncAddressTextWithActiveTab()
        }
    }

    private func setWebView(_ webView: WKWebView, for tabID: BrowserTabState.ID) {
        if webViewsByTabID[tabID] === webView { return }
        webViewsByTabID[tabID] = webView

        if activeSelectedTabID == nil {
            mutateActiveSession { session in
                guard session.tabs.contains(where: { $0.id == tabID }) else { return }
                session.selectedTabID = tabID
            }
        }
    }

    private func updateNavigationState(_ state: WebNavigationState, for tabID: BrowserTabState.ID) {
        if state.isLoading, formAssistant?.tabID == tabID { closeFormAssistant() }
        if !state.isLoading, state.errorMessage == nil { processRecoveryAttempts.remove(tabID) }
        var displayURL = state.url
        mutateActiveSession { session in
            guard let index = session.tabs.firstIndex(where: { $0.id == tabID }) else { return }
            var normalizedState = state
            if normalizedState.url == "about:blank", session.tabs[index].initialURLString == BrowserBuiltInPage.blankURLString {
                normalizedState.url = BrowserBuiltInPage.blankURLString
            }
            displayURL = normalizedState.url
            session.tabs[index].navigationState = normalizedState
            session.tabs[index].lastAccessedAt = Date()
            session.tabs[index].restorationStatus = .live
        }
        if tabID == activeSelectedTabID, !displayURL.isEmpty, !isAddressEditing { addressText = displayURL }

        // Record browser history when page finishes loading
        if !privateTabIDs.contains(tabID), !state.isLoading, !state.url.isEmpty, !state.url.hasPrefix("connor://"), !state.url.hasPrefix("about:"), !state.url.hasPrefix("data:") {
            model.recordHistory(
                url: state.url,
                title: state.title,
                sessionID: activeSessionID
            )
        }
    }

    private func syncAddressTextWithActiveTab() {
        guard !isAddressEditing, let activeTab else { return }
        addressText = activeTab.navigationState.url.isEmpty ? activeTab.initialURLString : activeTab.navigationState.url
    }

    private func reloadOrStopActiveWebView() {
        guard let webView = activeWebView else { return }
        if activeTab?.navigationState.isLoading == true || webView.isLoading {
            webView.stopLoading()
            if let selectedTabID = activeSelectedTabID {
                updateNavigationState(
                    WebNavigationState(
                        canGoBack: webView.canGoBack,
                        canGoForward: webView.canGoForward,
                        title: webView.title ?? activeTab?.navigationState.title ?? "",
                        url: webView.url?.absoluteString ?? activeTab?.navigationState.url ?? "",
                        isLoading: false,
                        errorMessage: nil
                    ),
                    for: selectedTabID
                )
            }
        } else {
            webView.reload()
        }
    }

    private func navigateFromAddressBar() {
        isAddressEditing = false
        let trimmed = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let urlString = normalizedURLString(from: trimmed) else { return }
        model.targetURLString = urlString
        navigate(to: urlString)
    }

    private func navigate(to urlString: String) {
        guard let normalized = normalizedURLString(from: urlString) else { return }
        ensureInitialTab()
        addressText = normalized
        guard let selectedTabID = activeSelectedTabID else { return }
        mutateActiveSession { session in
            guard let index = session.tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
            session.tabs[index].initialURLString = normalized
            if session.tabs[index].webView?.url?.absoluteString != normalized {
                session.tabs[index].webView?.loadBrowserURLString(normalized)
            }
        }
    }

    private func normalizedURLString(from value: String) -> String? {
        BrowserNavigationURLResolver.normalizedURLString(from: value, defaultSearchEngine: chat.defaultSearchEngine)
    }

    private func captureRestorationSnapshotsForLiveTabs() {
        for tab in activeTabs {
            guard let webView = webViewsByTabID[tab.id] else { continue }
            webView.evaluateJavaScript(Self.pageRestorationSnapshotScript) { result, _ in
                guard let json = result as? String,
                      let data = json.data(using: .utf8),
                      let snapshot = try? JSONDecoder().decode(BrowserPageRestorationSnapshot.self, from: data)
                else { return }
                DispatchQueue.main.async {
                    mutateActiveSession { session in
                        guard let index = session.tabs.firstIndex(where: { $0.id == tab.id }) else { return }
                        session.tabs[index].scrollX = snapshot.scrollX
                        session.tabs[index].scrollY = snapshot.scrollY
                        session.tabs[index].viewportWidth = snapshot.viewportWidth
                        session.tabs[index].viewportHeight = snapshot.viewportHeight
                        session.tabs[index].contentFingerprint = snapshot.contentFingerprint
                        session.tabs[index].focusedElementHint = snapshot.focusedElementHint
                        session.tabs[index].lastAccessedAt = Date()
                    }
                }
            }
        }
    }

    private func restoreSnapshotIfNeeded(for tabID: BrowserTabState.ID, in webView: WKWebView) {
        guard let tab = activeTabs.first(where: { $0.id == tabID }),
              tab.restorationStatus == .evicted || tab.restorationStatus == .restoreFailed,
              let scrollY = tab.scrollY
        else { return }
        let scrollX = tab.scrollX ?? 0
        let script = "window.scrollTo(\(scrollX), \(scrollY));"
        webView.evaluateJavaScript(script) { _, error in
            DispatchQueue.main.async {
                mutateActiveSession { session in
                    guard let index = session.tabs.firstIndex(where: { $0.id == tabID }) else { return }
                    session.tabs[index].restorationStatus = error == nil ? .restoredFromSnapshot : .restoreFailed
                }
            }
        }
    }

    private var formToneBinding: Binding<BrowserFormAssistantTone> {
        Binding(
            get: { formAssistant?.tone ?? .natural },
            set: { value in
                guard var state = formAssistant else { return }
                state.tone = value
                formAssistant = state
            }
        )
    }

    private var formLengthBinding: Binding<BrowserFormAssistantLength> {
        Binding(
            get: { formAssistant?.length ?? .medium },
            set: { value in
                guard var state = formAssistant else { return }
                state.length = value
                formAssistant = state
            }
        )
    }

    private var formLanguageBinding: Binding<BrowserFormAssistantLanguage> {
        Binding(
            get: { formAssistant?.language ?? .automatic },
            set: { value in
                guard var state = formAssistant else { return }
                state.language = value
                formAssistant = state
            }
        )
    }

    private func handleEditableField(_ payload: BrowserEditableFieldPayload, tabID: BrowserTabState.ID) {
        guard tabID == activeSelectedTabID else { return }
        switch payload.event {
        case .dismissed:
            if formAssistant?.field.token == payload.token { closeFormAssistant() }
        case .moved:
            guard var state = formAssistant, state.field.token == payload.token else { return }
            state.field.rect = payload.rect
            formAssistant = state
        case .focused:
            cancelFormGeneration()
            formUndoReceipt = formUndoReceipt?.token == payload.token ? formUndoReceipt : nil
            let semantic = BrowserFormAssistantClassifier.semantic(for: payload)
            let tasks = BrowserFormAssistantClassifier.quickTasks(for: semantic, hasText: !payload.currentValue.isEmpty)
            formAssistant = BrowserFormAssistantState(
                tabID: tabID,
                field: payload,
                semantic: semantic,
                quickTasks: tasks
            )
            formAssistantQuestion = ""
            closeSelectionPopover(policy: .explicitClose)
        }
    }

    private func closeFormAssistant() {
        cancelFormGeneration()
        formAssistant = nil
        formAssistantQuestion = ""
    }

    private func isFormAssistantSiteEnabled(_ urlString: String) -> Bool {
        guard let host = URL(string: urlString)?.host else { return true }
        return model.isFormAssistantEnabled(for: host)
    }

    private func toggleFormAssistantForCurrentSite() {
        guard let state = formAssistant, let host = URL(string: state.field.pageURL)?.host else { return }
        model.setFormAssistantEnabled(!model.isFormAssistantEnabled(for: host), for: host)
        if !model.isFormAssistantEnabled(for: host) { cancelFormGeneration() }
    }

    private func generateFormCandidates(_ task: BrowserFormQuickTask) {
        requestFormCandidates(task.prompt, displayRequest: task.title)
    }

    private func askFormAssistant() {
        let request = formAssistantQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { return }
        requestFormCandidates(request, displayRequest: request)
    }

    private func requestFormCandidates(_ request: String, displayRequest: String) {
        guard var state = formAssistant,
              !state.field.sensitive,
              isFormAssistantSiteEnabled(state.field.pageURL),
              !state.isGenerating
        else { return }

        let cacheKey = formCandidateCacheKey(state: state, request: request)
        if let cached = formCandidateCache[cacheKey], Date().timeIntervalSince(cached.createdAt) < 300 {
            state.candidates = cached.candidates
            state.errorMessage = nil
            state.messages.append(.init(role: .user, text: displayRequest))
            state.messages.append(.init(role: .assistant, text: "已使用最近生成的候选。"))
            formAssistant = state
            formAssistantQuestion = ""
            return
        }

        state.isGenerating = true
        state.errorMessage = nil
        state.messages.append(.init(role: .user, text: displayRequest))
        formAssistant = state
        formAssistantQuestion = ""
        let token = state.field.token
        let tabID = state.tabID

        chat.appendSessionRecord(
            "browser.form-assistant.generate",
            state.field.pageTitle.isEmpty ? "网页输入助手" : state.field.pageTitle,
            displayRequest,
            [
                "pageHost": URL(string: state.field.pageURL)?.host ?? "",
                "fieldSemantic": state.semantic.rawValue,
                "fieldLabel": String(state.field.label.prefix(200)),
                "tabID": tabID.uuidString
            ],
            activeSessionID
        )

        formGenerationTask?.cancel()
        formGenerationTask = Task {
            let prompt = BrowserFormAssistantPromptBuilder.prompt(state: state, request: request)
            guard !Task.isCancelled else { return }
            let displayPrompt = "网页输入助手\n字段：\(state.semantic.displayName)\n要求：\(displayRequest)"
            let answer = await chat.submit(prompt, displayPrompt)
            guard !Task.isCancelled else { return }
            let candidates = await Task.detached(priority: .userInitiated) {
                BrowserFormCandidateParser.parse(answer ?? "")
            }.value
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard var current = formAssistant,
                      current.tabID == tabID,
                      current.field.token == token
                else { return }
                current.isGenerating = false
                if candidates.isEmpty {
                    current.errorMessage = chat.currentErrorMessage() ?? "未能生成候选，请重试。"
                } else {
                    current.candidates = candidates
                    current.messages.append(.init(role: .assistant, text: "已生成 \(candidates.count) 个候选。"))
                    formCandidateCache[cacheKey] = BrowserFormCandidateCacheEntry(createdAt: Date(), candidates: candidates)
                    formCandidateCache = formCandidateCache.filter { Date().timeIntervalSince($0.value.createdAt) < 300 }
                }
                formAssistant = current
                formGenerationTask = nil
            }
        }
    }

    private func cancelFormGeneration() {
        guard formGenerationTask != nil || formAssistant?.isGenerating == true else { return }
        formGenerationTask?.cancel()
        formGenerationTask = nil
        chat.cancelActiveRun()
        if var state = formAssistant {
            state.isGenerating = false
            formAssistant = state
        }
    }

    private func updateFormCandidate(_ id: UUID, _ text: String) {
        guard var state = formAssistant,
              let index = state.candidates.firstIndex(where: { $0.id == id })
        else { return }
        state.candidates[index].text = text
        formAssistant = state
    }

    private func insertFormCandidate(_ text: String, mode: BrowserFormInsertionMode) {
        guard let state = formAssistant, let webView = activeWebView else { return }
        mutateEditableField(
            webView: webView,
            token: state.field.token,
            text: text,
            mode: mode,
            expectedCurrentValue: nil
        ) { receipt in
            guard var current = formAssistant, current.field.token == state.field.token else { return }
            if receipt.ok {
                current.field.currentValue = receipt.insertedValue ?? text
                current.errorMessage = nil
                formUndoReceipt = receipt
            } else {
                current.errorMessage = receipt.reason ?? "插入失败，请重新选择输入框。"
            }
            formAssistant = current
        }
    }

    private func undoFormInsertion() {
        guard let receipt = formUndoReceipt,
              let token = receipt.token,
              let previous = receipt.previousValue,
              let inserted = receipt.insertedValue,
              let webView = activeWebView
        else { return }
        mutateEditableField(
            webView: webView,
            token: token,
            text: previous,
            mode: .replaceAll,
            expectedCurrentValue: inserted
        ) { result in
            guard var current = formAssistant, current.field.token == token else { return }
            if result.ok {
                current.field.currentValue = previous
                current.errorMessage = nil
                formUndoReceipt = nil
            } else {
                current.errorMessage = result.reason ?? "未能撤销。"
            }
            formAssistant = current
        }
    }

    private func mutateEditableField(
        webView: WKWebView,
        token: String,
        text: String,
        mode: BrowserFormInsertionMode,
        expectedCurrentValue: String?,
        completion: @escaping (BrowserFormInsertionReceipt) -> Void
    ) {
        Task {
            do {
                let value = try await webView.callAsyncJavaScript(
                    EmbeddedWebView.editableFieldMutationScript,
                    arguments: [
                        "token": token,
                        "text": text,
                        "mode": mode.rawValue,
                        "expectedCurrentValue": expectedCurrentValue ?? NSNull()
                    ],
                    in: nil,
                    contentWorld: .page
                )
                guard let dictionary = value as? [String: Any] else {
                    completion(.init(ok: false, reason: "网页未返回插入结果。", previousValue: nil, insertedValue: nil, token: token))
                    return
                }
                completion(.init(
                    ok: dictionary["ok"] as? Bool ?? false,
                    reason: dictionary["reason"] as? String,
                    previousValue: dictionary["previousValue"] as? String,
                    insertedValue: dictionary["insertedValue"] as? String,
                    token: dictionary["token"] as? String ?? token
                ))
            } catch {
                completion(.init(ok: false, reason: error.localizedDescription, previousValue: nil, insertedValue: nil, token: token))
            }
        }
    }

    private func formCandidateCacheKey(state: BrowserFormAssistantState, request: String) -> String {
        [state.field.pageURL, state.field.token, state.field.currentValue, state.tone.rawValue, state.length.rawValue, state.language.rawValue, request]
            .joined(separator: "|")
    }

    private func showSelectionPopover(_ payload: BrowserSelectionPayload, tabID: BrowserTabState.ID) {
        closeFormAssistant()
        let page = BrowserPageContext(url: payload.pageURL, title: payload.pageTitle, text: payload.pageText)
        let context = BrowserSelectionContext(page: page, selectedText: payload.selectedText)
        guard context.hasSelectionContext else { return }
        let threadID = BrowserSelectionThread.stableID(tabID: tabID, pageURL: payload.pageURL, selectedText: payload.selectedText)
        showContextPopover(context, tabID: tabID, rect: payload.rect, threadID: threadID, threadSelectedText: payload.selectedText)
    }

    private func showPageQuestionPopover() {
        guard let webView = activeWebView, let tabID = activeSelectedTabID else { return }
        webView.evaluateJavaScript(Self.pageContextScript) { result, error in
            if let error {
                DispatchQueue.main.async { chat.reportError(error.localizedDescription) }
                return
            }
            guard let json = result as? String,
                  let data = json.data(using: .utf8),
                  let payload = try? JSONDecoder().decode(BrowserPageQuestionPayload.self, from: data)
            else { return }
            let context = BrowserSelectionContext(
                page: BrowserPageContext(url: payload.pageURL, title: payload.pageTitle, text: payload.pageText),
                selectedText: ""
            )
            guard context.hasPageContext else { return }
            let width = max(420, webView.bounds.width)
            let rect = BrowserSelectionRect(x: max(24, width - 260), y: 16, width: 220, height: 28)
            let threadID = BrowserSelectionThread.stablePageID(tabID: tabID, pageURL: payload.pageURL)
            DispatchQueue.main.async {
                showContextPopover(context, tabID: tabID, rect: rect, threadID: threadID, threadSelectedText: "")
            }
        }
    }

    private func showContextPopover(_ context: BrowserSelectionContext, tabID: BrowserTabState.ID, rect: BrowserSelectionRect, threadID: UUID, threadSelectedText: String) {
        mutateActiveSession { session in
            if session.threads[threadID] == nil {
                session.threads[threadID] = BrowserSelectionThread(
                    id: threadID,
                    tabID: tabID,
                    pageURL: context.page.url,
                    selectedText: threadSelectedText,
                    messages: []
                )
            }
            session.selectionPopover = BrowserSelectionPopoverState(
                tabID: tabID,
                context: context,
                rect: rect,
                threadID: threadID
            )
        }
    }

    private func closeSelectionPopover(policy: BrowserPopoverDismissalPolicy) {
        mutateActiveSession { session in session.selectionPopover = nil }
        if !policy.shouldPreserveDraftQuestion { questionText = "" }
    }

    private func installBrowserKeyMonitorIfNeeded() {
        guard browserKeyMonitor == nil else { return }
        browserKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let characters = event.charactersIgnoringModifiers?.lowercased()
            let commandOnly = event.modifierFlags.contains(.command)
                && !event.modifierFlags.contains(.control)
                && !event.modifierFlags.contains(.option)
            if event.keyCode == 53, isFindBarVisible {
                closeFindBar()
                return nil
            }
            if event.keyCode == 53, formAssistant != nil {
                closeFormAssistant()
                return nil
            }
            if commandOnly, characters == "f" {
                showFindBar()
                return nil
            }
            if commandOnly, characters == "+" || characters == "=" {
                adjustPageZoom(by: 0.1)
                return nil
            }
            if commandOnly, characters == "-" {
                adjustPageZoom(by: -0.1)
                return nil
            }
            if commandOnly, characters == "0" {
                setPageZoom(1)
                return nil
            }
            if commandOnly, characters == "p" {
                printCurrentPage()
                return nil
            }
            let shortcut = BrowserKeyboardShortcutResolver().shortcut(
                character: event.charactersIgnoringModifiers,
                isEscape: event.keyCode == 53,
                isCommandDown: event.modifierFlags.contains(.command),
                isShiftDown: event.modifierFlags.contains(.shift),
                isControlDown: event.modifierFlags.contains(.control),
                isOptionDown: event.modifierFlags.contains(.option),
                hasSelectionPopover: activeSession.selectionPopover != nil,
                settings: chat.shortcutSettings
            )

            switch shortcut {
            case .closeSelectionPopover:
                closeSelectionPopover(policy: .escape)
                return nil
            case .focusAddress:
                focusAddressRequestID = UUID()
                return nil
            case .newTab:
                openNewTab(urlString: BrowserBuiltInPage.blankURLString, select: true)
                focusAddressRequestID = UUID()
                return nil
            case .closeSelectedTab:
                guard let selectedTabID = activeSelectedTabID else { return event }
                closeTab(selectedTabID)
                return nil
            case .goBack:
                activeWebView?.goBack()
                return nil
            case .goForward:
                activeWebView?.goForward()
                return nil
            case .toggleBookmarks:
                model.toggleBookmarksPanel()
                return nil
            case .toggleHistory:
                model.toggleHistoryPanel()
                return nil
            case nil:
                return event
            }
        }
    }

    private func removeBrowserKeyMonitor() {
        if let browserKeyMonitor {
            NSEvent.removeMonitor(browserKeyMonitor)
            self.browserKeyMonitor = nil
        }
    }

    private func insertSelectionContext(_ context: BrowserSelectionContext) {
        chat.appendToDraft(
            BrowserLLMContextBuilder().makeContextMarkdown(selection: context)
        )
    }

    private func sendSelectionQuestion(_ popover: BrowserSelectionPopoverState, questionOverride: String? = nil) {
        let question = (questionOverride ?? questionText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        appendThreadMessage(threadID: popover.threadID, role: .user, text: question)
        let pendingMessageID = appendThreadMessage(threadID: popover.threadID, role: .assistant, text: "", isPending: true)
        let isPageQuestion = popover.context.selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        chat.appendSessionRecord(
            isPageQuestion ? "browser.page.question" : "browser.selection.question",
            popover.context.page.title.isEmpty ? (isPageQuestion ? "网页提问" : "网页选择提问") : popover.context.page.title,
            question,
            [
                "pageURL": popover.context.page.url,
                "selectedText": String(popover.context.selectedText.prefix(500)),
                "contextScope": isPageQuestion ? "page" : "selection",
                "threadID": popover.threadID.uuidString,
                "tabID": popover.tabID.uuidString
            ],
            activeSessionID
        )
        let prompt = BrowserLLMContextBuilder().makePrompt(selection: popover.context, question: question)
        let displayPrompt = makeSelectionDisplayPrompt(selection: popover.context, question: question)
        questionText = ""
        Task {
            let answer = await chat.submit(prompt, displayPrompt)
            await MainActor.run {
                replaceThreadMessage(
                    threadID: popover.threadID,
                    messageID: pendingMessageID,
                    role: .assistant,
                    text: answer ?? chat.currentErrorMessage() ?? "未能获取回复。",
                    isPending: false
                )
            }
        }
    }

    @discardableResult
    private func appendThreadMessage(threadID: UUID, role: BrowserSelectionThreadMessage.Role, text: String, isPending: Bool = false) -> UUID {
        let message = BrowserSelectionThreadMessage(role: role, text: text, createdAt: Date(), isPending: isPending)
        mutateActiveSession { session in
            guard var thread = session.threads[threadID] else { return }
            thread.messages.append(message)
            session.threads[threadID] = thread
        }
        return message.id
    }

    private func makeSelectionDisplayPrompt(selection: BrowserSelectionContext, question: String) -> String {
        let title = selection.page.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = selection.page.url.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedText = selection.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let isPageQuestion = selectedText.isEmpty
        let selectedPreview = selectedText.count > 300 ? String(selectedText.prefix(300)) + "…" : selectedText
        var lines: [String] = [isPageQuestion ? "网页提问" : "网页选区提问"]
        if !title.isEmpty { lines.append("页面：\(title)") }
        if !url.isEmpty { lines.append("URL：\(url)") }
        if !selectedPreview.isEmpty {
            lines.append("")
            lines.append("选中文本：")
            lines.append("> \(selectedPreview.replacingOccurrences(of: "\n", with: "\n> "))")
        }
        lines.append("")
        lines.append("问题：\(question)")
        return lines.joined(separator: "\n")
    }

    private func replaceThreadMessage(threadID: UUID, messageID: UUID, role: BrowserSelectionThreadMessage.Role, text: String, isPending: Bool) {
        mutateActiveSession { session in
            guard var thread = session.threads[threadID],
                  let index = thread.messages.firstIndex(where: { $0.id == messageID })
            else { return }
            thread.messages[index].role = role
            thread.messages[index].text = text
            thread.messages[index].isPending = isPending
            session.threads[threadID] = thread
        }
    }

    private func selectionPopoverLayout(for rect: BrowserSelectionRect, in size: CGSize) -> BrowserSelectionPopoverLayout {
        BrowserSelectionPopoverLayoutCalculator().layout(
            anchorRect: rect,
            containerSize: size,
            preferredSize: CGSize(width: 420, height: 520)
        )
    }

    private static let pageRestorationSnapshotScript = """
    (function() {
      var bodyText = (document.body && document.body.innerText) ? document.body.innerText : '';
      var active = document.activeElement;
      function elementHint(element) {
        if (!element) { return ''; }
        if (element.id) { return '#' + element.id; }
        if (element.name) { return element.tagName.toLowerCase() + '[name="' + element.name + '"]'; }
        return element.tagName ? element.tagName.toLowerCase() : '';
      }
      return JSON.stringify({
        scrollX: window.scrollX || window.pageXOffset || 0,
        scrollY: window.scrollY || window.pageYOffset || 0,
        viewportWidth: window.innerWidth || 0,
        viewportHeight: window.innerHeight || 0,
        contentFingerprint: String((location.href || '') + '|' + (document.title || '') + '|' + bodyText.length + '|' + bodyText.slice(0, 200)),
        focusedElementHint: elementHint(active)
      });
    })();
    """

    private static let pageContextScript = """
    (function() {
      function readablePageText() {
        var candidates = [];
        var article = document.querySelector('article');
        if (article && article.innerText) { candidates.push(article.innerText); }
        var main = document.querySelector('main');
        if (main && main.innerText) { candidates.push(main.innerText); }
        if (document.body && document.body.innerText) { candidates.push(document.body.innerText); }
        var text = candidates.find(function(value) { return value && value.trim().length > 0; }) || '';
        return text.replace(/[ \\t]+/g, ' ').replace(/\\n{3,}/g, '\\n\\n').trim().slice(0, 60000);
      }
      return JSON.stringify({
        pageURL: location.href || '',
        pageTitle: document.title || '',
        pageText: readablePageText()
      });
    })();
    """
}

struct BrowserReaderPayload: Decodable {
    var title: String
    var url: String
    var text: String
}

enum BrowserReaderPage {
    static func html(_ payload: BrowserReaderPayload) -> String {
        let title = escape(payload.title.isEmpty ? "阅读模式" : payload.title)
        let source = escape(payload.url)
        let paragraphs = payload.text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { "<p>\(escape($0))</p>" }
            .joined(separator: "\n")
        return """
        <!doctype html><html lang="zh-Hans"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>\(title)</title><style>
        :root{color-scheme:light dark}body{margin:0;background:#f5f7f9;color:#172b3d;font:17px/1.85 -apple-system,BlinkMacSystemFont,sans-serif}
        article{max-width:760px;margin:0 auto;padding:72px 32px 110px}h1{font-size:42px;line-height:1.12;letter-spacing:0;margin:0 0 16px}a{color:#2879cc;word-break:break-all}p{margin:0 0 1.25em}
        .source{margin-bottom:42px;font-size:13px;color:#718395}@media(prefers-color-scheme:dark){body{background:#10171e;color:#e7edf2}.source{color:#91a3b2}}
        </style></head><body><article><h1>\(title)</h1><div class="source"><a href="\(source)">\(source)</a></div>\(paragraphs)</article></body></html>
        """
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

private struct BrowserPageRestorationSnapshot: Decodable {
    var scrollX: Double?
    var scrollY: Double?
    var viewportWidth: Double?
    var viewportHeight: Double?
    var contentFingerprint: String?
    var focusedElementHint: String?
}

private struct BrowserAddressTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var focusRequestID: UUID
    var onEditingChanged: (Bool) -> Void
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let textField = SelectAllOnFocusTextField()
        textField.delegate = context.coordinator
        textField.placeholderString = placeholder
        textField.font = .systemFont(ofSize: 13)
        textField.isBordered = true
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.focusRingType = .default
        textField.lineBreakMode = .byTruncatingMiddle
        textField.cell?.sendsActionOnEndEditing = false
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.onEditingChanged = onEditingChanged
        let editor = nsView.currentEditor()
        let isEditing = nsView.window?.firstResponder === editor || nsView.window?.firstResponder === nsView
        if !isEditing, nsView.stringValue != text {
            context.coordinator.isApplyingSwiftUIValue = true
            nsView.stringValue = text
            context.coordinator.isApplyingSwiftUIValue = false
        }
        nsView.placeholderString = placeholder
        if context.coordinator.lastFocusRequestID != focusRequestID {
            context.coordinator.lastFocusRequestID = focusRequestID
            context.coordinator.scheduleFocus(for: nsView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onEditingChanged: onEditingChanged, onSubmit: onSubmit)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        var onEditingChanged: (Bool) -> Void
        var onSubmit: () -> Void
        var lastFocusRequestID: UUID?
        var isApplyingSwiftUIValue = false

        init(text: Binding<String>, onEditingChanged: @escaping (Bool) -> Void, onSubmit: @escaping () -> Void) {
            _text = text
            self.onEditingChanged = onEditingChanged
            self.onSubmit = onSubmit
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            onEditingChanged(true)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            onEditingChanged(false)
        }

        func controlTextDidChange(_ notification: Notification) {
            guard !isApplyingSwiftUIValue,
                  let field = notification.object as? NSTextField else { return }
            let newValue = field.stringValue
            guard text != newValue else { return }
            text = newValue
        }

        func scheduleFocus(for field: NSTextField) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak field] in
                guard let field, let window = field.window else { return }
                if window.firstResponder !== field.currentEditor() && window.firstResponder !== field {
                    window.makeFirstResponder(field)
                }
                field.currentEditor()?.selectAll(nil)
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                text = (control as? NSTextField)?.stringValue ?? text
                onEditingChanged(false)
                onSubmit()
                return true
            }
            return false
        }
    }
}

private final class SelectAllOnFocusTextField: NSTextField {
    override func becomeFirstResponder() -> Bool {
        let didBecomeFirstResponder = super.becomeFirstResponder()
        if didBecomeFirstResponder {
            DispatchQueue.main.async { [weak self] in
                self?.currentEditor()?.selectAll(nil)
            }
        }
        return didBecomeFirstResponder
    }
}

private struct BrowserFormCandidateCacheEntry {
    var createdAt: Date
    var candidates: [BrowserFormCandidate]
}
