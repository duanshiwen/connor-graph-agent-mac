import SwiftUI

struct ChatListRouteView: View {
    @Bindable var model: ChatFeatureModel
    @Bindable var governanceModel: GovernanceFeatureModel
    var sessionActions: any ChatSessionCommanding
    var rowActions: ChatSessionListActions
    var imModel: ImFeatureModel?

    var body: some View {
        CraftSessionListPane(
            model: model,
            governanceModel: governanceModel,
            sessionActions: sessionActions,
            rowActions: rowActions,
            imModel: imModel
        )
        .onChange(of: model.sessions.selectedSessionID) { _, newValue in
            // Selecting an AI session dismisses the IM chat detail overlay.
            if newValue != nil, let imModel, imModel.selectedConversationId != nil {
                Task { await imModel.selectConversation(nil) }
            }
        }
    }
}

struct ChatDetailRouteView: View {
    @Bindable var model: ChatFeatureModel
    var chatActions: ChatFeatureActions
    var imModel: ImFeatureModel?

    var body: some View {
        if model.sessions.selectedSessionID == nil {
            AgentChatNoSelectionDetailView()
        } else {
            AgentChatView(model: model, chatActions: chatActions, imModel: imModel)
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
