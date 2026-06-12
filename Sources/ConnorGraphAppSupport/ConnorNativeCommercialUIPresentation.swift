import Foundation

public enum ConnorNativeCommercialUIStatus: String, Codable, Sendable, Equatable, Hashable {
    case ready
    case needsReview = "needs_review"
    case blocked
}

public enum ConnorNativeCommercialUIRiskLevel: String, Codable, Sendable, Equatable, Hashable {
    case low
    case medium
    case high
}

public enum ConnorNativeCommercialUIActionKind: String, Codable, Sendable, Equatable, Hashable {
    case navigate
    case create
    case review
    case configure
    case verify
}

public struct ConnorNativeCommercialUIHero: Codable, Sendable, Equatable {
    public var title: String
    public var subtitle: String
    public var status: ConnorNativeCommercialUIStatus
    public var statusText: String

    public init(title: String, subtitle: String, status: ConnorNativeCommercialUIStatus, statusText: String) {
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.statusText = statusText
    }
}

public struct ConnorNativeCommercialUIAction: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var kind: ConnorNativeCommercialUIActionKind
    public var riskLevel: ConnorNativeCommercialUIRiskLevel
    public var target: ConnorNativeShellItem
    public var keyboardShortcut: String?
    public var isPrimary: Bool

    public init(id: String, title: String, subtitle: String, kind: ConnorNativeCommercialUIActionKind, riskLevel: ConnorNativeCommercialUIRiskLevel = .low, target: ConnorNativeShellItem, keyboardShortcut: String? = nil, isPrimary: Bool = false) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.riskLevel = riskLevel
        self.target = target
        self.keyboardShortcut = keyboardShortcut
        self.isPrimary = isPrimary
    }
}

public struct ConnorNativeCommercialUIWorkspaceCard: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var target: ConnorNativeShellItem
    public var status: ConnorNativeCommercialUIStatus
    public var riskLevel: ConnorNativeCommercialUIRiskLevel

    public init(id: String, title: String, subtitle: String, target: ConnorNativeShellItem, status: ConnorNativeCommercialUIStatus = .ready, riskLevel: ConnorNativeCommercialUIRiskLevel = .low) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.target = target
        self.status = status
        self.riskLevel = riskLevel
    }
}

public struct ConnorNativeSettingsFieldPresentation: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String
    public var isRequiredForCommercialReadiness: Bool

    public init(id: String, title: String, detail: String, isRequiredForCommercialReadiness: Bool = false) {
        self.id = id
        self.title = title
        self.detail = detail
        self.isRequiredForCommercialReadiness = isRequiredForCommercialReadiness
    }
}

public struct ConnorNativeSettingsSectionPresentation: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var systemImage: String
    public var fields: [ConnorNativeSettingsFieldPresentation]

    public init(id: String, title: String, subtitle: String, systemImage: String, fields: [ConnorNativeSettingsFieldPresentation]) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.fields = fields
    }
}

public struct ConnorNativeSettingsPresentation: Codable, Sendable, Equatable {
    public var sections: [ConnorNativeSettingsSectionPresentation]

    public init(sections: [ConnorNativeSettingsSectionPresentation]) {
        self.sections = sections
    }

    public var commercialReadinessFieldCount: Int {
        sections.flatMap(\.fields).filter(\.isRequiredForCommercialReadiness).count
    }

    public static let `default` = ConnorNativeSettingsPresentation(sections: [
        ConnorNativeSettingsSectionPresentation(id: "app", title: "App", subtitle: "Notifications, browser, local runtime", systemImage: "app.badge", fields: [
            .init(id: "desktopNotifications", title: "Desktop notifications", detail: "Show run and approval notifications"),
            .init(id: "internalBrowser", title: "Internal browser", detail: "Enable the native browser workspace")
        ]),
        ConnorNativeSettingsSectionPresentation(id: "ai", title: "AI", subtitle: "Model provider and Claude SDK sidecar", systemImage: "sparkles", fields: [
            .init(id: "provider", title: "Provider mode", detail: "OpenAI-compatible or Claude SDK sidecar", isRequiredForCommercialReadiness: true),
            .init(id: "model", title: "Model", detail: "Default model selection", isRequiredForCommercialReadiness: true)
        ]),
        ConnorNativeSettingsSectionPresentation(id: "appearance", title: "Appearance", subtitle: "Theme and presentation density", systemImage: "paintpalette", fields: [
            .init(id: "appearanceMode", title: "Appearance mode", detail: "System, light, or dark")
        ]),
        ConnorNativeSettingsSectionPresentation(id: "input", title: "Input", subtitle: "Composer behavior and spelling", systemImage: "keyboard", fields: [
            .init(id: "sendShortcut", title: "Send shortcut", detail: "Return or modifier-based send behavior")
        ]),
        ConnorNativeSettingsSectionPresentation(id: "permissions", title: "Permissions", subtitle: "Connor-owned approval defaults", systemImage: "shield", fields: [
            .init(id: "defaultPermissionMode", title: "Default permission mode", detail: "Read-only, ask-to-write, or allow-all guarded by Connor", isRequiredForCommercialReadiness: true),
            .init(id: "networkApproval", title: "Network approval", detail: "Require review for network actions")
        ]),
        ConnorNativeSettingsSectionPresentation(id: "shortcuts", title: "Shortcuts", subtitle: "Command palette and navigation", systemImage: "command", fields: [
            .init(id: "commandPalette", title: "Command palette", detail: "⌘K global command surface", isRequiredForCommercialReadiness: true)
        ]),
        ConnorNativeSettingsSectionPresentation(id: "preferences", title: "Preferences", subtitle: "User profile and locale", systemImage: "person.crop.circle", fields: [
            .init(id: "profile", title: "User profile", detail: "Name, timezone, city, and preference notes")
        ])
    ])
}

public struct ConnorNativeCommercialUIPresentation: Codable, Sendable, Equatable {
    public var hero: ConnorNativeCommercialUIHero
    public var workspaceCards: [ConnorNativeCommercialUIWorkspaceCard]
    public var primaryActions: [ConnorNativeCommercialUIAction]
    public var settings: ConnorNativeSettingsPresentation
    public var shellItemCount: Int
    public var commandCount: Int
    public var keyboardShortcutCount: Int
    public var emptyStateCount: Int
    public var readinessLinked: Bool

    public init(hero: ConnorNativeCommercialUIHero, workspaceCards: [ConnorNativeCommercialUIWorkspaceCard], primaryActions: [ConnorNativeCommercialUIAction], settings: ConnorNativeSettingsPresentation, shellItemCount: Int, commandCount: Int, keyboardShortcutCount: Int, emptyStateCount: Int, readinessLinked: Bool) {
        self.hero = hero
        self.workspaceCards = workspaceCards
        self.primaryActions = primaryActions
        self.settings = settings
        self.shellItemCount = shellItemCount
        self.commandCount = commandCount
        self.keyboardShortcutCount = keyboardShortcutCount
        self.emptyStateCount = emptyStateCount
        self.readinessLinked = readinessLinked
    }

    public static func build(shell: ConnorNativeShellPresentation = .default, readinessDashboard: CommercialReadinessDashboard? = nil, settings: ConnorNativeSettingsPresentation = .default) -> ConnorNativeCommercialUIPresentation {
        let shellItems = shell.sidebarGroups.flatMap(\.items)
        let blockedReadiness = readinessDashboard?.blockedCount ?? 0
        let status: ConnorNativeCommercialUIStatus = blockedReadiness == 0 ? .ready : .needsReview
        let hero = ConnorNativeCommercialUIHero(
            title: "Connor Home",
            subtitle: "Native Agent OS control center",
            status: status,
            statusText: blockedReadiness == 0 ? "Commercial UI ready" : "\(blockedReadiness) readiness checks need review"
        )
        let workspaceCards = shellItems.filter(\.commercialSurface).map { item in
            ConnorNativeCommercialUIWorkspaceCard(
                id: item.id.rawValue,
                title: item.title,
                subtitle: item.subtitle,
                target: item.id,
                status: item.riskLevel == .high ? .needsReview : .ready,
                riskLevel: item.riskLevel
            )
        }
        let primaryActions = shell.commands.filter(\.isPrimaryAction).map { command in
            ConnorNativeCommercialUIAction(
                id: command.id.rawValue,
                title: command.title,
                subtitle: command.groupID,
                kind: command.id == .newSession ? .create : (command.id == .checkCommercialReadiness ? .verify : .navigate),
                riskLevel: command.riskLevel,
                target: command.target,
                keyboardShortcut: command.keyboardShortcut,
                isPrimary: command.isPrimaryAction
            )
        }
        return ConnorNativeCommercialUIPresentation(
            hero: hero,
            workspaceCards: workspaceCards,
            primaryActions: primaryActions,
            settings: settings,
            shellItemCount: shellItems.count,
            commandCount: shell.commands.count,
            keyboardShortcutCount: shell.commands.filter { $0.keyboardShortcut != nil }.count,
            emptyStateCount: shellItems.filter { $0.emptyStateTitle != nil }.count,
            readinessLinked: readinessDashboard != nil
        )
    }
}
