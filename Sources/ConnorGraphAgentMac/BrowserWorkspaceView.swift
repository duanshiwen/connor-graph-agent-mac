import AppKit
import SwiftUI
import WebKit
import ConnorGraphCore
import ConnorGraphAppSupport

typealias BrowserWorkspaceSnapshot = AppBrowserStateSnapshot
typealias BrowserTabSnapshot = AppBrowserTabSnapshot
typealias BrowserSelectionPopoverSnapshot = AppBrowserSelectionPopoverSnapshot
typealias BrowserSelectionThreadSnapshot = AppBrowserSelectionThreadSnapshot
typealias BrowserSelectionThreadMessageSnapshot = AppBrowserSelectionThreadMessageSnapshot
typealias BrowserSelectionRect = AppBrowserSelectionRect

struct BrowserWorkspaceView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var webViewsByTabID: [UUID: WKWebView] = [:]
    @State private var addressText: String = ""
    @State private var focusAddressRequestID = UUID()
    @State private var questionText = ""
    @State private var browserKeyMonitor: Any?

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
                                    initialURLString: tab.restoredURLString,
                                    onWebViewCreated: { webView in
                                        DispatchQueue.main.async { setWebView(webView, for: tab.id) }
                                    },
                                    onNavigationStateChanged: { state in
                                        updateNavigationState(state, for: tab.id)
                                    },
                                    onOpenInNewTab: { url in
                                        openNewTab(urlString: url.absoluteString, select: true)
                                    },
                                    onSelectionChanged: { selection in
                                        showSelectionPopover(selection, tabID: tab.id)
                                    },
                                    onMediaSnapshotChanged: { snapshot in
                                        updateMediaSnapshot(snapshot, for: tab.id)
                                    }
                                )
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
                            isSubmitting: viewModel.isSubmittingChat,
                            onAsk: {
                                sendSelectionQuestion(popover)
                            },
                            onSummarizePage: {
                                let summaryQuestion = BrowserLLMContextBuilder().makePageSummaryQuestion(selection: popover.context)
                                sendSelectionQuestion(popover, questionOverride: summaryQuestion)
                            },
                            onCancel: {
                                viewModel.cancelActiveChatRun()
                            },
                            onClose: { closeSelectionPopover(policy: .explicitClose) }
                        )
                        .frame(width: layout.width)
                        .frame(maxHeight: layout.maxHeight)
                        .position(layout.position)
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
                    }
                }

                // Floating panels overlay on the right side
                if viewModel.isBrowserBookmarksPanelVisible {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        BrowserBookmarksPanelView(
                            viewModel: viewModel,
                            currentPageURL: activeTabCanBeBookmarked ? activeTab?.displayURL : nil,
                            currentPageTitle: activeTabCanBeBookmarked ? activeTab?.displayTitle : nil
                        )
                        .transition(AnyTransition.move(edge: Edge.trailing).combined(with: AnyTransition.opacity))
                    }
                }

                if viewModel.isBrowserHistoryPanelVisible {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        BrowserHistoryPanelView(viewModel: viewModel)
                            .transition(AnyTransition.move(edge: Edge.trailing).combined(with: AnyTransition.opacity))
                    }
                }
            }
        }
        .onAppear {
            ensureInitialTab()
            viewModel.loadBrowserBookmarks()
            navigate(to: viewModel.browserTargetURLString)
            installBrowserKeyMonitorIfNeeded()
        }
        .onDisappear {
            removeBrowserKeyMonitor()
        }
        .onChange(of: viewModel.browserTargetURLString) { _, newValue in
            ensureInitialTab()
            navigate(to: newValue)
        }
        .onChange(of: viewModel.selectedChatSessionID) { _, _ in
            ensureInitialTab()
            syncAddressTextWithActiveTab()
            questionText = ""
        }
        .onChange(of: activeSelectedTabID) { _, _ in
            syncAddressTextWithActiveTab()
            questionText = ""
        }
    }

    private var activeSessionID: String {
        viewModel.selectedChatSessionID ?? "__fallback__"
    }

    private var activeSession: BrowserSessionState {
        let snapshot = viewModel.browserWorkspaceSnapshotsBySessionID[activeSessionID]
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
        viewModel.browserTargetURLString.isEmpty ? BrowserBuiltInPage.blankURLString : viewModel.browserTargetURLString
    }

    private var activeTabCanBeBookmarked: Bool {
        guard let url = activeTab?.displayURL.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty else { return false }
        return !url.hasPrefix("connor://") && !url.hasPrefix("about:") && !url.hasPrefix("data:")
    }

    private var activeURLIsBookmarked: Bool {
        guard activeTabCanBeBookmarked, let url = activeTab?.displayURL else { return false }
        return viewModel.isBrowserBookmarked(url: url)
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
                                onSelect: { selectTab(tab.id) },
                                onClose: { closeTab(tab.id) }
                            )
                        }
                    }
                }
                .frame(width: availableTabWidth, alignment: .leading)

                Button(action: { openNewTab(urlString: viewModel.browserTargetURLString, select: true) }) {
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

            BrowserAddressTextField(
                text: $addressText,
                placeholder: "输入网址或搜索词，按 Return 打开",
                focusRequestID: focusAddressRequestID,
                onSubmit: navigateFromAddressBar
            )
            .frame(height: 28)

            Button(action: { viewModel.toggleBrowserBookmarksPanel() }) {
                BrowserToolbarIconButtonLabel(
                    systemImage: activeURLIsBookmarked ? "star.fill" : "star",
                    isActive: viewModel.isBrowserBookmarksPanelVisible || activeURLIsBookmarked,
                    iconFont: .system(size: 16, weight: .semibold)
                )
            }
            .buttonStyle(.plain)
            .help(activeURLIsBookmarked ? "当前页已收藏，打开收藏夹" : "打开收藏夹")
            .accessibilityLabel("收藏夹")

            if let mediaSnapshot = activeTab?.mediaSnapshot, mediaSnapshot.hasDetectedMedia {
                Button(action: {}) {
                    BrowserToolbarIconButtonLabel(
                        systemImage: "waveform.badge.magnifyingglass",
                        isActive: true,
                        iconFont: .system(size: 16, weight: .semibold)
                    )
                }
                .buttonStyle(.plain)
                .help("检测到 \(mediaSnapshot.mediaElements.count + mediaSnapshot.openGraphMedia.count) 个媒体来源；转写入口将在媒体任务面板中启用")
                .accessibilityLabel("检测到网页媒体")
            }

            Button(action: { viewModel.toggleBrowserHistoryPanel() }) {
                BrowserToolbarIconButtonLabel(
                    systemImage: viewModel.isBrowserHistoryPanelVisible ? "clock.arrow.circlepath" : "clock",
                    isActive: viewModel.isBrowserHistoryPanelVisible,
                    iconFont: .system(size: 16, weight: .semibold)
                )
            }
            .buttonStyle(.plain)
            .help("浏览历史")
            .accessibilityLabel("历史")

            Button(action: showPageQuestionPopover) {
                BrowserAskAIButtonLabel()
            }
            .buttonStyle(.plain)
            .disabled(activeWebView == nil || activeTab?.navigationState.isLoading == true)
            .opacity(activeWebView == nil || activeTab?.navigationState.isLoading == true ? 0.48 : 1)
            .help("基于当前网页全文提问")

            Button(action: { viewModel.returnFromBrowserWorkspace() }) {
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

    private func ensureInitialTab() {
        if viewModel.browserWorkspaceSnapshotsBySessionID[activeSessionID] == nil {
            let session = BrowserSessionState.default(urlString: defaultURLString)
            viewModel.saveBrowserWorkspaceSnapshot(session.snapshot, for: activeSessionID)
            addressText = defaultURLString
        }
    }

    private func mutateActiveSession(_ update: (inout BrowserSessionState) -> Void) {
        var session = activeSession
        update(&session)
        viewModel.saveBrowserWorkspaceSnapshot(session.snapshot, for: activeSessionID)
        webViewsByTabID = session.webViewsByTabID
    }

    private func openNewTab(urlString: String, select: Bool) {
        let normalized = normalizedURLString(from: urlString) ?? BrowserBuiltInPage.blankURLString
        let tab = BrowserTabState(initialURLString: normalized)
        mutateActiveSession { session in
            session.tabs.append(tab)
            if select { session.selectedTabID = tab.id }
        }
        if select { addressText = normalized }
    }

    private func selectTab(_ id: BrowserTabState.ID) {
        mutateActiveSession { session in
            session.selectedTabID = id
            session.selectionPopover = nil
        }
        syncAddressTextWithActiveTab()
    }

    private func closeTab(_ id: BrowserTabState.ID) {
        var shouldReturnToConversation = false
        mutateActiveSession { session in
            guard let index = session.tabs.firstIndex(where: { $0.id == id }) else { return }
            let wasSelected = session.selectedTabID == id
            session.tabs.remove(at: index)
            session.webViewsByTabID[id] = nil
            session.selectionPopover = session.selectionPopover?.tabID == id ? nil : session.selectionPopover

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
            viewModel.returnFromBrowserWorkspace()
        } else {
            syncAddressTextWithActiveTab()
        }
    }

    private func setWebView(_ webView: WKWebView, for tabID: BrowserTabState.ID) {
        mutateActiveSession { session in
            guard let index = session.tabs.firstIndex(where: { $0.id == tabID }) else { return }
            session.webViewsByTabID[tabID] = webView
            if session.tabs.indices.contains(index) { session.tabs[index].webView = webView }
            if session.selectedTabID == nil { session.selectedTabID = tabID }
        }
    }

    private func updateMediaSnapshot(_ snapshot: BrowserMediaSourceSnapshot, for tabID: BrowserTabState.ID) {
        mutateActiveSession { session in
            guard let index = session.tabs.firstIndex(where: { $0.id == tabID }) else { return }
            session.tabs[index].mediaSnapshot = snapshot
        }
    }

    private func updateNavigationState(_ state: WebNavigationState, for tabID: BrowserTabState.ID) {
        var displayURL = state.url
        mutateActiveSession { session in
            guard let index = session.tabs.firstIndex(where: { $0.id == tabID }) else { return }
            var normalizedState = state
            if normalizedState.url == "about:blank", session.tabs[index].initialURLString == BrowserBuiltInPage.blankURLString {
                normalizedState.url = BrowserBuiltInPage.blankURLString
            }
            displayURL = normalizedState.url
            session.tabs[index].navigationState = normalizedState
        }
        if tabID == activeSelectedTabID, !displayURL.isEmpty { addressText = displayURL }

        // Record browser history when page finishes loading
        if !state.isLoading, !state.url.isEmpty, !state.url.hasPrefix("connor://"), !state.url.hasPrefix("about:"), !state.url.hasPrefix("data:") {
            viewModel.recordBrowserHistory(
                url: state.url,
                title: state.title,
                sessionID: activeSessionID
            )
        }
    }

    private func syncAddressTextWithActiveTab() {
        guard let activeTab else { return }
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
        let trimmed = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let urlString = normalizedURLString(from: trimmed) else { return }
        viewModel.browserTargetURLString = urlString
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
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed == BrowserBuiltInPage.blankURLString { return trimmed }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") { return trimmed }
        if trimmed.contains(".") && !trimmed.contains(" ") { return "https://\(trimmed)" }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        return "https://cn.bing.com/search?q=\(encoded)"
    }

    private func showSelectionPopover(_ payload: BrowserSelectionPayload, tabID: BrowserTabState.ID) {
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
                DispatchQueue.main.async { viewModel.errorMessage = error.localizedDescription }
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
            let shortcut = BrowserKeyboardShortcutResolver().shortcut(
                character: event.charactersIgnoringModifiers,
                isEscape: event.keyCode == 53,
                isCommandDown: event.modifierFlags.contains(.command),
                isShiftDown: event.modifierFlags.contains(.shift),
                isControlDown: event.modifierFlags.contains(.control),
                isOptionDown: event.modifierFlags.contains(.option),
                hasSelectionPopover: activeSession.selectionPopover != nil,
                settings: viewModel.shortcutSettings
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
                viewModel.toggleBrowserBookmarksPanel()
                return nil
            case .toggleHistory:
                viewModel.toggleBrowserHistoryPanel()
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
        viewModel.chatInput = [viewModel.chatInput, BrowserLLMContextBuilder().makeContextMarkdown(selection: context)]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
    }

    private func sendSelectionQuestion(_ popover: BrowserSelectionPopoverState, questionOverride: String? = nil) {
        let question = (questionOverride ?? questionText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        appendThreadMessage(threadID: popover.threadID, role: .user, text: question)
        let pendingMessageID = appendThreadMessage(threadID: popover.threadID, role: .assistant, text: "", isPending: true)
        let isPageQuestion = popover.context.selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        viewModel.appendSessionRecord(
            kind: isPageQuestion ? "browser.page.question" : "browser.selection.question",
            title: popover.context.page.title.isEmpty ? (isPageQuestion ? "网页提问" : "网页选择提问") : popover.context.page.title,
            body: question,
            metadata: [
                "pageURL": popover.context.page.url,
                "selectedText": String(popover.context.selectedText.prefix(500)),
                "contextScope": isPageQuestion ? "page" : "selection",
                "threadID": popover.threadID.uuidString,
                "tabID": popover.tabID.uuidString
            ],
            sessionID: activeSessionID
        )
        let prompt = BrowserLLMContextBuilder().makePrompt(selection: popover.context, question: question)
        let displayPrompt = makeSelectionDisplayPrompt(selection: popover.context, question: question)
        questionText = ""
        Task {
            let answer = await viewModel.submitChat(prompt: prompt, displayPrompt: displayPrompt)
            await MainActor.run {
                replaceThreadMessage(
                    threadID: popover.threadID,
                    messageID: pendingMessageID,
                    role: .assistant,
                    text: answer ?? viewModel.errorMessage ?? "未能获取回复。",
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

private struct BrowserAddressTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var focusRequestID: UUID
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
        if nsView.stringValue != text {
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
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        var onSubmit: () -> Void
        var lastFocusRequestID: UUID?
        var isApplyingSwiftUIValue = false

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            _text = text
            self.onSubmit = onSubmit
        }

        func controlTextDidChange(_ notification: Notification) {
            guard !isApplyingSwiftUIValue,
                  let field = notification.object as? NSTextField else { return }
            let newValue = field.stringValue
            guard text != newValue else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.text != newValue else { return }
                self.text = newValue
            }
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
