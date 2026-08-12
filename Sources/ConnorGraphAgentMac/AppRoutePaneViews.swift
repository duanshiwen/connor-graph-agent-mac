import SwiftUI
import ConnorGraphAppSupport

struct CraftListPaneView: View {
    let graph: AppFeatureGraph
    @Binding var selection: SidebarItem?

    var body: some View {
        listRouteView(selection ?? .agentChat)
    }

    private var openPeerChat: (Int64) -> Void {
        { peerId in
            guard let im = graph.im else { return }
            Task { await im.openPeerConversation(peerId: peerId) }
            _ = graph.shell.select(.agentChat)
        }
    }

    private func listRouteView(_ route: SidebarItem) -> some View {
        Group {
            switch route {
            case .agentChat:
                ChatListRouteView(
                    model: graph.chat,
                    governanceModel: graph.governance,
                    sessionActions: graph.chatActions.session,
                    rowActions: graph.chatSessionListActions,
                    imModel: graph.im,
                    onAddFriend: { graph.shell.requestAddFriend() }
                )
            case .llmSettings:
                CraftSettingsListPane(shellModel: graph.shell, selection: $selection)
            case .calendar:
                CraftCalendarListPane(model: graph.calendar, forwarding: makeListItemForwarding(graph: graph))
            case .contacts:
                CraftContactsListPane(
                    model: graph.contacts,
                    im: graph.im,
                    onOpenPeerChat: openPeerChat,
                    addFriendRequestID: graph.shell.addFriendRequestID
                )
            case .rss:
                RSSListRouteView(model: graph.rss, forwarding: makeListItemForwarding(graph: graph))
            case .mail:
                MailListRouteView(model: graph.mail, forwarding: makeListItemForwarding(graph: graph))
            case .sources:
                CraftSourceListPane(model: graph.sources)
            case .skills:
                CraftSkillListPane(model: graph.skills)
            case .knowledgeMarketplace:
                CloudKnowledgeMarketplaceListPane(
                    store: graph.knowledgeMarketplace,
                    creatorStore: graph.knowledgeCreator,
                    sessions: graph.chat.sessions.allSessions,
                    sessionActions: graph.chatActions.session
                )
            case .automation, .scheduledTasks:
                CraftTaskAutomationListPane(
                    model: graph.tasks,
                    governanceConfig: graph.governance.config,
                    kind: .scheduled
                )
            case .eventTriggeredTasks:
                CraftTaskAutomationListPane(
                    model: graph.tasks,
                    governanceConfig: graph.governance.config,
                    kind: .eventTriggered
                )
            case .productOS:
                CraftSimpleListPane(
                    title: "Product OS",
                    subtitle: "本地控制面模块",
                    rows: graph.productOS.registry.sources.map(\.displayName)
                        + graph.productOS.registry.skills.map(\.displayName)
                )
            default:
                CraftSimpleListPane(title: route.rawValue, subtitle: "康纳同学工作区", rows: [])
            }
        }
        .background {
            AppRouteActivationSentinel(
                route: route,
                pane: .list,
                tracker: graph.shell.routePerformanceTracker
            )
        }
    }
}

struct CraftDetailPaneView: View {
    let graph: AppFeatureGraph
    @ObservedObject var identityStore: AppUserIdentityStore
    var selection: SidebarItem

    var body: some View {
        detailRouteView(selection)
    }

    private var openPeerChat: (Int64) -> Void {
        { peerId in
            guard let im = graph.im else { return }
            Task { await im.openPeerConversation(peerId: peerId) }
            _ = graph.shell.select(.agentChat)
        }
    }

    private func detailRouteView(_ route: SidebarItem) -> some View {
        Group {
            switch route {
            case .entities:
                GraphEntitiesView(
                    entities: graph.graphDiagnostics.entities,
                    statements: graph.graphDiagnostics.statements,
                    episodes: graph.graphDiagnostics.episodes
                )
            case .search:
                SearchView(model: graph.graphDiagnostics)
            case .observeLog:
                ObserveLogView(entries: graph.graphDiagnostics.observeLogEntries)
            case .agentChat:
                if let im = graph.im, im.selectedConversationId != nil {
                    ImChatDetailView(model: im, chatModel: graph.chat)
                } else {
                    ChatDetailRouteView(model: graph.chat, chatActions: graph.chatActions, imModel: graph.im)
                }
            case .promotionQueue:
                PromotionQueueView(model: graph.graphDiagnostics)
            case .pendingApprovals:
                AgentPendingApprovalReviewView(model: graph.chat, chatActions: graph.chatActions)
            case .automation, .scheduledTasks:
                TaskAutomationDetailPane(model: graph.tasks, kind: .scheduled)
            case .eventTriggeredTasks:
                TaskAutomationDetailPane(model: graph.tasks, kind: .eventTriggered)
            case .productOS:
                ProductOSRegistryView(
                    model: graph.productOS,
                    governanceConfig: graph.governance.config,
                    commercialReadinessDashboard: graph.commercialReadinessDashboard()
                )
            case .calendar:
                CalendarSourceSettingsView(model: graph.calendar)
            case .contacts:
                ContactsSourceSettingsView(
                    model: graph.contacts,
                    im: graph.im,
                    onOpenPeerChat: openPeerChat
                )
            case .mail:
                MailDetailRouteView(model: graph.mail)
            case .rss:
                RSSDetailRouteView(model: graph.rss)
            case .sources:
                SourceRuntimePanelView(model: graph.sources)
            case .skills:
                SkillRuntimePanelView(model: graph.skills)
            case .knowledgeMarketplace:
                CloudKnowledgeMarketplaceDetailPane(
                    store: graph.knowledgeMarketplace,
                    creatorStore: graph.knowledgeCreator,
                    sessions: graph.chat.sessions.allSessions,
                    sessionActions: graph.chatActions.session
                )
            case .llmSettings:
                ConnorSettingsDetailView(graph: graph, identityStore: identityStore)
            }
        }
        .background {
            AppRouteActivationSentinel(
                route: route,
                pane: .detail,
                tracker: graph.shell.routePerformanceTracker
            )
        }
    }
}


// MARK: - 列表项转发上下文

private enum ListItemForwardingError: LocalizedError {
    case imUnavailable

    var errorDescription: String? {
        switch self {
        case .imUnavailable: "IM 功能未就绪，暂时无法转发。"
        }
    }
}

private func makeListItemForwarding(graph: AppFeatureGraph) -> ListItemForwardingContext {
    ListItemForwardingContext(
        destinations: {
            forwardDestinations(
                sessions: graph.chat.sessions.loadAllChatSessionsForForwarding(),
                conversations: graph.im?.conversations ?? []
            )
        },
        send: { bundle, keys in
            guard let im = graph.im else { throw ListItemForwardingError.imUnavailable }
            try await im.forward(bundle: bundle, destinationKeys: keys)
        }
    )
}
