import Foundation

public enum ConnorNativeShellItem: String, Codable, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case home
    case agentChat
    case browserWorkspace
    case graphMemory
    case search
    case graphEntities
    case approvals
    case automation
    case localAutomationSurface
    case productOS
    case calendar
    case contacts
    case mail
    case rss
    case sources
    case skills
    case settings

    public var id: String { rawValue }
}

public enum ConnorNativeShellBadgeStyle: String, Codable, Sendable, Equatable {
    case neutral
    case info
    case success
    case warning
    case error
}

public struct ConnorNativeShellSidebarItem: Codable, Sendable, Equatable, Identifiable {
    public var id: ConnorNativeShellItem
    public var title: String
    public var subtitle: String
    public var systemImage: String
    public var badgeText: String?
    public var badgeStyle: ConnorNativeShellBadgeStyle
    public var isPrimary: Bool
    public var commercialSurface: Bool
    public var riskLevel: ConnorNativeCommercialUIRiskLevel
    public var emptyStateTitle: String?
    public var emptyStateActionTitle: String?

    public init(
        id: ConnorNativeShellItem,
        title: String,
        subtitle: String,
        systemImage: String,
        badgeText: String? = nil,
        badgeStyle: ConnorNativeShellBadgeStyle = .neutral,
        isPrimary: Bool = false,
        commercialSurface: Bool = true,
        riskLevel: ConnorNativeCommercialUIRiskLevel = .low,
        emptyStateTitle: String? = nil,
        emptyStateActionTitle: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.badgeText = badgeText
        self.badgeStyle = badgeStyle
        self.isPrimary = isPrimary
        self.commercialSurface = commercialSurface
        self.riskLevel = riskLevel
        self.emptyStateTitle = emptyStateTitle
        self.emptyStateActionTitle = emptyStateActionTitle
    }
}

public struct ConnorNativeShellSidebarGroup: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var items: [ConnorNativeShellSidebarItem]

    public init(id: String, title: String, items: [ConnorNativeShellSidebarItem]) {
        self.id = id
        self.title = title
        self.items = items
    }
}

public enum ConnorNativeShellCommandID: String, Codable, Sendable, Equatable, Hashable, Identifiable {
    case newSession
    case toggleBrowser
    case openGraphMemoryReview
    case openApprovals
    case openSources
    case openSkills
    case openAutomation
    case openLocalAutomationSurface
    case openCalendarSources
    case openContactsSources
    case openMailSources
    case openRSSSources
    case checkCommercialReadiness
    case openSettings

    public var id: String { rawValue }
}

public struct ConnorNativeShellCommand: Codable, Sendable, Equatable, Identifiable {
    public var id: ConnorNativeShellCommandID
    public var title: String
    public var systemImage: String
    public var keyboardShortcut: String?
    public var target: ConnorNativeShellItem
    public var groupID: String
    public var isPrimaryAction: Bool
    public var riskLevel: ConnorNativeCommercialUIRiskLevel
    public var keywords: [String]

    public init(
        id: ConnorNativeShellCommandID,
        title: String,
        systemImage: String,
        keyboardShortcut: String? = nil,
        target: ConnorNativeShellItem,
        groupID: String = "general",
        isPrimaryAction: Bool = false,
        riskLevel: ConnorNativeCommercialUIRiskLevel = .low,
        keywords: [String] = []
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.keyboardShortcut = keyboardShortcut
        self.target = target
        self.groupID = groupID
        self.isPrimaryAction = isPrimaryAction
        self.riskLevel = riskLevel
        self.keywords = keywords
    }
}

public struct ConnorNativeShellRoute: Codable, Sendable, Equatable {
    public var item: ConnorNativeShellItem
    public var legacySidebarID: String
    public var requiresBrowserVisible: Bool
    public var isPlaceholder: Bool
    public var placeholderTitle: String?

    public init(
        item: ConnorNativeShellItem,
        legacySidebarID: String,
        requiresBrowserVisible: Bool = false,
        isPlaceholder: Bool = false,
        placeholderTitle: String? = nil
    ) {
        self.item = item
        self.legacySidebarID = legacySidebarID
        self.requiresBrowserVisible = requiresBrowserVisible
        self.isPlaceholder = isPlaceholder
        self.placeholderTitle = placeholderTitle
    }
}

public struct ConnorNativeShellRouteResolver: Sendable {
    public init() {}

    public func route(for item: ConnorNativeShellItem) -> ConnorNativeShellRoute {
        switch item {
        case .home:
            ConnorNativeShellRoute(item: item, legacySidebarID: "home")
        case .agentChat:
            ConnorNativeShellRoute(item: item, legacySidebarID: "agentChat")
        case .browserWorkspace:
            ConnorNativeShellRoute(item: item, legacySidebarID: "agentChat", requiresBrowserVisible: true)
        case .graphMemory:
            ConnorNativeShellRoute(item: item, legacySidebarID: "memoryOS")
        case .search:
            ConnorNativeShellRoute(item: item, legacySidebarID: "search")
        case .graphEntities:
            ConnorNativeShellRoute(item: item, legacySidebarID: "entities")
        case .approvals:
            ConnorNativeShellRoute(item: item, legacySidebarID: "pendingApprovals")
        case .automation:
            ConnorNativeShellRoute(item: item, legacySidebarID: "automation")
        case .localAutomationSurface:
            ConnorNativeShellRoute(item: item, legacySidebarID: "automation")
        case .productOS:
            ConnorNativeShellRoute(item: item, legacySidebarID: "productOS")
        case .calendar:
            ConnorNativeShellRoute(item: item, legacySidebarID: "calendar")
        case .contacts:
            ConnorNativeShellRoute(item: item, legacySidebarID: "contacts")
        case .mail:
            ConnorNativeShellRoute(item: item, legacySidebarID: "mail")
        case .rss:
            ConnorNativeShellRoute(item: item, legacySidebarID: "rss")
        case .sources:
            ConnorNativeShellRoute(item: item, legacySidebarID: "sources")
        case .skills:
            ConnorNativeShellRoute(item: item, legacySidebarID: "skills")
        case .settings:
            ConnorNativeShellRoute(item: item, legacySidebarID: "llmSettings")
        }
    }
}

public struct ConnorNativeShellPresentation: Codable, Sendable, Equatable {
    public var title: String
    public var defaultSelection: ConnorNativeShellItem
    public var sidebarGroups: [ConnorNativeShellSidebarGroup]
    public var commands: [ConnorNativeShellCommand]

    public init(
        title: String,
        defaultSelection: ConnorNativeShellItem,
        sidebarGroups: [ConnorNativeShellSidebarGroup],
        commands: [ConnorNativeShellCommand]
    ) {
        self.title = title
        self.defaultSelection = defaultSelection
        self.sidebarGroups = sidebarGroups
        self.commands = commands
    }

    public func item(for id: ConnorNativeShellItem) -> ConnorNativeShellSidebarItem? {
        sidebarGroups.lazy.flatMap(\.items).first { $0.id == id }
    }

    public func command(for id: ConnorNativeShellCommandID) -> ConnorNativeShellCommand? {
        commands.first { $0.id == id }
    }

    public static let `default` = ConnorNativeShellPresentation(
        title: "康纳同学",
        defaultSelection: .agentChat,
        sidebarGroups: [
            ConnorNativeShellSidebarGroup(id: "work", title: "Work", items: [
                ConnorNativeShellSidebarItem(id: .agentChat, title: "Sessions", subtitle: "Graph-backed conversations", systemImage: "message.fill", isPrimary: true, emptyStateTitle: "还没有会话", emptyStateActionTitle: "开始新会话"),
                ConnorNativeShellSidebarItem(id: .browserWorkspace, title: "Browser Workspace", subtitle: "In-app browsing surface", systemImage: "globe", emptyStateTitle: "浏览器暂时收起", emptyStateActionTitle: "打开浏览器")
            ]),
            ConnorNativeShellSidebarGroup(id: "memory", title: "Memory", items: [
                ConnorNativeShellSidebarItem(id: .graphMemory, title: "Graph Memory", subtitle: "Context, feedback, review", systemImage: "brain.head.profile", badgeStyle: .warning, isPrimary: true, riskLevel: .medium, emptyStateTitle: "暂无记忆审查", emptyStateActionTitle: "查看记忆"),
                ConnorNativeShellSidebarItem(id: .search, title: "Search", subtitle: "Hybrid graph retrieval", systemImage: "magnifyingglass"),
                ConnorNativeShellSidebarItem(id: .graphEntities, title: "Graph", subtitle: "Entities, statements, episodes", systemImage: "point.3.connected.trianglepath.dotted")
            ]),
            ConnorNativeShellSidebarGroup(id: "governance", title: "Governance", items: [
                ConnorNativeShellSidebarItem(id: .approvals, title: "Approvals", subtitle: "Permissions and reviews", systemImage: "checkmark.shield", badgeStyle: .warning, isPrimary: true, riskLevel: .high, emptyStateTitle: "暂无待审批事项", emptyStateActionTitle: "查看权限策略"),
                ConnorNativeShellSidebarItem(id: .automation, title: "Automation", subtitle: "Rules, history, rate limits", systemImage: "bolt.badge.clock", badgeStyle: .warning, riskLevel: .medium),
                ConnorNativeShellSidebarItem(id: .localAutomationSurface, title: "Local API / CLI", subtitle: "Scriptable automation surface", systemImage: "terminal", badgeStyle: .info, isPrimary: true, riskLevel: .medium, emptyStateTitle: "暂无本地自动化调用", emptyStateActionTitle: "复制 CLI 命令"),
                ConnorNativeShellSidebarItem(id: .productOS, title: "Product OS", subtitle: "Registry, labels, readiness", systemImage: "square.grid.2x2", isPrimary: true)
            ]),
            ConnorNativeShellSidebarGroup(id: "extensions", title: "Extensions", items: [
                ConnorNativeShellSidebarItem(id: .calendar, title: "Calendar", subtitle: "Native schedule source", systemImage: "calendar", badgeStyle: .info, isPrimary: true, riskLevel: .medium, emptyStateTitle: "还没有连接日历", emptyStateActionTitle: "添加账户"),
                ConnorNativeShellSidebarItem(id: .contacts, title: "Contacts", subtitle: "Native contacts source", systemImage: "person.crop.circle.badge", badgeStyle: .info, isPrimary: true, riskLevel: .medium, emptyStateTitle: "还没有连接通讯录", emptyStateActionTitle: "添加账户"),
                ConnorNativeShellSidebarItem(id: .mail, title: "Mail", subtitle: "Native mail data source", systemImage: "envelope", badgeStyle: .info, isPrimary: true, riskLevel: .high, emptyStateTitle: "还没有连接邮箱", emptyStateActionTitle: "添加邮箱"),
                ConnorNativeShellSidebarItem(id: .rss, title: "RSS", subtitle: "Native feed intelligence", systemImage: "dot.radiowaves.left.and.right", badgeStyle: .info, isPrimary: true, riskLevel: .medium, emptyStateTitle: "还没有添加 RSS 源", emptyStateActionTitle: "添加 RSS 源"),
                ConnorNativeShellSidebarItem(id: .sources, title: "Sources", subtitle: "MCP source runtime", systemImage: "externaldrive.connected.to.line.below", riskLevel: .medium),
                ConnorNativeShellSidebarItem(id: .skills, title: "Skills", subtitle: "Governed instruction profiles", systemImage: "sparkles.rectangle.stack")
            ]),
            ConnorNativeShellSidebarGroup(id: "system", title: "System", items: [
                ConnorNativeShellSidebarItem(id: .settings, title: "Settings", subtitle: "Models, policy, appearance", systemImage: "gearshape", isPrimary: true)
            ])
        ],
        commands: [
            ConnorNativeShellCommand(id: .newSession, title: "开始新会话", systemImage: "square.and.pencil", keyboardShortcut: "⌘N", target: .agentChat, groupID: "work", isPrimaryAction: true, keywords: ["chat", "conversation", "会话"]),
            ConnorNativeShellCommand(id: .toggleBrowser, title: "打开浏览器", systemImage: "globe", keyboardShortcut: "⌘B", target: .browserWorkspace, groupID: "work", keywords: ["browser", "web", "浏览器"]),
            ConnorNativeShellCommand(id: .openGraphMemoryReview, title: "Open Graph Memory", systemImage: "brain.head.profile", keyboardShortcut: "⌘2", target: .graphMemory, groupID: "memory", isPrimaryAction: true, riskLevel: .medium, keywords: ["memory", "review", "graph"]),
            ConnorNativeShellCommand(id: .openApprovals, title: "Open Approvals", systemImage: "checkmark.shield", keyboardShortcut: "⌘3", target: .approvals, groupID: "governance", isPrimaryAction: true, riskLevel: .high, keywords: ["permission", "approval", "policy"]),
            ConnorNativeShellCommand(id: .openSources, title: "Open Sources", systemImage: "externaldrive.connected.to.line.below", keyboardShortcut: "⌘4", target: .sources, groupID: "extensions", keywords: ["mcp", "source", "tools"]),
            ConnorNativeShellCommand(id: .openSkills, title: "Open Skills", systemImage: "sparkles.rectangle.stack", keyboardShortcut: "⌘5", target: .skills, groupID: "extensions", keywords: ["skill", "instruction"]),
            ConnorNativeShellCommand(id: .openAutomation, title: "Open Automation", systemImage: "bolt.badge.clock", keyboardShortcut: "⌘6", target: .automation, groupID: "governance", riskLevel: .medium, keywords: ["automation", "rules"]),
            ConnorNativeShellCommand(id: .openLocalAutomationSurface, title: "Open Local API / CLI", systemImage: "terminal", keyboardShortcut: "⌘7", target: .localAutomationSurface, groupID: "governance", isPrimaryAction: true, riskLevel: .medium, keywords: ["local", "api", "cli", "automation", "script"]),
            ConnorNativeShellCommand(id: .openCalendarSources, title: "Open Calendar", systemImage: "calendar", target: .calendar, groupID: "extensions", isPrimaryAction: true, riskLevel: .medium, keywords: ["calendar", "caldav", "events", "schedule"]),
            ConnorNativeShellCommand(id: .openContactsSources, title: "Open Contacts", systemImage: "person.crop.circle.badge", target: .contacts, groupID: "extensions", isPrimaryAction: true, riskLevel: .medium, keywords: ["contacts", "carddav", "people", "address book"]),
            ConnorNativeShellCommand(id: .openMailSources, title: "Open Mail", systemImage: "envelope", target: .mail, groupID: "extensions", isPrimaryAction: true, riskLevel: .high, keywords: ["mail", "email", "imap", "smtp", "inbox"]),
            ConnorNativeShellCommand(id: .openRSSSources, title: "Open RSS", systemImage: "dot.radiowaves.left.and.right", keyboardShortcut: "⌘9", target: .rss, groupID: "extensions", isPrimaryAction: true, riskLevel: .medium, keywords: ["rss", "feed", "atom", "json feed", "opml"]),
            ConnorNativeShellCommand(id: .checkCommercialReadiness, title: "Check Commercial Readiness", systemImage: "checkmark.seal", keyboardShortcut: "⌘R", target: .productOS, groupID: "governance", isPrimaryAction: true, riskLevel: .medium, keywords: ["readiness", "release", "commercial"]),
            ConnorNativeShellCommand(id: .openSettings, title: "Open Settings", systemImage: "gearshape", keyboardShortcut: "⌘,", target: .settings, groupID: "system", isPrimaryAction: true, keywords: ["settings", "model", "preferences"])
        ]
    )
}
