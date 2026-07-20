import SwiftUI

struct ChatListRouteView: View {
    @Bindable var model: ChatFeatureModel
    @Bindable var governanceModel: GovernanceFeatureModel
    @Bindable var workspaceSettings: WorkspaceSettingsFeatureModel
    @Bindable var browser: BrowserFeatureModel
    var sessionActions: any ChatSessionCommanding
    var rowActions: ChatSessionListActions

    var body: some View {
        VStack(spacing: 0) {
            Picker("列表内容", selection: Binding(
                get: { model.workspaceExplorer.mode },
                set: { model.workspaceExplorer.mode = $0 }
            )) {
                Label("会话", systemImage: "bubble.left.and.bubble.right").tag(ChatListPaneMode.sessions)
                Label("文件", systemImage: "folder").tag(ChatListPaneMode.files)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, AppShellLayout.spaceM)
            .padding(.vertical, AppShellLayout.spaceS)

            Divider()

            switch model.workspaceExplorer.mode {
            case .sessions:
                CraftSessionListPane(
                    model: model,
                    governanceModel: governanceModel,
                    sessionActions: sessionActions,
                    rowActions: rowActions
                )
            case .files:
                WorkspaceFileTreePaneView(
                    model: model.workspaceExplorer,
                    sessionID: model.sessions.selectedSessionID,
                    workingDirectoryPath: workspaceSettings.defaultWorkingDirectoryPath,
                    onOpenHTMLPreview: { node, root in
                        browser.openLocalHTMLPreview(
                            fileURL: node.url,
                            readAccessRootURL: root.url,
                            preferredSessionID: model.sessions.selectedSessionID
                        )
                    }
                )
            }
        }
    }
}

struct ChatDetailRouteView: View {
    @Bindable var model: ChatFeatureModel
    var chatActions: ChatFeatureActions

    var body: some View {
        if model.sessions.selectedSessionID == nil {
            AgentChatNoSelectionDetailView()
        } else {
            AgentChatView(model: model, chatActions: chatActions)
        }
    }
}

struct MailListRouteView: View {
    @Bindable var model: MailFeatureModel

    var body: some View {
        CraftMailListPane(model: model)
    }
}

struct MailDetailRouteView: View {
    @Bindable var model: MailFeatureModel

    var body: some View {
        MailSourceDetailView(model: model)
    }
}

struct RSSListRouteView: View {
    @Bindable var model: RSSFeatureModel

    var body: some View {
        CraftRSSListPane(model: model)
    }
}

struct RSSDetailRouteView: View {
    @Bindable var model: RSSFeatureModel

    var body: some View {
        RSSSourceSettingsView(model: model)
    }
}
