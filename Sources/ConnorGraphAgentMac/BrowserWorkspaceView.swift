import SwiftUI
import WebKit
import ConnorGraphAppSupport

struct BrowserWorkspaceSnapshot: Equatable {
    var tabs: [BrowserTabSnapshot]
    var selectedTabID: UUID?
    var selectionPopover: BrowserSelectionPopoverSnapshot?
    var threads: [UUID: BrowserSelectionThreadSnapshot]
}

struct BrowserTabSnapshot: Identifiable, Equatable {
    var id: UUID
    var initialURLString: String
    var title: String
    var currentURLString: String
    var isLoading: Bool
    var canGoBack: Bool
    var canGoForward: Bool
}

struct BrowserSelectionPopoverSnapshot: Equatable {
    var tabID: UUID
    var pageURL: String
    var pageTitle: String
    var pageText: String
    var selectedText: String
    var rect: BrowserSelectionRect
    var threadID: UUID
}

struct BrowserSelectionThreadSnapshot: Identifiable, Equatable {
    var id: UUID
    var tabID: UUID
    var pageURL: String
    var selectedText: String
    var messages: [BrowserSelectionThreadMessageSnapshot]
}

struct BrowserSelectionThreadMessageSnapshot: Identifiable, Equatable {
    enum Role: Equatable { case user, assistant }
    var id: UUID
    var role: Role
    var text: String
    var createdAt: Date
}

struct BrowserWorkspaceView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var webViewsByTabID: [UUID: WKWebView] = [:]
    @State private var addressText: String = ""
    @State private var questionText = ""

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
                                    initialURLString: tab.initialURLString,
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
                        BrowserSelectionPopover(
                            popover: popover,
                            thread: activeSession.thread(for: popover.threadID),
                            question: $questionText,
                            isSubmitting: viewModel.isSubmittingChat,
                            onAsk: {
                                sendSelectionQuestion(popover)
                            },
                            onInsert: {
                                insertSelectionContext(popover.context)
                            },
                            onSaveEvidence: {
                                Task { await viewModel.saveBrowserSelectionAsEpisode(popover.context) }
                            },
                            onClose: closeSelectionPopover
                        )
                        .frame(width: 420)
                        .position(popoverPosition(for: popover.rect, in: geometry.size))
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
                    }
                }
            }
        }
        .onAppear {
            ensureInitialTab()
            navigate(to: viewModel.browserTargetURLString)
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
        viewModel.browserTargetURLString.isEmpty ? "https://www.wikipedia.org" : viewModel.browserTargetURLString
    }

    private var tabBar: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(activeTabs) { tab in
                        BrowserTabChip(
                            title: tab.displayTitle,
                            url: tab.displayURL,
                            isSelected: tab.id == activeSelectedTabID,
                            isLoading: tab.navigationState.isLoading,
                            onSelect: { selectTab(tab.id) },
                            onClose: { closeTab(tab.id) }
                        )
                    }
                }
            }

            Button(action: { openNewTab(urlString: viewModel.browserTargetURLString, select: true) }) {
                Image(systemName: "plus")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 26)
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

            Button(action: { viewModel.isBrowserVisible = false }) {
                Label("返回对话", systemImage: "bubble.left.and.bubble.right")
            }
            .help("关闭网页工作区，返回对话时间线")
        }
    }

    private func ensureInitialTab() {
        if viewModel.browserWorkspaceSnapshotsBySessionID[activeSessionID] == nil {
            let session = BrowserSessionState.default(urlString: defaultURLString)
            viewModel.browserWorkspaceSnapshotsBySessionID[activeSessionID] = session.snapshot
            addressText = defaultURLString
        }
    }

    private func mutateActiveSession(_ update: (inout BrowserSessionState) -> Void) {
        var session = activeSession
        update(&session)
        viewModel.browserWorkspaceSnapshotsBySessionID[activeSessionID] = session.snapshot
        webViewsByTabID = session.webViewsByTabID
    }

    private func openNewTab(urlString: String, select: Bool) {
        let normalized = normalizedURLString(from: urlString) ?? "https://www.wikipedia.org"
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
        mutateActiveSession { session in
            guard let index = session.tabs.firstIndex(where: { $0.id == tabID }) else { return }
            session.tabs[index].navigationState = state
        }
        if tabID == activeSelectedTabID, !state.url.isEmpty { addressText = state.url }
    }

    private func syncAddressTextWithActiveTab() {
        guard let activeTab else { return }
        addressText = activeTab.navigationState.url.isEmpty ? activeTab.initialURLString : activeTab.navigationState.url
    }

    private func navigateFromAddressBar() {
        let trimmed = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let urlString = normalizedURLString(from: trimmed), let url = URL(string: urlString) else { return }
        viewModel.browserTargetURLString = url.absoluteString
        navigate(to: url.absoluteString)
    }

    private func navigate(to urlString: String) {
        guard let normalized = normalizedURLString(from: urlString), let url = URL(string: normalized) else { return }
        ensureInitialTab()
        addressText = url.absoluteString
        guard let selectedTabID = activeSelectedTabID else { return }
        mutateActiveSession { session in
            guard let index = session.tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
            session.tabs[index].initialURLString = url.absoluteString
            if session.tabs[index].webView?.url?.absoluteString != url.absoluteString {
                session.tabs[index].webView?.load(URLRequest(url: url))
            }
        }
    }

    private func normalizedURLString(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") { return trimmed }
        if trimmed.contains(".") && !trimmed.contains(" ") { return "https://\(trimmed)" }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        return "https://duckduckgo.com/?q=\(encoded)"
    }

    private func showSelectionPopover(_ payload: BrowserSelectionPayload, tabID: BrowserTabState.ID) {
        let page = BrowserPageContext(url: payload.pageURL, title: payload.pageTitle, text: payload.pageText)
        let context = BrowserSelectionContext(page: page, selectedText: payload.selectedText)
        guard context.hasSelectionContext else { return }
        let threadID = BrowserSelectionThread.stableID(tabID: tabID, pageURL: payload.pageURL, selectedText: payload.selectedText)
        mutateActiveSession { session in
            if session.threads[threadID] == nil {
                session.threads[threadID] = BrowserSelectionThread(
                    id: threadID,
                    tabID: tabID,
                    pageURL: payload.pageURL,
                    selectedText: payload.selectedText,
                    messages: []
                )
            }
            session.selectionPopover = BrowserSelectionPopoverState(
                tabID: tabID,
                context: context,
                rect: payload.rect,
                threadID: threadID
            )
        }
    }

    private func closeSelectionPopover() {
        mutateActiveSession { session in session.selectionPopover = nil }
        questionText = ""
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
        let prompt = BrowserLLMContextBuilder().makePrompt(selection: popover.context, question: question)
        questionText = ""
        Task { await viewModel.submitChat(prompt: prompt) }
    }

    private func appendThreadMessage(threadID: UUID, role: BrowserSelectionThreadMessage.Role, text: String) {
        mutateActiveSession { session in
            guard var thread = session.threads[threadID] else { return }
            thread.messages.append(BrowserSelectionThreadMessage(role: role, text: text, createdAt: Date()))
            session.threads[threadID] = thread
        }
    }

    private func popoverPosition(for rect: BrowserSelectionRect, in size: CGSize) -> CGPoint {
        let width: CGFloat = 420
        let height: CGFloat = 300
        let margin: CGFloat = 14
        let rawX = rect.x + rect.width / 2
        let x = min(max(rawX, width / 2 + margin), max(width / 2 + margin, size.width - width / 2 - margin))
        let belowY = rect.y + rect.height + height / 2 + 12
        let aboveY = rect.y - height / 2 - 12
        let y = belowY + margin < size.height ? belowY : max(aboveY, height / 2 + margin)
        return CGPoint(x: x, y: y)
    }
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
}

private struct BrowserSelectionThreadMessage: Identifiable {
    enum Role { case user, assistant }
    var id: UUID = UUID()
    var role: Role
    var text: String
    var createdAt: Date

    init(id: UUID = UUID(), role: Role, text: String, createdAt: Date) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }

    init(snapshot: BrowserSelectionThreadMessageSnapshot) {
        self.id = snapshot.id
        self.role = snapshot.role == .user ? .user : .assistant
        self.text = snapshot.text
        self.createdAt = snapshot.createdAt
    }

    var snapshot: BrowserSelectionThreadMessageSnapshot {
        BrowserSelectionThreadMessageSnapshot(
            id: id,
            role: role == .user ? .user : .assistant,
            text: text,
            createdAt: createdAt
        )
    }
}

struct BrowserSelectionRect: Decodable, Equatable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
}

private struct BrowserSelectionPayload: Decodable {
    var pageURL: String
    var pageTitle: String
    var pageText: String
    var selectedText: String
    var rect: BrowserSelectionRect
}

private struct BrowserSelectionPopover: View {
    var popover: BrowserSelectionPopoverState
    var thread: BrowserSelectionThread?
    @Binding var question: String
    var isSubmitting: Bool
    var onAsk: () -> Void
    var onInsert: () -> Void
    var onSaveEvidence: () -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("网页选择", systemImage: "selection.pin.in.out")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
            }

            VStack(alignment: .leading, spacing: 4) {
                if !popover.context.page.title.isEmpty {
                    Text(popover.context.page.title)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                }
                if !popover.context.page.url.isEmpty {
                    Text(popover.context.page.url)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Text(popover.context.selectedText)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(4)
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            BrowserSelectionThreadList(messages: thread?.messages ?? [])
                .frame(maxHeight: 96)

            HStack(spacing: 8) {
                TextField("基于选中文本提问…", text: $question, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
                    .onSubmit(onAsk)

                AgentSendControlButton(
                    isSubmitting: isSubmitting,
                    isDisabled: !isSubmitting && question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    action: onAsk
                )
            }

            HStack {
                Button("插入到输入框", action: onInsert)
                Button("保存为证据", action: onSaveEvidence)
                Spacer()
                Text("发送后浮窗保持打开")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .font(.caption)
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

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                if messages.isEmpty {
                    Text("这个网页选择还没有提问记录。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                } else {
                    ForEach(messages) { message in
                        HStack(alignment: .top, spacing: 6) {
                            Text(message.role == .user ? "你" : "AI")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(message.role == .user ? Color.accentColor : Color.secondary)
                                .frame(width: 22, alignment: .leading)
                            Text(message.text)
                                .font(.caption2)
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

private struct BrowserTabChip: View {
    var title: String
    var url: String
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
                .frame(width: 112, alignment: .leading)

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
        .frame(height: 25)
        .background(tabBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(tabBorder, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onTapGesture(perform: onSelect)
        .help(url)
    }

    private var tabBackground: Color { isSelected ? Color(nsColor: .controlBackgroundColor) : Color.secondary.opacity(0.045) }
    private var tabBorder: Color { isSelected ? Color.secondary.opacity(0.18) : Color.secondary.opacity(0.07) }
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

        if let url = URL(string: initialURLString), !initialURLString.isEmpty {
            webView.load(URLRequest(url: url))
        }
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
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { publishNavigationState(webView, errorMessage: error.localizedDescription) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { publishNavigationState(webView, errorMessage: error.localizedDescription) }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                DispatchQueue.main.async { self.onOpenInNewTab(url) }
            }
            return nil
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
