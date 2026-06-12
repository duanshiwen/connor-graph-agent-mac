import Foundation

public enum ConnorNativeShellItem: String, Codable, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case agentChat
    case browserWorkspace
    case graphMemory
    case search
    case graphEntities
    case approvals
    case automation
    case productOS
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

    public init(
        id: ConnorNativeShellItem,
        title: String,
        subtitle: String,
        systemImage: String,
        badgeText: String? = nil,
        badgeStyle: ConnorNativeShellBadgeStyle = .neutral
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.badgeText = badgeText
        self.badgeStyle = badgeStyle
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

    public init(
        id: ConnorNativeShellCommandID,
        title: String,
        systemImage: String,
        keyboardShortcut: String? = nil,
        target: ConnorNativeShellItem
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.keyboardShortcut = keyboardShortcut
        self.target = target
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
        case .productOS:
            ConnorNativeShellRoute(item: item, legacySidebarID: "productOS")
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
        title: "Connor",
        defaultSelection: .agentChat,
        sidebarGroups: [
            ConnorNativeShellSidebarGroup(id: "run", title: "Run", items: [
                ConnorNativeShellSidebarItem(id: .agentChat, title: "Sessions", subtitle: "Graph-backed conversations", systemImage: "message.fill"),
                ConnorNativeShellSidebarItem(id: .browserWorkspace, title: "Browser Workspace", subtitle: "In-app browsing surface", systemImage: "globe")
            ]),
            ConnorNativeShellSidebarGroup(id: "memory", title: "Memory", items: [
                ConnorNativeShellSidebarItem(id: .graphMemory, title: "Graph Memory", subtitle: "Review, explain, promote", systemImage: "brain.head.profile", badgeStyle: .warning),
                ConnorNativeShellSidebarItem(id: .search, title: "Search", subtitle: "Hybrid graph retrieval", systemImage: "magnifyingglass"),
                ConnorNativeShellSidebarItem(id: .graphEntities, title: "Graph", subtitle: "Entities, statements, episodes", systemImage: "point.3.connected.trianglepath.dotted")
            ]),
            ConnorNativeShellSidebarGroup(id: "governance", title: "Governance", items: [
                ConnorNativeShellSidebarItem(id: .approvals, title: "Approvals", subtitle: "Permissions and reviews", systemImage: "checkmark.shield", badgeStyle: .warning),
                ConnorNativeShellSidebarItem(id: .automation, title: "Automation", subtitle: "Rules, history, rate limits", systemImage: "bolt.badge.clock", badgeStyle: .warning),
                ConnorNativeShellSidebarItem(id: .productOS, title: "Product OS", subtitle: "Registry, labels, statuses", systemImage: "square.grid.2x2")
            ]),
            ConnorNativeShellSidebarGroup(id: "system", title: "System", items: [
                ConnorNativeShellSidebarItem(id: .sources, title: "Sources", subtitle: "MCP source runtime", systemImage: "externaldrive.connected.to.line.below"),
                ConnorNativeShellSidebarItem(id: .skills, title: "Skills", subtitle: "Governed instruction profiles", systemImage: "sparkles.rectangle.stack"),
                ConnorNativeShellSidebarItem(id: .settings, title: "Settings", subtitle: "Models and runtime", systemImage: "gearshape")
            ])
        ],
        commands: [
            ConnorNativeShellCommand(id: .newSession, title: "New Session", systemImage: "square.and.pencil", keyboardShortcut: "⌘N", target: .agentChat),
            ConnorNativeShellCommand(id: .toggleBrowser, title: "Toggle Browser", systemImage: "globe", keyboardShortcut: "⌘B", target: .browserWorkspace),
            ConnorNativeShellCommand(id: .openGraphMemoryReview, title: "Open Graph Memory", systemImage: "brain.head.profile", keyboardShortcut: "⌘2", target: .graphMemory),
            ConnorNativeShellCommand(id: .openApprovals, title: "Open Approvals", systemImage: "checkmark.shield", keyboardShortcut: "⌘3", target: .approvals),
            ConnorNativeShellCommand(id: .openSources, title: "Open Sources", systemImage: "externaldrive.connected.to.line.below", keyboardShortcut: "⌘4", target: .sources),
            ConnorNativeShellCommand(id: .openSkills, title: "Open Skills", systemImage: "sparkles.rectangle.stack", keyboardShortcut: "⌘5", target: .skills),
            ConnorNativeShellCommand(id: .openAutomation, title: "Open Automation", systemImage: "bolt.badge.clock", keyboardShortcut: "⌘6", target: .automation),
            ConnorNativeShellCommand(id: .checkCommercialReadiness, title: "Check Commercial Readiness", systemImage: "checkmark.seal", target: .productOS),
            ConnorNativeShellCommand(id: .openSettings, title: "Open Settings", systemImage: "gearshape", keyboardShortcut: "⌘,", target: .settings)
        ]
    )
}
