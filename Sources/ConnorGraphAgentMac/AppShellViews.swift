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
    @State private var isPrimarySidebarVisible = true

    private var selectionBinding: Binding<SidebarItem?> {
        Binding(
            get: { viewModel.selection ?? .agentChat },
            set: { viewModel.selection = $0 ?? .agentChat }
        )
    }
    @State private var topSearchKeyMonitor: Any?

    var body: some View {
        HSplitView {
            if isPrimarySidebarVisible {
                CraftPrimarySidebarView(viewModel: viewModel, selection: selectionBinding)
                    .frame(
                        minWidth: AppShellLayout.primarySidebarMinWidth,
                        idealWidth: AppShellLayout.primarySidebarDefaultWidth,
                        maxWidth: AppShellLayout.primarySidebarMaxWidth,
                        maxHeight: .infinity
                    )
                    .background(.bar)
                    .controlSize(.small)
            }

            CraftListPaneView(viewModel: viewModel, selection: selectionBinding)
                .frame(
                    minWidth: AppShellLayout.listColumnMinWidth,
                    idealWidth: AppShellLayout.listColumnDefaultWidth,
                    maxWidth: AppShellLayout.listColumnMaxWidth,
                    maxHeight: .infinity
                )
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.84))
                .controlSize(.small)

            CraftDetailPaneView(viewModel: viewModel, selection: viewModel.selection ?? .agentChat)
                .id(viewModel.selection ?? .agentChat)
                .frame(minWidth: AppShellLayout.detailColumnMinWidth, maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.12))
                .controlSize(.small)
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
                            get: { viewModel.globalSearchQuery },
                            set: { viewModel.updateGlobalSearchQuery($0) }
                        ),
                        placeholder: "搜索或发起对话",
                        focusRequestID: viewModel.focusTopSearchRequestID,
                        onSubmit: { viewModel.performSelectedGlobalSearchItem() },
                        onMoveUp: { viewModel.moveGlobalSearchSelectionUp() },
                        onMoveDown: { viewModel.moveGlobalSearchSelectionDown() },
                        onCancel: { viewModel.dismissGlobalSearchOverlay() },
                        onFocus: { viewModel.activateGlobalSearchField() },
                        onBlur: { viewModel.deactivateGlobalSearchField() }
                    )
                    .frame(minWidth: 220, idealWidth: 320, maxWidth: 420, minHeight: 18, idealHeight: 20, maxHeight: 22)
                    if !viewModel.globalSearchQuery.isEmpty {
                        Button(action: { viewModel.clearGlobalSearch() }) {
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

            ToolbarItem(placement: .primaryAction) {
                Button(action: { viewModel.openProjectGitHubHelp() }) {
                    Label("帮助", systemImage: "questionmark.circle")
                }
                .help("用内置浏览器打开项目 GitHub 页面")
            }
        }
        .overlay(alignment: .topLeading) {
            BrowserBackgroundTaskRunnerView(viewModel: viewModel)
        }
        .overlay(alignment: .top) {
            if viewModel.isGlobalSearchOverlayPresented && !viewModel.globalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                AppGlobalSearchOverlayView(viewModel: viewModel)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(20)
            }
        }
        .background(WindowTitlebarConfigurator())
        .frame(minWidth: AppShellLayout.shellMinWidth, minHeight: AppShellLayout.shellMinHeight)
        .onAppear {
            if viewModel.selection == nil {
                viewModel.selection = .agentChat
            }
            viewModel.reloadChatSessionsIfNeededAfterInitialLoad()
            installTopSearchKeyMonitorIfNeeded()
            viewModel.activateRuntimeSettingsSideEffectsAfterLaunch()
        }
        .onDisappear {
            removeTopSearchKeyMonitor()
        }
        .onChange(of: viewModel.runtimeSettingsAutosaveSignature) { _, _ in
            viewModel.scheduleRuntimeSettingsAutosave()
        }
        .onReceive(NotificationCenter.default.publisher(for: .connorSessionNotificationActivated)) { notification in
            guard let sessionID = notification.userInfo?["sessionID"] as? String else { return }
            viewModel.openSessionFromNotification(sessionID)
        }
    }

    private func installTopSearchKeyMonitorIfNeeded() {
        guard topSearchKeyMonitor == nil else { return }
        topSearchKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let shortcut = viewModel.shortcut(for: .focusTopSearch)
            guard shortcut.matches(
                character: event.charactersIgnoringModifiers,
                isCommandDown: event.modifierFlags.contains(.command),
                isShiftDown: event.modifierFlags.contains(.shift),
                isControlDown: event.modifierFlags.contains(.control),
                isOptionDown: event.modifierFlags.contains(.option)
            ) else {
                return event
            }
            viewModel.performShortcutAction(.focusTopSearch)
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
