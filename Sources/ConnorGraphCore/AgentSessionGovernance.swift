import Foundation

public enum AgentSessionStatus: String, Codable, Sendable, Equatable, CaseIterable, Hashable {
    case todo
    case inProgress = "in_progress"
    case waiting
    case needsReview = "needs_review"
    case done
    case blocked
    case archived

    public var displayName: String {
        switch self {
        case .todo: "待办"
        case .inProgress: "进行中"
        case .waiting: "等待中"
        case .needsReview: "待审阅"
        case .done: "已完成"
        case .blocked: "受阻"
        case .archived: "已归档"
        }
    }
}

public struct AgentSessionStatusDefinition: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var systemImage: String
    public var sortOrder: Int
    public var isTerminal: Bool

    public init(id: String, name: String, systemImage: String = "circle", sortOrder: Int = 0, isTerminal: Bool = false) {
        self.id = id
        self.name = name
        self.systemImage = systemImage
        self.sortOrder = sortOrder
        self.isTerminal = isTerminal
    }

    public static let defaults: [AgentSessionStatusDefinition] = [
        .init(id: AgentSessionStatus.todo.rawValue, name: "待办", systemImage: "circle", sortOrder: 10),
        .init(id: AgentSessionStatus.inProgress.rawValue, name: "进行中", systemImage: "play.circle", sortOrder: 20),
        .init(id: AgentSessionStatus.waiting.rawValue, name: "等待中", systemImage: "clock", sortOrder: 30),
        .init(id: AgentSessionStatus.needsReview.rawValue, name: "待审阅", systemImage: "exclamationmark.bubble", sortOrder: 40),
        .init(id: AgentSessionStatus.blocked.rawValue, name: "受阻", systemImage: "nosign", sortOrder: 50),
        .init(id: AgentSessionStatus.done.rawValue, name: "已完成", systemImage: "checkmark.circle", sortOrder: 60, isTerminal: true),
        .init(id: AgentSessionStatus.archived.rawValue, name: "已归档", systemImage: "archivebox", sortOrder: 70, isTerminal: true)
    ]
}

public struct AgentSessionLabelDefinition: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var colorName: String
    public var systemImage: String

    public init(id: String, name: String, colorName: String = "blue") {
        self.id = id
        self.name = name
        self.colorName = colorName
        self.systemImage = "tag"
    }

    public init(id: String, name: String, colorName: String, systemImage: String) {
        self.id = id
        self.name = name
        self.colorName = colorName
        self.systemImage = systemImage
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case colorName
        case systemImage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        colorName = try container.decodeIfPresent(String.self, forKey: .colorName) ?? "blue"
        systemImage = try container.decodeIfPresent(String.self, forKey: .systemImage) ?? "tag"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(colorName, forKey: .colorName)
        try container.encode(systemImage, forKey: .systemImage)
    }

    public static let defaults: [AgentSessionLabelDefinition] = [
        .init(id: "important", name: "重要", colorName: "orange", systemImage: "star.fill"),
        .init(id: "research", name: "研究", colorName: "purple", systemImage: "doc.text.magnifyingglass"),
        .init(id: "priority", name: "优先级", colorName: "red", systemImage: "flag.fill"),
        .init(id: "due", name: "截止日期", colorName: "yellow", systemImage: "calendar.badge.clock"),
        .init(id: "project", name: "项目", colorName: "green", systemImage: "folder.fill")
    ]
}

public struct AgentSessionLabel: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: String

    public init(id: String) {
        self.id = id
    }
}

public struct AgentSessionGovernanceMetadata: Codable, Sendable, Equatable {
    public var status: AgentSessionStatus
    public var labels: [AgentSessionLabel]
    public var isArchived: Bool
    public var isFlagged: Bool
    public var archivedAt: Date?
    public var deletedAt: Date?

    public init(
        status: AgentSessionStatus = .todo,
        labels: [AgentSessionLabel] = [],
        isArchived: Bool = false,
        isFlagged: Bool = false,
        archivedAt: Date? = nil,
        deletedAt: Date? = nil
    ) {
        self.status = status
        self.labels = labels
        self.isArchived = isArchived
        self.isFlagged = isFlagged
        self.archivedAt = archivedAt
        self.deletedAt = deletedAt
    }

    public var isDeleted: Bool { deletedAt != nil }

    public static let `default` = AgentSessionGovernanceMetadata()
}

public enum AgentSessionListFilter: Sendable, Equatable {
    case status(AgentSessionStatus)
    case label(String)
    case all
}

public struct AgentSessionArtifactDirectories: Sendable, Equatable {
    public var root: URL
    public var state: URL
    public var browser: URL
    public var plans: URL
    public var data: URL
    public var attachments: URL
    public var exports: URL
    public var logs: URL

    public init(root: URL) {
        self.root = root
        self.state = root.appendingPathComponent("state", isDirectory: true)
        self.browser = root.appendingPathComponent("browser", isDirectory: true)
        self.plans = root.appendingPathComponent("plans", isDirectory: true)
        self.data = root.appendingPathComponent("data", isDirectory: true)
        self.attachments = root.appendingPathComponent("attachments", isDirectory: true)
        self.exports = root.appendingPathComponent("exports", isDirectory: true)
        self.logs = root.appendingPathComponent("logs", isDirectory: true)
    }

    public var all: [URL] { [root, state, browser, plans, data, attachments, exports, logs] }
}
