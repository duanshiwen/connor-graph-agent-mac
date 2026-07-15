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

    @Test func routePaneSourceBelongsToXcodeAppTarget() throws {
        let project = try String(contentsOf: xcodeProjectURL(), encoding: .utf8)
        let sourcePath = "Sources/ConnorGraphAgentMac/AppRoutePaneViews.swift"

        #expect(project.contains("\(sourcePath) */ = {isa = PBXFileReference"))
        #expect(project.contains("\(sourcePath) in Sources */ = {isa = PBXBuildFile"))
        #expect(project.components(separatedBy: "\(sourcePath) */,").count - 1 == 1)
        #expect(project.components(separatedBy: "\(sourcePath) in Sources */,").count - 1 == 1)
    }

    @Test func sessionRowDeletionAvailabilityUsesCachedStateWithoutPersistenceIO() throws {
        let source = try String(contentsOf: projectSourceURL(named: "AppRuntimeLifecycle.swift"), encoding: .utf8)
        let start = try #require(source.range(of: "func canDeleteChatSessionFromCachedState"))
        let tail = source[start.lowerBound...]
        let end = try #require(tail.range(of: "func regenerateChatSessionTitle"))
        let implementation = tail[..<end.lowerBound]

        #expect(implementation.contains("hasRunningBackgroundTask"))
        #expect(!implementation.contains("runningBackgroundTasksForDeletionCheck"))
    }

    @Test func mailSidebarCountUsesTheDisplayedMessageTotal() throws {
        let source = try String(contentsOf: projectSourceURL(named: "AppPrimarySidebarView.swift"), encoding: .utf8)
        let start = try #require(source.range(of: "private var mailSidebarCount"))
        let tail = source[start.lowerBound...]
        let end = try #require(tail.range(of: "private var rssUnreadCount"))
        let implementation = tail[..<end.lowerBound]

        #expect(implementation.contains("totalMessageCount"))
        #expect(!implementation.contains("totalUnreadCount"))
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
        case .knowledgeMarketplace: "knowledgeMarketplace"
        case .llmSettings: "llmSettings"
        }
    }
}

private func projectRootURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func projectSourceURL(named filename: String) -> URL {
    projectRootURL()
        .appendingPathComponent("Sources/ConnorGraphAgentMac")
        .appendingPathComponent(filename)
}

private func xcodeProjectURL() -> URL {
    projectRootURL()
        .appendingPathComponent("ConnorGraphAgentMac.xcodeproj/project.pbxproj")
}
