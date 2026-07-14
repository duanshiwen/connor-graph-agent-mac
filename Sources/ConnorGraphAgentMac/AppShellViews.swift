import SwiftUI
import AppKit
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphSearch
import ConnorGraphAgent
import ConnorGraphStore
import ConnorGraphAppSupport

struct AppShellView: View {
    @ObservedObject var viewModel: AppViewModel
    @Bindable var shellModel: AppShellFeatureModel
    @ObservedObject var identityStore: AppUserIdentityStore
    @ObservedObject var noteImportModel: NoteImportViewModel
    var sendCommand: (AppCommand) -> Void
    @Environment(\.openWindow) private var openWindow
    @State private var isPrimarySidebarVisible = true
    @State private var isIdentityPopoverPresented = false

    private var selectionBinding: Binding<SidebarItem?> {
        Binding(
            get: { shellModel.selection ?? .agentChat },
            set: { shellModel.selection = $0 ?? .agentChat }
        )
    }
    @State private var topSearchKeyMonitor: Any?

    var body: some View {
        Group {
            if viewModel.aiConnectionsModel.showsWelcome {
                WelcomeLLMView(
                    model: viewModel.aiConnectionsModel,
                    openURL: viewModel.openURLInSystemDefaultBrowser
                )
            } else {
                HSplitView {
                    if isPrimarySidebarVisible {
                        CraftPrimarySidebarView(
                            viewModel: viewModel,
                            shellModel: shellModel,
                            governanceModel: viewModel.governanceModel,
                            sourceRuntimeModel: viewModel.sourceRuntimeModel,
                            skillRuntimeModel: viewModel.skillRuntimeModel,
                            taskAutomationModel: viewModel.taskAutomationModel,
                            calendarFeatureModel: viewModel.calendarFeatureModel,
                            contactsFeatureModel: viewModel.contactsFeatureModel,
                            mailFeatureModel: viewModel.mailFeatureModel,
                            rssFeatureModel: viewModel.rssFeatureModel,
                            selection: selectionBinding
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
                viewModel: viewModel,
                shellModel: shellModel,
                governanceModel: viewModel.governanceModel,
                sourceRuntimeModel: viewModel.sourceRuntimeModel,
                skillRuntimeModel: viewModel.skillRuntimeModel,
                taskAutomationModel: viewModel.taskAutomationModel,
                productOSControlModel: viewModel.productOSControlModel,
                calendarFeatureModel: viewModel.calendarFeatureModel,
                contactsFeatureModel: viewModel.contactsFeatureModel,
                mailFeatureModel: viewModel.mailFeatureModel,
                rssFeatureModel: viewModel.rssFeatureModel,
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
                viewModel: viewModel,
                shellModel: shellModel,
                governanceModel: viewModel.governanceModel,
                identityStore: identityStore,
                graphDiagnosticsModel: viewModel.graphDiagnosticsModel,
                sourceRuntimeModel: viewModel.sourceRuntimeModel,
                skillRuntimeModel: viewModel.skillRuntimeModel,
                taskAutomationModel: viewModel.taskAutomationModel,
                productOSControlModel: viewModel.productOSControlModel,
                calendarFeatureModel: viewModel.calendarFeatureModel,
                contactsFeatureModel: viewModel.contactsFeatureModel,
                mailFeatureModel: viewModel.mailFeatureModel,
                rssFeatureModel: viewModel.rssFeatureModel,
                selection: shellModel.selection ?? .agentChat
            )
                .id(shellModel.selection ?? .agentChat)
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
                            get: { viewModel.globalSearchFeatureModel.query },
                            set: { viewModel.globalSearchFeatureModel.updateQuery($0) }
                        ),
                        isFocused: Binding(
                            get: { viewModel.globalSearchFeatureModel.isFieldFocused },
                            set: { focused in
                                if focused {
                                    viewModel.globalSearchFeatureModel.activateField()
                                } else {
                                    viewModel.globalSearchFeatureModel.deactivateField()
                                }
                            }
                        ),
                        placeholder: "搜索或发起对话",
                        focusRequestID: shellModel.focusTopSearchRequestID,
                        onSubmit: { viewModel.globalSearchFeatureModel.performSelectedItem() },
                        onMoveUp: { viewModel.globalSearchFeatureModel.moveSelectionUp() },
                        onMoveDown: { viewModel.globalSearchFeatureModel.moveSelectionDown() },
                        onCancel: { viewModel.globalSearchFeatureModel.dismissOverlay() }
                    )
                    .frame(minWidth: 220, idealWidth: 320, maxWidth: 420, minHeight: 18, idealHeight: 20, maxHeight: 22)
                    if !viewModel.globalSearchFeatureModel.query.isEmpty {
                        Button(action: { viewModel.globalSearchFeatureModel.clear() }) {
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
                        shellModel.selectSettingsSection(.identity)
                    }
                }
            }
        }
        .overlay(alignment: .topLeading) {
            BrowserBackgroundTaskRunnerView(model: viewModel.browserFeatureModel)
        }
        .overlay(alignment: .top) {
            if viewModel.globalSearchFeatureModel.isOverlayPresented && (!viewModel.globalSearchFeatureModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !viewModel.globalSearchFeatureModel.historyEntries.isEmpty) {
                AppGlobalSearchOverlayView(model: viewModel.globalSearchFeatureModel)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(20)
            }
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                if viewModel.globalSearchFeatureModel.isFieldFocused {
                    viewModel.globalSearchFeatureModel.deactivateField()
                }
            }
        )
        .background(WindowTitlebarConfigurator())
        .frame(minWidth: AppShellLayout.shellMinWidth, minHeight: AppShellLayout.shellMinHeight)
        .onAppear {
            if shellModel.selection == nil {
                shellModel.selection = .agentChat
            }
            viewModel.reloadChatSessionsIfNeededAfterInitialLoad()
            installTopSearchKeyMonitorIfNeeded()
            viewModel.activateRuntimeSettingsSideEffectsAfterLaunch()
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
            let shortcut = viewModel.inputSettingsModel.shortcut(for: .focusTopSearch)
            guard shortcut.matches(
                character: event.charactersIgnoringModifiers,
                isCommandDown: event.modifierFlags.contains(.command),
                isShiftDown: event.modifierFlags.contains(.shift),
                isControlDown: event.modifierFlags.contains(.control),
                isOptionDown: event.modifierFlags.contains(.option)
            ) else {
                return event
            }
            shellModel.requestTopSearchFocus()
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
