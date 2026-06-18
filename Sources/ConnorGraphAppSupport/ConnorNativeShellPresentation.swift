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
    case mail
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
    case openMailSources
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
            ConnorNativeShellRoute(item: item, legacySidebarID: "graphWriteCandidates")
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
        case .mail:
            ConnorNativeShellRoute(item: item, legacySidebarID: "sources")
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
                ConnorNativeShellSidebarItem(id: .agentChat, title: "Sessions", subtitle: "Graph-backed conversations", systemImage: "message.fill", isPrimary: true, emptyStateTitle: "No sessions yet", emptyStateActionTitle: "New Session"),
                ConnorNativeShellSidebarItem(id: .browserWorkspace, title: "Browser Workspace", subtitle: "In-app browsing surface", systemImage: "globe", emptyStateTitle: "Browser hidden", emptyStateActionTitle: "Toggle Browser")
            ]),
            ConnorNativeShellSidebarGroup(id: "memory", title: "Memory", items: [
                ConnorNativeShellSidebarItem(id: .graphMemory, title: "Graph Memory", subtitle: "Context, feedback, review", systemImage: "brain.head.profile", badgeStyle: .warning, isPrimary: true, riskLevel: .medium, emptyStateTitle: "No memory reviews", emptyStateActionTitle: "Inspect Memory"),
                ConnorNativeShellSidebarItem(id: .search, title: "Search", subtitle: "Hybrid graph retrieval", systemImage: "magnifyingglass"),
                ConnorNativeShellSidebarItem(id: .graphEntities, title: "Graph", subtitle: "Entities, statements, episodes", systemImage: "point.3.connected.trianglepath.dotted")
            ]),
            ConnorNativeShellSidebarGroup(id: "governance", title: "Governance", items: [
                ConnorNativeShellSidebarItem(id: .approvals, title: "Approvals", subtitle: "Permissions and reviews", systemImage: "checkmark.shield", badgeStyle: .warning, isPrimary: true, riskLevel: .high, emptyStateTitle: "No pending approvals", emptyStateActionTitle: "Review Policy"),
                ConnorNativeShellSidebarItem(id: .automation, title: "Automation", subtitle: "Rules, history, rate limits", systemImage: "bolt.badge.clock", badgeStyle: .warning, riskLevel: .medium),
                ConnorNativeShellSidebarItem(id: .localAutomationSurface, title: "Local API / CLI", subtitle: "Scriptable automation surface", systemImage: "terminal", badgeStyle: .info, isPrimary: true, riskLevel: .medium, emptyStateTitle: "No local automation calls", emptyStateActionTitle: "Copy CLI Command"),
                ConnorNativeShellSidebarItem(id: .productOS, title: "Product OS", subtitle: "Registry, labels, readiness", systemImage: "square.grid.2x2", isPrimary: true)
            ]),
            ConnorNativeShellSidebarGroup(id: "extensions", title: "Extensions", items: [
                ConnorNativeShellSidebarItem(id: .mail, title: "Mail", subtitle: "Native mail and contacts", systemImage: "envelope.badge.shield.half.filled", badgeStyle: .info, isPrimary: true, riskLevel: .high, emptyStateTitle: "No mail accounts", emptyStateActionTitle: "Add Mail Account"),
                ConnorNativeShellSidebarItem(id: .sources, title: "Sources", subtitle: "MCP source runtime", systemImage: "externaldrive.connected.to.line.below", riskLevel: .medium),
                ConnorNativeShellSidebarItem(id: .skills, title: "Skills", subtitle: "Governed instruction profiles", systemImage: "sparkles.rectangle.stack")
            ]),
            ConnorNativeShellSidebarGroup(id: "system", title: "System", items: [
                ConnorNativeShellSidebarItem(id: .settings, title: "Settings", subtitle: "Models, policy, appearance", systemImage: "gearshape", isPrimary: true)
            ])
        ],
        commands: [
            ConnorNativeShellCommand(id: .newSession, title: "New Session", systemImage: "square.and.pencil", keyboardShortcut: "⌘N", target: .agentChat, groupID: "work", isPrimaryAction: true, keywords: ["chat", "conversation"]),
            ConnorNativeShellCommand(id: .toggleBrowser, title: "Toggle Browser", systemImage: "globe", keyboardShortcut: "⌘B", target: .browserWorkspace, groupID: "work", keywords: ["browser", "web"]),
            ConnorNativeShellCommand(id: .openGraphMemoryReview, title: "Open Graph Memory", systemImage: "brain.head.profile", keyboardShortcut: "⌘2", target: .graphMemory, groupID: "memory", isPrimaryAction: true, riskLevel: .medium, keywords: ["memory", "review", "graph"]),
            ConnorNativeShellCommand(id: .openApprovals, title: "Open Approvals", systemImage: "checkmark.shield", keyboardShortcut: "⌘3", target: .approvals, groupID: "governance", isPrimaryAction: true, riskLevel: .high, keywords: ["permission", "approval", "policy"]),
            ConnorNativeShellCommand(id: .openSources, title: "Open Sources", systemImage: "externaldrive.connected.to.line.below", keyboardShortcut: "⌘4", target: .sources, groupID: "extensions", keywords: ["mcp", "source", "tools"]),
            ConnorNativeShellCommand(id: .openSkills, title: "Open Skills", systemImage: "sparkles.rectangle.stack", keyboardShortcut: "⌘5", target: .skills, groupID: "extensions", keywords: ["skill", "instruction"]),
            ConnorNativeShellCommand(id: .openAutomation, title: "Open Automation", systemImage: "bolt.badge.clock", keyboardShortcut: "⌘6", target: .automation, groupID: "governance", riskLevel: .medium, keywords: ["automation", "rules"]),
            ConnorNativeShellCommand(id: .openLocalAutomationSurface, title: "Open Local API / CLI", systemImage: "terminal", keyboardShortcut: "⌘7", target: .localAutomationSurface, groupID: "governance", isPrimaryAction: true, riskLevel: .medium, keywords: ["local", "api", "cli", "automation", "script"]),
            ConnorNativeShellCommand(id: .openMailSources, title: "Open Mail", systemImage: "envelope.badge.shield.half.filled", keyboardShortcut: "⌘8", target: .mail, groupID: "extensions", isPrimaryAction: true, riskLevel: .high, keywords: ["mail", "email", "contacts", "imap", "smtp"]),
            ConnorNativeShellCommand(id: .checkCommercialReadiness, title: "Check Commercial Readiness", systemImage: "checkmark.seal", keyboardShortcut: "⌘R", target: .productOS, groupID: "governance", isPrimaryAction: true, riskLevel: .medium, keywords: ["readiness", "release", "commercial"]),
            ConnorNativeShellCommand(id: .openSettings, title: "Open Settings", systemImage: "gearshape", keyboardShortcut: "⌘,", target: .settings, groupID: "system", isPrimaryAction: true, keywords: ["settings", "model", "preferences"])
        ]
    )
}
