import Foundation

public enum ConnorCommandPaletteEntryKind: String, Codable, Sendable, Equatable, Hashable {
    case command
    case destination
}

public struct ConnorCommandPaletteEntry: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var systemImage: String
    public var keyboardShortcut: String?
    public var target: ConnorNativeShellItem
    public var kind: ConnorCommandPaletteEntryKind
    public var keywords: [String]

    public init(
        id: String,
        title: String,
        subtitle: String,
        systemImage: String,
        keyboardShortcut: String? = nil,
        target: ConnorNativeShellItem,
        kind: ConnorCommandPaletteEntryKind,
        keywords: [String] = []
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.keyboardShortcut = keyboardShortcut
        self.target = target
        self.kind = kind
        self.keywords = keywords
    }

    public func matches(_ query: String) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return true }
        return searchableText.contains(normalized)
    }

    private var searchableText: String {
        ([id, title, subtitle, systemImage, keyboardShortcut ?? "", target.rawValue, kind.rawValue] + keywords)
            .joined(separator: " ")
            .lowercased()
    }
}

public struct ConnorCommandPalettePresentation: Codable, Sendable, Equatable {
    public var entries: [ConnorCommandPaletteEntry]

    public init(entries: [ConnorCommandPaletteEntry]) {
        self.entries = entries
    }

    public func search(_ query: String) -> [ConnorCommandPaletteEntry] {
        entries.filter { $0.matches(query) }
    }

    public static func build(shell: ConnorNativeShellPresentation) -> ConnorCommandPalettePresentation {
        let itemEntries = shell.sidebarGroups.flatMap { group in
            group.items.map { item in
                ConnorCommandPaletteEntry(
                    id: "item.\(item.id.rawValue)",
                    title: item.title,
                    subtitle: "\(group.title) · \(item.subtitle)",
                    systemImage: item.systemImage,
                    target: item.id,
                    kind: .destination,
                    keywords: [group.id, group.title, item.badgeText ?? "", item.badgeStyle.rawValue]
                )
            }
        }

        let commandEntries = shell.commands.map { command in
            ConnorCommandPaletteEntry(
                id: "command.\(command.id.rawValue)",
                title: command.title,
                subtitle: command.keyboardShortcut.map { "Command · \($0)" } ?? "Command",
                systemImage: command.systemImage,
                keyboardShortcut: command.keyboardShortcut,
                target: command.target,
                kind: .command,
                keywords: [command.id.rawValue]
            )
        }

        let entries = (commandEntries + itemEntries).sorted { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind.rawValue < rhs.kind.rawValue }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        return ConnorCommandPalettePresentation(entries: entries)
    }
}
