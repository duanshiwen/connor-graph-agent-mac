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

    @Test func listColumnUsesOneStableWidthAcrossRoutes() throws {
        let shellSource = try String(contentsOf: projectSourceURL(named: "AppShellViews.swift"), encoding: .utf8)
        let designSource = try String(contentsOf: projectSourceURL(named: "AppShellDesignSystem.swift"), encoding: .utf8)

        #expect(shellSource.contains("width: AppShellLayout.listColumnWidth"))
        #expect(!shellSource.contains("listColumnMinWidth"))
        #expect(!shellSource.contains("listColumnMaxWidth"))
        #expect(designSource.contains("static let listColumnWidth: CGFloat = 300"))
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

    @Test func knowledgePublicationProgressViewsBelongToXcodeAppTarget() throws {
        let project = try String(contentsOf: xcodeProjectURL(), encoding: .utf8)
        let sourcePath = "Sources/ConnorGraphAgentMac/KnowledgePublicationProgressViews.swift"

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

    @Test func knowledgeMarketplaceListMatchesNativeListAndPresentsCreatorFromAddButton() throws {
        let source = try String(contentsOf: projectSourceURL(named: "CloudKnowledgeMarketplaceView.swift"), encoding: .utf8)
        let listStart = try #require(source.range(of: "struct CloudKnowledgeMarketplaceListPane: View"))
        let detailStart = try #require(source.range(of: "struct CloudKnowledgeMarketplaceDetailPane: View"))
        let listSource = source[listStart.lowerBound..<detailStart.lowerBound]

        #expect(listSource.contains("AppListPaneHeader(title: \"知识市场\")"))
        #expect(listSource.contains("Image(systemName: \"plus\")"))
        #expect(listSource.contains("Image(systemName: \"clock.arrow.circlepath\")"))
        #expect(listSource.contains("weight: .semibold"))
        #expect(listSource.contains("LazyVStack(alignment: .leading, spacing: AppListCardLayout.spacing)"))
        #expect(listSource.contains(".padding(.horizontal, AppListCardLayout.horizontalInset)"))
        #expect(listSource.contains(".onAppear { store.showHome() }"))
        #expect(!listSource.contains("title: \"市场首页\""))
        #expect(listSource.contains("Color(nsColor: .windowBackgroundColor)"))
        #expect(listSource.contains(".sheet(isPresented: $isPresentingCreator)"))
        #expect(listSource.contains("CloudKnowledgeCreatorView(store: creatorStore, sessions: sessions)"))
        #expect(listSource.contains("creatorStore.prepareForNewKnowledgeBase()"))
        #expect(listSource.contains("KnowledgePublicationHistoryView(store: creatorStore)"))
        #expect(!listSource.contains("store.showPublisher()"))
    }

    @Test func listPaneHeadersCenterTitlesIndependentlyFromTrailingActions() throws {
        let designSystem = try String(contentsOf: projectSourceURL(named: "AppShellDesignSystem.swift"), encoding: .utf8)
        let listPanes = try String(contentsOf: projectSourceURL(named: "AppListDetailPanes.swift"), encoding: .utf8)
        let marketplace = try String(contentsOf: projectSourceURL(named: "CloudKnowledgeMarketplaceView.swift"), encoding: .utf8)
        let sources = try String(contentsOf: projectSourceURL(named: "MCPSourceListViews.swift"), encoding: .utf8)
        let skills = try String(contentsOf: projectSourceURL(named: "SkillManagerListViews.swift"), encoding: .utf8)

        #expect(designSystem.contains("struct AppListPaneHeader<Actions: View>: View"))
        #expect(designSystem.contains("ZStack"))
        #expect(designSystem.contains(".frame(maxWidth: .infinity, alignment: .center)"))
        #expect(listPanes.contains("AppListPaneHeader(title: \"日历\")"))
        #expect(listPanes.contains("AppListPaneHeader(title: \"人际关系\")"))
        #expect(listPanes.contains("AppListPaneHeader(title: kind.title)"))
        #expect(listPanes.contains("AppListPaneHeader(title: \"邮件\")"))
        #expect(listPanes.contains("AppListPaneHeader(title: \"RSS 阅读\")"))
        #expect(marketplace.contains("AppListPaneHeader(title: \"知识市场\")"))
        #expect(sources.contains("AppListPaneHeader(title: \"外部工具连接\""))
        #expect(skills.contains("AppListPaneHeader(title: \"技能\")"))
    }

    @Test func knowledgePublicationHistorySupportsFilteringDetailsAndGuardedRemoval() throws {
        let source = try String(contentsOf: projectSourceURL(named: "KnowledgePublicationProgressViews.swift"), encoding: .utf8)
        let historyStart = try #require(source.range(of: "struct KnowledgePublicationHistoryView: View"))
        let historySource = source[historyStart.lowerBound...]

        #expect(historySource.contains("store.publicationHistory"))
        #expect(historySource.contains("KnowledgePublicationHistoryFilter.allCases"))
        #expect(historySource.contains(".searchable(text: $query"))
        #expect(historySource.contains("store.canRemovePublicationHistory(id: entry.id)"))
        #expect(historySource.contains("store.removePublicationHistory(id: id)"))
        #expect(historySource.contains("不会删除服务端知识库或已经提交的知识"))
    }

    @Test func accountSettingsReuseRuntimeKnowledgeStores() throws {
        let source = try String(contentsOf: projectSourceURL(named: "ConnorSettingsViews.swift"), encoding: .utf8)
        let settingsStart = try #require(source.range(of: "struct ConnorSettingsDetailView: View"))
        let calendarStart = try #require(source.range(of: "struct SettingsCalendarSection: View"))
        let settingsSource = source[settingsStart.lowerBound..<calendarStart.lowerBound]

        #expect(settingsSource.contains("creatorStore: graph.knowledgeCreator"))
        #expect(settingsSource.contains("marketplaceStore: graph.knowledgeMarketplace"))
        #expect(!settingsSource.contains("StateObject(wrappedValue: CloudKnowledgeCreatorStore"))
        #expect(!settingsSource.contains("StateObject(wrappedValue: CloudKnowledgeMarketplaceStore"))
    }

    @Test func knowledgeMarketplaceDetailOnlyShowsHomeOrLibraryAndAllowsOwnerSubscription() throws {
        let source = try String(contentsOf: projectSourceURL(named: "CloudKnowledgeMarketplaceView.swift"), encoding: .utf8)
        let detailStart = try #require(source.range(of: "struct CloudKnowledgeMarketplaceDetailPane: View"))
        let badgeStart = try #require(source.range(of: "struct MarketplaceStatusBadge: View"))
        let detailSource = source[detailStart.lowerBound..<badgeStart.lowerBound]

        #expect(!detailSource.contains("CloudKnowledgeCreatorView"))
        #expect(!detailSource.contains("store.showsPublisher"))
        #expect(!detailSource.contains("if !base.owned"))
        #expect(detailSource.contains("if base.subscribed"))
        #expect(detailSource.contains("store.subscribe(id: base.id)"))
    }

    @Test func knowledgePublicationToolbarButtonOwnsItsDynamicVisibility() throws {
        let shellSource = try String(contentsOf: projectSourceURL(named: "AppShellViews.swift"), encoding: .utf8)
        let progressSource = try String(contentsOf: projectSourceURL(named: "KnowledgePublicationProgressViews.swift"), encoding: .utf8)

        #expect(shellSource.contains("KnowledgePublicationToolbarProgressButton(store: graph.knowledgeCreator)"))
        #expect(!shellSource.contains("if KnowledgePublicationActivitySummary(store: graph.knowledgeCreator).isVisible"))
        #expect(progressSource.contains("@ObservedObject var store: CloudKnowledgeCreatorStore"))
        #expect(progressSource.contains("if summary.isVisible"))
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
