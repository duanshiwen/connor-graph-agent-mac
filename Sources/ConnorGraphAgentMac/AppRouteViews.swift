import SwiftUI

struct ChatListRouteView: View {
    @Bindable var model: ChatFeatureModel
    @Bindable var governanceModel: GovernanceFeatureModel
    var sessionActions: any ChatSessionCommanding
    var rowActions: ChatSessionListActions

    var body: some View {
        CraftSessionListPane(
            model: model,
            governanceModel: governanceModel,
            sessionActions: sessionActions,
            rowActions: rowActions
        )
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
