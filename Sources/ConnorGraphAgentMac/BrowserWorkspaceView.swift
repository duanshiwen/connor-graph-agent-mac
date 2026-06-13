import AppKit
import SwiftUI
import WebKit
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
    @State private var questionText = ""
    @State private var escapeKeyMonitor: Any?

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
                            onClose: { closeSelectionPopover(policy: .explicitClose) }
                        )
                        .frame(width: layout.width)
                        .frame(maxHeight: layout.maxHeight)
                        .position(layout.position)
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
                    }
                }
            }
        }
        .onAppear {
            ensureInitialTab()
            navigate(to: viewModel.browserTargetURLString)
            installEscapeKeyMonitorIfNeeded()
        }
        .onDisappear {
            removeEscapeKeyMonitor()
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
                        .font(.callout.weight(.semibold))
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
                Image(systemName: "chevron.left")
            }
            .disabled(activeTab?.navigationState.canGoBack != true)
            .help("后退")

            Button(action: { activeWebView?.goForward() }) {
                Image(systemName: "chevron.right")
            }
            .disabled(activeTab?.navigationState.canGoForward != true)
            .help("前进")

            Button(action: { activeWebView?.reload() }) {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(activeWebView == nil)
            .help("刷新")

            TextField("输入网址或搜索词，按 Return 打开", text: $addressText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { navigateFromAddressBar() }

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
                    titleFont: .caption.weight(.semibold),
                    iconFont: .caption.weight(.bold)
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
        mutateActiveSession { session in
            guard let index = session.tabs.firstIndex(where: { $0.id == id }) else { return }
            let wasSelected = session.selectedTabID == id
            session.tabs.remove(at: index)
            session.selectionPopover = session.selectionPopover?.tabID == id ? nil : session.selectionPopover

            if session.tabs.isEmpty {
                let fallback = BrowserTabState(initialURLString: defaultURLString)
                session.tabs = [fallback]
                session.selectedTabID = fallback.id
                return
            }

            if wasSelected {
                let nextIndex = min(index, session.tabs.count - 1)
                session.selectedTabID = session.tabs[nextIndex].id
            }
        }
        syncAddressTextWithActiveTab()
    }

    private func setWebView(_ webView: WKWebView, for tabID: BrowserTabState.ID) {
        mutateActiveSession { session in
            guard let index = session.tabs.firstIndex(where: { $0.id == tabID }) else { return }
            session.webViewsByTabID[tabID] = webView
            if session.tabs.indices.contains(index) { session.tabs[index].webView = webView }
            if session.selectedTabID == nil { session.selectedTabID = tabID }
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
    }

    private func syncAddressTextWithActiveTab() {
        guard let activeTab else { return }
        addressText = activeTab.navigationState.url.isEmpty ? activeTab.initialURLString : activeTab.navigationState.url
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

    private func installEscapeKeyMonitorIfNeeded() {
        guard escapeKeyMonitor == nil else { return }
        escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53, activeSession.selectionPopover != nil else { return event }
            closeSelectionPopover(policy: .escape)
            return nil
        }
    }

    private func removeEscapeKeyMonitor() {
        if let escapeKeyMonitor {
            NSEvent.removeMonitor(escapeKeyMonitor)
            self.escapeKeyMonitor = nil
        }
    }

    private func insertSelectionContext(_ context: BrowserSelectionContext) {
        viewModel.chatInput = [viewModel.chatInput, BrowserLLMContextBuilder().makeContextMarkdown(selection: context)]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
    }

    private func sendSelectionQuestion(_ popover: BrowserSelectionPopoverState) {
        let question = questionText.trimmingCharacters(in: .whitespacesAndNewlines)
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

private struct BrowserSessionState {
    var tabs: [BrowserTabState]
    var selectedTabID: BrowserTabState.ID?
    var selectionPopover: BrowserSelectionPopoverState?
    var threads: [UUID: BrowserSelectionThread] = [:]
    var webViewsByTabID: [UUID: WKWebView] = [:]

    init(tabs: [BrowserTabState], selectedTabID: BrowserTabState.ID?, selectionPopover: BrowserSelectionPopoverState? = nil, threads: [UUID: BrowserSelectionThread] = [:], webViewsByTabID: [UUID: WKWebView] = [:]) {
        self.tabs = tabs
        self.selectedTabID = selectedTabID
        self.selectionPopover = selectionPopover
        self.threads = threads
        self.webViewsByTabID = webViewsByTabID
    }

    init(snapshot: BrowserWorkspaceSnapshot?, webViewsByTabID: [UUID: WKWebView], fallbackURLString: String) {
        guard let snapshot else {
            self = .default(urlString: fallbackURLString)
            self.webViewsByTabID = webViewsByTabID
            return
        }
        self.tabs = snapshot.tabs.map { BrowserTabState(snapshot: $0, webView: webViewsByTabID[$0.id]) }
        self.selectedTabID = snapshot.selectedTabID ?? self.tabs.first?.id
        self.selectionPopover = snapshot.selectionPopover.map(BrowserSelectionPopoverState.init(snapshot:))
        self.threads = Dictionary(uniqueKeysWithValues: snapshot.threads.map { ($0.key, BrowserSelectionThread(snapshot: $0.value)) })
        self.webViewsByTabID = webViewsByTabID
        if self.tabs.isEmpty {
            let fallback = BrowserTabState(initialURLString: fallbackURLString)
            self.tabs = [fallback]
            self.selectedTabID = fallback.id
        }
    }

    static func `default`(urlString: String) -> BrowserSessionState {
        let tab = BrowserTabState(initialURLString: urlString)
        return BrowserSessionState(tabs: [tab], selectedTabID: tab.id)
    }

    var snapshot: BrowserWorkspaceSnapshot {
        BrowserWorkspaceSnapshot(
            tabs: tabs.map(\.snapshot),
            selectedTabID: selectedTabID,
            selectionPopover: selectionPopover?.snapshot,
            threads: Dictionary(uniqueKeysWithValues: threads.map { ($0.key, $0.value.snapshot) })
        )
    }

    func thread(for id: UUID) -> BrowserSelectionThread? {
        threads[id]
    }
}

private struct BrowserTabState: Identifiable {
    let id: UUID
    var initialURLString: String
    var webView: WKWebView?
    var navigationState: WebNavigationState

    init(id: UUID = UUID(), initialURLString: String) {
        self.id = id
        self.initialURLString = initialURLString
        self.navigationState = WebNavigationState(canGoBack: false, canGoForward: false, title: "", url: initialURLString)
    }

    init(snapshot: BrowserTabSnapshot, webView: WKWebView?) {
        self.id = snapshot.id
        self.initialURLString = snapshot.initialURLString
        self.webView = webView
        self.navigationState = WebNavigationState(
            canGoBack: snapshot.canGoBack,
            canGoForward: snapshot.canGoForward,
            title: snapshot.title,
            url: snapshot.currentURLString,
            isLoading: snapshot.isLoading
        )
    }

    var snapshot: BrowserTabSnapshot {
        BrowserTabSnapshot(
            id: id,
            initialURLString: initialURLString,
            title: navigationState.title,
            currentURLString: displayURL,
            isLoading: navigationState.isLoading,
            canGoBack: navigationState.canGoBack,
            canGoForward: navigationState.canGoForward
        )
    }

    var displayTitle: String {
        let title = navigationState.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        if let host = URL(string: displayURL)?.host, !host.isEmpty { return host }
        return "新标签页"
    }

    var displayURL: String { navigationState.url.isEmpty ? initialURLString : navigationState.url }

    var restoredURLString: String {
        let restored = displayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return restored.isEmpty ? BrowserBuiltInPage.blankURLString : restored
    }
}

private struct BrowserSelectionPopoverState {
    var tabID: BrowserTabState.ID
    var context: BrowserSelectionContext
    var rect: BrowserSelectionRect
    var threadID: UUID

    init(tabID: BrowserTabState.ID, context: BrowserSelectionContext, rect: BrowserSelectionRect, threadID: UUID) {
        self.tabID = tabID
        self.context = context
        self.rect = rect
        self.threadID = threadID
    }

    init(snapshot: BrowserSelectionPopoverSnapshot) {
        self.tabID = snapshot.tabID
        self.context = BrowserSelectionContext(
            page: BrowserPageContext(url: snapshot.pageURL, title: snapshot.pageTitle, text: snapshot.pageText),
            selectedText: snapshot.selectedText
        )
        self.rect = snapshot.rect
        self.threadID = snapshot.threadID
    }

    var snapshot: BrowserSelectionPopoverSnapshot {
        BrowserSelectionPopoverSnapshot(
            tabID: tabID,
            pageURL: context.page.url,
            pageTitle: context.page.title,
            pageText: context.page.text,
            selectedText: context.selectedText,
            rect: rect,
            threadID: threadID
        )
    }
}

private struct BrowserSelectionThread: Identifiable {
    var id: UUID
    var tabID: BrowserTabState.ID
    var pageURL: String
    var selectedText: String
    var messages: [BrowserSelectionThreadMessage]

    init(id: UUID, tabID: BrowserTabState.ID, pageURL: String, selectedText: String, messages: [BrowserSelectionThreadMessage]) {
        self.id = id
        self.tabID = tabID
        self.pageURL = pageURL
        self.selectedText = selectedText
        self.messages = messages
    }

    init(snapshot: BrowserSelectionThreadSnapshot) {
        self.id = snapshot.id
        self.tabID = snapshot.tabID
        self.pageURL = snapshot.pageURL
        self.selectedText = snapshot.selectedText
        self.messages = snapshot.messages.map(BrowserSelectionThreadMessage.init(snapshot:))
    }

    var snapshot: BrowserSelectionThreadSnapshot {
        BrowserSelectionThreadSnapshot(
            id: id,
            tabID: tabID,
            pageURL: pageURL,
            selectedText: selectedText,
            messages: messages.map(\.snapshot)
        )
    }

    static func stableID(tabID: UUID, pageURL: String, selectedText: String) -> UUID {
        let key = "\(tabID.uuidString)|\(pageURL)|\(selectedText.prefix(120))"
        return UUID(uuidString: UUID.nameUUIDFromBytes(key)) ?? UUID()
    }

    static func stablePageID(tabID: UUID, pageURL: String) -> UUID {
        let key = "\(tabID.uuidString)|\(pageURL)|__page__"
        return UUID(uuidString: UUID.nameUUIDFromBytes(key)) ?? UUID()
    }
}

private struct BrowserSelectionThreadMessage: Identifiable {
    enum Role { case user, assistant }
    var id: UUID = UUID()
    var role: Role
    var text: String
    var createdAt: Date
    var isPending: Bool

    init(id: UUID = UUID(), role: Role, text: String, createdAt: Date, isPending: Bool = false) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.isPending = isPending
    }

    init(snapshot: BrowserSelectionThreadMessageSnapshot) {
        self.id = snapshot.id
        self.role = snapshot.role == .user ? .user : .assistant
        self.text = snapshot.text
        self.createdAt = snapshot.createdAt
        self.isPending = snapshot.isPending
    }

    var snapshot: BrowserSelectionThreadMessageSnapshot {
        BrowserSelectionThreadMessageSnapshot(
            id: id,
            role: role == .user ? .user : .assistant,
            text: text,
            createdAt: createdAt,
            isPending: isPending
        )
    }
}

private struct BrowserSelectionPayload: Decodable {
    var pageURL: String
    var pageTitle: String
    var pageText: String
    var selectedText: String
    var rect: BrowserSelectionRect
}

private struct BrowserPageQuestionPayload: Decodable {
    var pageURL: String
    var pageTitle: String
    var pageText: String
}

private struct BrowserSelectionPopover: View {
    var popover: BrowserSelectionPopoverState
    var thread: BrowserSelectionThread?
    @Binding var question: String
    var isSubmitting: Bool
    var onAsk: () -> Void
    var onClose: () -> Void

    var body: some View {
        let isPageQuestion = popover.context.selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(isPageQuestion ? "问一问 AI" : "网页选择", systemImage: isPageQuestion ? "sparkles" : "selection.pin.in.out")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
            }

            VStack(alignment: .leading, spacing: 4) {
                if !popover.context.page.title.isEmpty {
                    Text(popover.context.page.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                }
                if !popover.context.page.url.isEmpty {
                    Text(popover.context.page.url)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if !isPageQuestion {
                Text(popover.context.selectedText)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }

            BrowserSelectionThreadList(messages: thread?.messages ?? [], isPageQuestion: isPageQuestion)
                .frame(maxHeight: 360)

            HStack(spacing: 8) {
                TextField(isPageQuestion ? "基于当前网页提问…" : "基于选中文本提问…", text: $question, axis: .vertical)
                    .font(.subheadline)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
                    .onSubmit(onAsk)

                AgentSendControlButton(
                    isSubmitting: isSubmitting,
                    isDisabled: !isSubmitting && question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    action: onAsk
                )
            }

            Text("发送后浮窗保持打开")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 8)
    }
}

private struct BrowserSelectionThreadList: View {
    var messages: [BrowserSelectionThreadMessage]
    var isPageQuestion: Bool = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                if messages.isEmpty {
                    Text(isPageQuestion ? "这个网页还没有提问记录。" : "这个网页选择还没有提问记录。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                } else {
                    ForEach(messages) { message in
                        HStack(alignment: .top, spacing: 6) {
                            Text(message.role == .user ? "你" : "AI")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(message.role == .user ? ConnorCraftPalette.accent : Color.secondary)
                                .frame(width: 28, alignment: .leading)
                            if message.isPending {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                        .scaleEffect(0.62)
                                    Text("正在生成回复…")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            } else if message.role == .assistant {
                                AgentMarkdownPreviewText(markdown: message.text, font: .footnote)
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                Text(message.text)
                                    .font(.footnote)
                                    .foregroundStyle(.primary)
                                    .lineLimit(3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct BrowserTabChip: View {
    var title: String
    var url: String
    var width: CGFloat
    var isSelected: Bool
    var isLoading: Bool
    var onSelect: () -> Void
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: isLoading ? "arrow.triangle.2.circlepath" : "globe")
                .font(.caption2)
                .foregroundStyle(.secondary.opacity(isSelected ? 0.85 : 0.65))

            Text(title)
                .font(.caption2.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .frame(width: 13, height: 13)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary.opacity(0.72))
            .help("关闭标签页")
        }
        .padding(.leading, 8)
        .padding(.trailing, 5)
        .padding(.vertical, 4)
        .frame(width: width, height: 25)
        .background(tabBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(tabBorder, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onTapGesture(perform: onSelect)
        .help(url)
    }

    private var tabBackground: Color { isSelected ? Color(nsColor: .controlBackgroundColor) : Color.secondary.opacity(0.045) }
    private var tabBorder: Color { isSelected ? Color.secondary.opacity(0.18) : Color.secondary.opacity(0.07) }
}

private struct BrowserAskAIButtonLabel: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.caption.weight(.bold))
            Text("问一问 AI")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(ConnorCraftPalette.accent)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(
            LinearGradient(
                colors: [ConnorCraftPalette.accent.opacity(0.18), ConnorCraftPalette.accentSubtleFill],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: Capsule()
        )
        .overlay(Capsule().stroke(ConnorCraftPalette.accentBorder, lineWidth: 1))
        .shadow(color: ConnorCraftPalette.accent.opacity(0.16), radius: 8, x: 0, y: 3)
        .contentShape(Capsule())
    }
}

private struct BrowserLoadingOverlay: View {
    var message: String
    var systemImage: String = "arrow.triangle.2.circlepath"

    var body: some View {
        Label(message, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.secondary.opacity(0.18), lineWidth: 1))
    }
}

private struct WebNavigationState: Equatable {
    var canGoBack: Bool
    var canGoForward: Bool
    var title: String
    var url: String
    var isLoading: Bool = false
    var errorMessage: String? = nil
}

private struct EmbeddedWebView: NSViewRepresentable {
    var initialURLString: String
    var onWebViewCreated: (WKWebView) -> Void
    var onNavigationStateChanged: (WebNavigationState) -> Void
    var onOpenInNewTab: (URL) -> Void
    var onSelectionChanged: (BrowserSelectionPayload) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onNavigationStateChanged: onNavigationStateChanged,
            onOpenInNewTab: onOpenInNewTab,
            onSelectionChanged: onSelectionChanged
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.addUserScript(WKUserScript(source: Self.selectionObserverScript, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        configuration.userContentController.add(context.coordinator, name: Coordinator.selectionMessageName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.webView = webView
        onWebViewCreated(webView)

        webView.loadBrowserURLString(initialURLString)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.onNavigationStateChanged = onNavigationStateChanged
        context.coordinator.onOpenInNewTab = onOpenInNewTab
        context.coordinator.onSelectionChanged = onSelectionChanged
    }

    static let selectionObserverScript = """
    (function() {
      if (window.__connorSelectionObserverInstalled) { return; }
      window.__connorSelectionObserverInstalled = true;

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

      var lastKey = '';
      var timer = null;
      function reportSelection() {
        clearTimeout(timer);
        timer = setTimeout(function() {
          try {
            var selection = window.getSelection ? window.getSelection() : null;
            var text = selection ? selection.toString().trim() : '';
            if (!selection || !text || selection.rangeCount === 0) { return; }
            var rect = selection.getRangeAt(0).getBoundingClientRect();
            if (!rect || (rect.width === 0 && rect.height === 0)) { return; }
            var key = text + '|' + location.href + '|' + Math.round(rect.x) + '|' + Math.round(rect.y);
            if (key === lastKey) { return; }
            lastKey = key;
            window.webkit.messageHandlers.connorSelection.postMessage(JSON.stringify({
              pageURL: location.href || '',
              pageTitle: document.title || '',
              pageText: readablePageText(),
              selectedText: text,
              rect: { x: rect.x, y: rect.y, width: rect.width, height: rect.height }
            }));
          } catch (error) {}
        }, 80);
      }

      document.addEventListener('selectionchange', reportSelection, true);
      document.addEventListener('mouseup', reportSelection, true);
      document.addEventListener('keyup', reportSelection, true);
    })();
    """

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        static let selectionMessageName = "connorSelection"
        weak var webView: WKWebView?
        var onNavigationStateChanged: (WebNavigationState) -> Void
        var onOpenInNewTab: (URL) -> Void
        var onSelectionChanged: (BrowserSelectionPayload) -> Void

        init(
            onNavigationStateChanged: @escaping (WebNavigationState) -> Void,
            onOpenInNewTab: @escaping (URL) -> Void,
            onSelectionChanged: @escaping (BrowserSelectionPayload) -> Void
        ) {
            self.onNavigationStateChanged = onNavigationStateChanged
            self.onOpenInNewTab = onOpenInNewTab
            self.onSelectionChanged = onSelectionChanged
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == Self.selectionMessageName,
                  let json = message.body as? String,
                  let data = json.data(using: .utf8),
                  let payload = try? JSONDecoder().decode(BrowserSelectionPayload.self, from: data)
            else { return }
            DispatchQueue.main.async { self.onSelectionChanged(payload) }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { publishNavigationState(webView) }
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { publishNavigationState(webView) }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { publishNavigationState(webView) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { showErrorPage(in: webView, error: error) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { showErrorPage(in: webView, error: error) }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                DispatchQueue.main.async { self.onOpenInNewTab(url) }
            }
            return nil
        }

        private func showErrorPage(in webView: WKWebView, error: Error) {
            let failedURLString = webView.url?.absoluteString ?? ""
            webView.loadHTMLString(
                BrowserBuiltInPage.errorHTML(failedURLString: failedURLString, message: error.localizedDescription),
                baseURL: BrowserBuiltInPage.webViewBaseURL
            )
            publishNavigationState(webView, errorMessage: error.localizedDescription)
        }

        private func publishNavigationState(_ webView: WKWebView, errorMessage: String? = nil) {
            let state = WebNavigationState(
                canGoBack: webView.canGoBack,
                canGoForward: webView.canGoForward,
                title: webView.title ?? "",
                url: webView.url?.absoluteString ?? "",
                isLoading: webView.isLoading,
                errorMessage: errorMessage
            )
            DispatchQueue.main.async { self.onNavigationStateChanged(state) }
        }
    }
}

private extension WKWebView {
    func loadBrowserURLString(_ urlString: String) {
        if urlString == BrowserBuiltInPage.blankURLString || urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            loadHTMLString(BrowserBuiltInPage.blankHTML, baseURL: BrowserBuiltInPage.webViewBaseURL)
            return
        }
        guard let url = URL(string: urlString) else {
            loadHTMLString(BrowserBuiltInPage.errorHTML(failedURLString: urlString, message: "Invalid URL"), baseURL: BrowserBuiltInPage.webViewBaseURL)
            return
        }
        load(URLRequest(url: url))
    }
}

private extension UUID {
    static func nameUUIDFromBytes(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "00000000-0000-4000-8000-%012llx", hash & 0x0000_FFFF_FFFF_FFFF)
    }
}
