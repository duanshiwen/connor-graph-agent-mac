import Foundation
import Testing
@testable import ConnorGraphAgentMac

struct AppRouteViewDependencyTests {
    @Test func hotRouteRootsHaveNarrowDependencies() throws {
        let source = try String(contentsOf: projectSourceURL(named: "AppRouteViews.swift"), encoding: .utf8)

        #expect(!source.contains("AppFeatureGraph"))
        #expect(source.contains("struct ChatListRouteView"))
        #expect(source.contains("struct ChatDetailRouteView"))
        #expect(source.contains("struct MailListRouteView"))
        #expect(source.contains("struct MailDetailRouteView"))
        #expect(source.contains("struct RSSListRouteView"))
        #expect(source.contains("struct RSSDetailRouteView"))
        #expect(!source.contains("AnyView"))
    }

    @Test func paneRoutingUsesNativeSwiftUIWithoutForcedIdentity() throws {
        let source = try String(contentsOf: projectSourceURL(named: "AppRoutePaneViews.swift"), encoding: .utf8)
        #expect(!source.contains("RetainedRouteHostView"))
        #expect(!source.contains("NSHostingController"))
        #expect(!source.contains("AnyView"))
        #expect(!source.contains(".id(selection)"))
        #expect(!source.contains(".id(graph.shell.selection)"))
    }

    @Test func listAndDetailSwitchesCoverEverySidebarRoute() throws {
        let source = try String(contentsOf: projectSourceURL(named: "AppRoutePaneViews.swift"), encoding: .utf8)
        for route in SidebarItem.allCases {
            #expect(source.contains(".\(routeCaseName(route))"))
        }
    }

    private func routeCaseName(_ route: SidebarItem) -> String {
        switch route {
        case .entities: "entities"
        case .search: "search"
        case .observeLog: "observeLog"
        case .agentChat: "agentChat"
        case .promotionQueue: "promotionQueue"
        case .pendingApprovals: "pendingApprovals"
        case .automation: "automation"
        case .scheduledTasks: "scheduledTasks"
        case .eventTriggeredTasks: "eventTriggeredTasks"
        case .productOS: "productOS"
        case .calendar: "calendar"
        case .contacts: "contacts"
        case .mail: "mail"
        case .rss: "rss"
        case .sources: "sources"
        case .skills: "skills"
        case .llmSettings: "llmSettings"
        }
    }
}

private func projectSourceURL(named filename: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/ConnorGraphAgentMac")
        .appendingPathComponent(filename)
}
