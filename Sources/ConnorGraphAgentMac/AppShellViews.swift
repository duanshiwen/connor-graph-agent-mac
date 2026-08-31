import SwiftUI
import AppKit
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphSearch
import ConnorGraphAgent
import ConnorGraphStore
import ConnorGraphAppSupport

struct AppStartupRootView<Content: View>: View {
    @Bindable var startupCoordinator: AppStartupCoordinator
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            if startupCoordinator.isInteractiveReady {
                content
                    .transition(.opacity)
            } else {
                AppInitializationView(startupCoordinator: startupCoordinator)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: startupCoordinator.isInteractiveReady)
        .task {
            await startupCoordinator.startIfNeeded()
        }
    }
}

private struct AppInitializationView: View {
    @Bindable var startupCoordinator: AppStartupCoordinator

    var body: some View {
        VStack(spacing: AppShellLayout.spaceL) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .padding(.bottom, AppShellLayout.spaceS)
                .accessibilityHidden(true)

            VStack(spacing: AppShellLayout.spaceS) {
                Text("康纳同学")
                    .font(AppTypography.pageTitle)

                if startupCoordinator.phase == .failed {
                    Text("初始化失败")
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(.red)

                    Text(startupCoordinator.failureMessage ?? "无法完成应用初始化。")
                        .font(AppTypography.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .frame(maxWidth: 420)
                } else {
                    ProgressView()
                        .controlSize(.regular)
                        .accessibilityLabel("应用正在初始化")

                    Text(startupStatusText)
                        .font(AppTypography.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if startupCoordinator.phase == .failed {
                Button("重新尝试") {
                    Task { await startupCoordinator.retry() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(AppButtonLayout.controlSize)
            }
        }
        .padding(AppShellLayout.spaceXL)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var startupStatusText: String {
        switch startupCoordinator.phase {
        case .lightConstruction:
            "正在准备应用…"
        case .coreBootstrap:
            "正在加载本地数据…"
        case .interactiveReady, .contentReady, .maintenanceReady:
            "即将完成…"
        case .failed:
            "初始化失败"
        }
    }
}

struct AppShellView: View {
    let graph: AppFeatureGraph
    @ObservedObject var identityStore: AppUserIdentityStore
    @ObservedObject var noteImportModel: NoteImportViewModel
    var sendCommand: (AppCommand) -> Void
    @Environment(\.openWindow) private var openWindow
    @State private var isPrimarySidebarVisible = true
    @State private var isIdentityPopoverPresented = false
    @State private var shellContentWidth: CGFloat = 0
    @State private var userRequestedSidebarHidden = false

    private var selectionBinding: Binding<SidebarItem?> {
        Binding(
            get: { graph.shell.selection ?? .agentChat },
            set: { graph.shell.selection = $0 ?? .agentChat }
        )
    }

    private var identityButtonHelp: String {
        identityStore.currentUser.map { "打开用户菜单，当前用户：\($0.displayName)" } ?? "打开用户菜单，尚未登录"
    }

    /// 从会话列表等入口请求“添加康纳好友”时，在当前页面上方直接弹出加好友弹窗，
    /// 不切换左侧栏到人际关系页。
    private var addFriendPresented: Binding<Bool> {
        Binding(
            get: { graph.shell.addFriendRequestID != nil },
            set: { presented in
                if !presented { graph.shell.clearAddFriendRequest() }
            }
        )
    }
    @State private var topSearchKeyMonitor: Any?

    var body: some View {
        Group {
            if graph.aiConnections.showsWelcome {
                WelcomeLLMView(
                    model: graph.aiConnections,
                    openURL: graph.shellActions.openURL
                )
            } else {
                if widthClass.usesStackedPanes {
                    stackedContent
                } else {
                    HStack(spacing: 0) {
                        if isPrimarySidebarVisible {
                            CraftPrimarySidebarView(
                                graph: graph,
                                selection: selectionBinding,
                                sendCommand: sendCommand
                            )
                            // 主侧栏固定宽度，不允许用户拖动更改。
                            .frame(width: AppShellLayout.sidebarColumnWidth)
                            .frame(maxHeight: .infinity)
                            .background(.bar)
                            .controlSize(AppButtonLayout.controlSize)
                        }

                        CraftListPaneView(
                            graph: graph,
                            selection: selectionBinding
                        )
                            .frame(width: AppShellLayout.listColumnWidth)
                            .frame(maxHeight: .infinity)
                            .background(AppShellColors.listBackground)
                            .controlSize(AppButtonLayout.controlSize)

                        CraftDetailPaneView(
                            graph: graph,
                            identityStore: identityStore,
                            selection: graph.shell.selection ?? .agentChat
                        )
                            .frame(minWidth: AppShellLayout.detailColumnMinWidth, maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(nsColor: .textBackgroundColor).opacity(0.12))
                            .controlSize(AppButtonLayout.controlSize)
                    }
                }
        }
        }
        .onChange(of: graph.knowledgeCreator.snapshot.stage) { oldStage, newStage in
            // LLM 生成结束（进入预览/完成/冲突）时自动弹出后台“知识库发布进度”窗口；
            // 用户可提前关闭创作窗口，发布任务继续在后台执行。
            let attentionStages: Set<CloudKnowledgeCreatorStage> = [.preview, .completed, .conflict]
            if attentionStages.contains(newStage), !attentionStages.contains(oldStage) {
                openWindow(id: AppMenuPresentation.knowledgePublicationProgressWindowID)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    userRequestedSidebarHidden = isPrimarySidebarVisible
                    withAnimation(.easeInOut(duration: 0.16)) {
                        isPrimarySidebarVisible.toggle()
                    }
                } label: {
                    Label(isPrimarySidebarVisible ? "隐藏主侧栏" : "显示主侧栏", systemImage: "sidebar.leading")
                }
                .disabled(shellContentWidth < AppShellLayout.sidebarCollapseThreshold)
                .help(shellContentWidth < AppShellLayout.sidebarCollapseThreshold ? "窗口过窄，主侧栏已自动收起" : (isPrimarySidebarVisible ? "隐藏主侧栏" : "显示主侧栏"))
            }

            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TopSearchTextField(
                        text: Binding(
                            get: { graph.globalSearch.query },
                            set: { graph.globalSearch.updateQuery($0) }
                        ),
                        isFocused: Binding(
                            get: { graph.globalSearch.isFieldFocused },
                            set: { focused in
                                if focused {
                                    graph.globalSearch.activateField()
                                } else {
                                    graph.globalSearch.deactivateField()
                                }
                            }
                        ),
                        placeholder: "搜索或发起对话",
                        focusRequestID: graph.shell.focusTopSearchRequestID,
                        onSubmit: { graph.globalSearch.performSelectedItem() },
                        onMoveUp: { graph.globalSearch.moveSelectionUp() },
                        onMoveDown: { graph.globalSearch.moveSelectionDown() },
                        onCancel: { graph.globalSearch.dismissOverlay() }
                    )
                    .frame(minWidth: widthClass.isCompactOrNarrow ? 150 : 220, idealWidth: 320, maxWidth: 420, minHeight: 18, idealHeight: 20, maxHeight: 22)
                    if !graph.globalSearch.query.isEmpty {
                        Button(action: { graph.globalSearch.clear() }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("清除搜索")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .frame(height: 28)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            ToolbarItemGroup(placement: .primaryAction) {
                KnowledgePublicationToolbarProgressButton(store: graph.knowledgeCreator) {
                    openWindow(id: AppMenuPresentation.knowledgePublicationProgressWindowID)
                }

                if noteImportModel.activitySummary.isVisible {
                    NoteImportToolbarProgressButton(summary: noteImportModel.activitySummary) {
                        openWindow(id: AppMenuPresentation.noteImportCenterWindowID)
                    }
                }

                Button { isIdentityPopoverPresented.toggle() } label: {
                    if let user = identityStore.currentUser {
                        IdentityAvatarView(user: user, size: 24, revision: identityStore.avatarRevision)
                    } else {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 20))
                    }
                }
                .buttonStyle(.appIcon)
                .help(identityButtonHelp)
                .accessibilityLabel(identityButtonHelp)
                .popover(isPresented: $isIdentityPopoverPresented, arrowEdge: .bottom) {
                    UserIdentityPopoverView(identityStore: identityStore) {
                        isIdentityPopoverPresented = false
                        graph.shell.selectSettingsSection(.identity)
                    }
                }
            }
        }
        .overlay(alignment: .topLeading) {
            BrowserBackgroundTaskRunnerView(model: graph.browser)
        }
        .overlay {
            if graph.globalSearch.isOverlayPresented && (!graph.globalSearch.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !graph.globalSearch.historyEntries.isEmpty) {
                ZStack(alignment: .top) {
                    // 透明点击层：点击搜索面板之外的任意页面区域即关闭浮层。
                    // 面板本身叠加在其上层，仍正常响应；工具栏/搜索框区域在内容区之外不受影响。
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { graph.globalSearch.dismissOverlay() }
                        .accessibilityHidden(true)
                    AppGlobalSearchOverlayView(model: graph.globalSearch)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                .zIndex(20)
            }
        }
        .background(WindowTitlebarConfigurator())
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        shellContentWidth = proxy.size.width
                        applyResponsiveSidebar(width: proxy.size.width)
                    }
                    .onChange(of: proxy.size.width) { _, newWidth in
                        shellContentWidth = newWidth
                        withAnimation(.easeInOut(duration: 0.16)) {
                            applyResponsiveSidebar(width: newWidth)
                        }
                    }
            }
        )
        .environment(\.windowWidthClass, widthClass)
        .frame(minWidth: AppShellLayout.shellMinWidth, minHeight: AppShellLayout.shellMinHeight)
        .onAppear {
            if graph.shell.selection == nil {
                graph.shell.selection = .agentChat
            }
            graph.chatActions.session.reloadChatSessionsIfNeededAfterInitialLoad()
            installTopSearchKeyMonitorIfNeeded()
            graph.shellActions.activateSettingsSideEffects()
        }
        .onDisappear {
            removeTopSearchKeyMonitor()
        }
        .onReceive(NotificationCenter.default.publisher(for: .connorSessionNotificationActivated)) { notification in
            guard let sessionID = notification.userInfo?["sessionID"] as? String else { return }
            sendCommand(.openSessionNotification(sessionID))
        }
        .onReceive(NotificationCenter.default.publisher(for: .connorImNotificationActivated)) { notification in
            if let conversationID = notification.userInfo?["imConversationID"] as? String {
                graph.shell.selection = .agentChat
                Task { await graph.im?.selectConversation(conversationID) }
            } else if notification.userInfo?["openContacts"] as? Bool == true {
                graph.shell.selection = .contacts
            }
        }
        .sheet(isPresented: addFriendPresented) {
            if let im = graph.im {
                ImAddFriendSheet(model: im, isPresented: addFriendPresented)
            }
        }
    }

    private var widthClass: AppWindowWidthClass {
        if shellContentWidth < AppShellLayout.phoneWidthThreshold { return .phone }
        if shellContentWidth < AppShellLayout.narrowWidthThreshold { return .narrow }
        if shellContentWidth < AppShellLayout.sidebarCollapseThreshold { return .compact }
        return .regular
    }

    /// 窄窗口堆叠布局（narrow/phone）：列表/详情二选一，全屏堆叠，带滑动切换动画；
    /// 详情页始终提供返回入口，返回后回到列表。
    private var stackedContent: some View {
        ZStack {
            if isDetailActive {
                CraftDetailPaneView(
                    graph: graph,
                    identityStore: identityStore,
                    selection: graph.shell.selection ?? .agentChat
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.12))
                .controlSize(AppButtonLayout.controlSize)
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .overlay(alignment: .topLeading) {
                    if let backAction = stackedBackAction {
                        Button(action: backAction) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: AppShellLayout.stackedBackButtonIconSize, weight: .bold))
                                .frame(width: AppShellLayout.stackedBackButtonSize, height: AppShellLayout.stackedBackButtonSize)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .padding(.horizontal, AppShellLayout.spaceM)
                        .padding(.top, AppShellLayout.spaceS)
                        .help("返回")
                        .accessibilityLabel("返回")
                    }
                }
            } else {
                CraftListPaneView(
                    graph: graph,
                    selection: selectionBinding
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppShellColors.listBackground)
                .controlSize(AppButtonLayout.controlSize)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isDetailActive)
    }

    /// 窄窗口堆叠布局下当前路由是否处于“详情”页（需要展示返回按钮并隐藏列表）。
    private var isDetailActive: Bool {
        let route = graph.shell.selection ?? .agentChat
        switch route {
        case .agentChat:
            if let im = graph.im, im.selectedConversationId != nil { return true }
            return graph.chat.sessions.selectedSessionID != nil
        case .mail:
            return graph.mail.selectedMessageID != nil
        case .rss:
            return graph.rss.selectedItemID != nil
        case .interactiveWeb:
            return graph.interactiveWeb.selectedProjectID != nil
        case .contacts:
            return graph.contacts.selectedContactID != nil
        default:
            // 设置/来源/技能/自动化等页面本身即详情形态，直接全屏展示。
            return true
        }
    }

    /// 窄窗口堆叠布局下详情页顶部的返回动作；聊天/IM 详情在头部自带返回按钮，这里不再叠加。
    private var stackedBackAction: (() -> Void)? {
        let route = graph.shell.selection ?? .agentChat
        switch route {
        case .agentChat:
            return nil
        case .mail:
            return { graph.mail.clearMessageSelection() }
        case .rss:
            return { graph.rss.clearItemSelection() }
        case .interactiveWeb:
            return { graph.interactiveWeb.clearSelection() }
        case .contacts:
            return { graph.contacts.clearContactSelection() }
        default:
            return { _ = graph.shell.select(.agentChat) }
        }
    }

    private func applyResponsiveSidebar(width: CGFloat) {
        if width < AppShellLayout.sidebarCollapseThreshold {
            if isPrimarySidebarVisible { isPrimarySidebarVisible = false }
        } else if width >= AppShellLayout.sidebarExpandThreshold, !userRequestedSidebarHidden {
            if !isPrimarySidebarVisible { isPrimarySidebarVisible = true }
        }
    }

    private func installTopSearchKeyMonitorIfNeeded() {
        guard topSearchKeyMonitor == nil else { return }
        topSearchKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let shortcut = graph.inputSettings.shortcut(for: .focusTopSearch)
            guard shortcut.matches(
                character: event.charactersIgnoringModifiers,
                isCommandDown: event.modifierFlags.contains(.command),
                isShiftDown: event.modifierFlags.contains(.shift),
                isControlDown: event.modifierFlags.contains(.control),
                isOptionDown: event.modifierFlags.contains(.option)
            ) else {
                return event
            }
            graph.shell.requestTopSearchFocus()
            return nil
        }
    }

    private func removeTopSearchKeyMonitor() {
        if let topSearchKeyMonitor {
            NSEvent.removeMonitor(topSearchKeyMonitor)
            self.topSearchKeyMonitor = nil
        }
    }

}

private struct WindowTitlebarConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { configure(window: view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(window: nsView.window) }
    }

    private func configure(window: NSWindow?) {
        guard let window else { return }
        window.styleMask.remove(.fullSizeContentView)
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        window.isMovableByWindowBackground = false
        let minimumSize = NSSize(
            width: AppShellLayout.shellMinWidth,
            height: AppShellLayout.shellMinHeight
        )
        if window.minSize != minimumSize {
            window.minSize = minimumSize
            window.contentMinSize = minimumSize
        }
    }
}
