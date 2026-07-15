import SwiftUI
import AppKit
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphSearch
import ConnorGraphAgent
import ConnorGraphStore
import ConnorGraphAppSupport

struct AppShellView: View {
    let graph: AppFeatureGraph
    @ObservedObject var identityStore: AppUserIdentityStore
    @ObservedObject var noteImportModel: NoteImportViewModel
    var sendCommand: (AppCommand) -> Void
    @Environment(\.openWindow) private var openWindow
    @State private var isPrimarySidebarVisible = true
    @State private var isIdentityPopoverPresented = false

    private var selectionBinding: Binding<SidebarItem?> {
        Binding(
            get: { graph.shell.selection ?? .agentChat },
            set: { graph.shell.selection = $0 ?? .agentChat }
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
                HSplitView {
                    if isPrimarySidebarVisible {
                        CraftPrimarySidebarView(
                            graph: graph,
                            selection: selectionBinding,
                            sendCommand: sendCommand
                        )
                    .frame(
                        minWidth: AppShellLayout.primarySidebarMinWidth,
                        idealWidth: AppShellLayout.primarySidebarDefaultWidth,
                        maxWidth: AppShellLayout.primarySidebarMaxWidth,
                        maxHeight: .infinity
                    )
                    .background(.bar)
                    .controlSize(.small)
            }

            CraftListPaneView(
                graph: graph,
                selection: selectionBinding
            )
                .frame(
                    minWidth: AppShellLayout.listColumnMinWidth,
                    idealWidth: AppShellLayout.listColumnDefaultWidth,
                    maxWidth: AppShellLayout.listColumnMaxWidth,
                    maxHeight: .infinity
                )
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.84))
                .controlSize(.small)

            CraftDetailPaneView(
                graph: graph,
                identityStore: identityStore,
                selection: graph.shell.selection ?? .agentChat
            )
                .frame(minWidth: AppShellLayout.detailColumnMinWidth, maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.12))
                .controlSize(.small)
        }
        }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        isPrimarySidebarVisible.toggle()
                    }
                } label: {
                    Label(isPrimarySidebarVisible ? "隐藏主侧栏" : "显示主侧栏", systemImage: "sidebar.leading")
                }
                .help(isPrimarySidebarVisible ? "隐藏主侧栏" : "显示主侧栏")
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
                    .frame(minWidth: 220, idealWidth: 320, maxWidth: 420, minHeight: 18, idealHeight: 20, maxHeight: 22)
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
                if KnowledgePublicationActivitySummary(store: graph.knowledgeCreator).isVisible {
                    KnowledgePublicationToolbarProgressButton(store: graph.knowledgeCreator) {
                        openWindow(id: AppMenuPresentation.knowledgePublicationProgressWindowID)
                    }
                }

                if noteImportModel.activitySummary.isVisible {
                    NoteImportToolbarProgressButton(summary: noteImportModel.activitySummary) {
                        openWindow(id: AppMenuPresentation.noteImportCenterWindowID)
                    }
                }

                Button { isIdentityPopoverPresented.toggle() } label: {
                    if let user = identityStore.currentUser {
                        IdentityAvatarView(user: user, size: 24)
                    } else {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 20))
                    }
                }
                .buttonStyle(.plain)
                .help(identityStore.currentUser.map { "打开用户菜单，当前用户：\($0.displayName)" } ?? "打开用户菜单，尚未登录")
                .accessibilityLabel(identityStore.currentUser.map { "打开用户菜单，当前用户：\($0.displayName)" } ?? "打开用户菜单，尚未登录")
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
        .overlay(alignment: .top) {
            if graph.globalSearch.isOverlayPresented && (!graph.globalSearch.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !graph.globalSearch.historyEntries.isEmpty) {
                AppGlobalSearchOverlayView(model: graph.globalSearch)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(20)
            }
        }
        .background(WindowTitlebarConfigurator())
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
    }
}
