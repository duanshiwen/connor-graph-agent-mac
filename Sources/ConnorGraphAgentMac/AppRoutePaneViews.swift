import SwiftUI
import ConnorGraphAppSupport

struct CraftListPaneView: View {
    let graph: AppFeatureGraph
    @Binding var selection: SidebarItem?

    var body: some View {
        let route = selection ?? .agentChat
        RetainedRouteHostView(
            route: route,
            pane: .list,
            tracker: graph.shell.routePerformanceTracker,
            contentOwner: ObjectIdentifier(graph),
            routeFactory: { route in
                AnyView(listRouteView(route))
            }
        )
    }

    private func listRouteView(_ route: SidebarItem) -> some View {
        Group {
            switch route {
            case .agentChat:
                ChatListRouteView(
                    model: graph.chat,
                    governanceModel: graph.governance,
                    sessionActions: graph.chatActions.session,
                    rowActions: graph.chatSessionListActions
                )
            case .llmSettings:
                CraftSettingsListPane(shellModel: graph.shell, selection: $selection)
            case .calendar:
                CraftCalendarListPane(model: graph.calendar)
            case .contacts:
                CraftContactsListPane(model: graph.contacts)
            case .rss:
                RSSListRouteView(model: graph.rss)
            case .mail:
                MailListRouteView(model: graph.mail)
            case .sources:
                CraftSourceListPane(model: graph.sources)
            case .skills:
                CraftSkillListPane(model: graph.skills)
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
        RetainedRouteHostView(
            route: selection,
            pane: .detail,
            tracker: graph.shell.routePerformanceTracker,
            contentOwner: ObjectIdentifier(graph),
            routeFactory: { route in
                AnyView(detailRouteView(route))
            }
        )
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
                ChatDetailRouteView(model: graph.chat, chatActions: graph.chatActions)
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
                ContactsSourceSettingsView(model: graph.contacts)
            case .mail:
                MailDetailRouteView(model: graph.mail)
            case .rss:
                RSSDetailRouteView(model: graph.rss)
            case .sources:
                SourceRuntimePanelView(model: graph.sources)
            case .skills:
                SkillRuntimePanelView(model: graph.skills)
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
