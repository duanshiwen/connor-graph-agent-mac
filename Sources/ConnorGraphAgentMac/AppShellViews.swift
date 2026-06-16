import SwiftUI
import AppKit
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphSearch
import ConnorGraphAgent
import ConnorGraphStore
import ConnorGraphAppSupport

struct AppShellView: View {
    @StateObject var viewModel: AppViewModel
    @State private var sidebarSelection: SidebarItem? = .agentChat
    @State private var splitViewVisibility: NavigationSplitViewVisibility = .all
    @State private var topSearchKeyMonitor: Any?

    var body: some View {
        NavigationSplitView(columnVisibility: $splitViewVisibility) {
            CraftPrimarySidebarView(viewModel: viewModel, selection: $sidebarSelection)
                .navigationSplitViewColumnWidth(min: 220, ideal: 264, max: 320)
                .background(.bar)
                .controlSize(.small)
        } content: {
            CraftListPaneView(viewModel: viewModel, selection: $sidebarSelection)
                .navigationSplitViewColumnWidth(min: 260, ideal: 314, max: 380)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.84))
                .controlSize(.small)
        } detail: {
            CraftDetailPaneView(viewModel: viewModel, selection: sidebarSelection ?? .agentChat)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.12))
                .controlSize(.small)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TopSearchTextField(
                        text: $viewModel.sessionSearchQuery,
                        placeholder: "搜索会话标题和内容",
                        focusRequestID: viewModel.focusTopSearchRequestID
                    )
                    .frame(minWidth: 220, idealWidth: 320, maxWidth: 420, minHeight: 20, idealHeight: 22, maxHeight: 24)
                    if !viewModel.sessionSearchQuery.isEmpty {
                        Button(action: { viewModel.sessionSearchQuery = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("清除搜索")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
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
        .frame(minWidth: 1120, minHeight: 680)
        .onAppear {
            sidebarSelection = viewModel.selection ?? .agentChat
            viewModel.reloadChatSessions()
            installTopSearchKeyMonitorIfNeeded()
        }
        .onDisappear {
            removeTopSearchKeyMonitor()
        }
        .onChange(of: sidebarSelection) { _, newSelection in
            viewModel.deferViewUpdate {
                viewModel.selection = newSelection
            }
        }
        .onChange(of: viewModel.selection) { _, newSelection in
            if sidebarSelection != newSelection {
                sidebarSelection = newSelection
            }
        }
        .onChange(of: viewModel.runtimeSettingsAutosaveSignature) { _, _ in
            viewModel.scheduleRuntimeSettingsAutosave()
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
