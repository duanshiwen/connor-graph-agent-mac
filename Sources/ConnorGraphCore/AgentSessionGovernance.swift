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
        case .todo: "Todo"
        case .inProgress: "In Progress"
        case .waiting: "Waiting"
        case .needsReview: "Needs Review"
        case .done: "Done"
        case .blocked: "Blocked"
        case .archived: "Archived"
        }
    }
}

public enum AgentSessionLabelValueType: String, Codable, Sendable, Equatable, CaseIterable, Hashable {
    case boolean
    case string
    case number
    case date
    case link
    case graphEntityRef = "graph_entity_ref"
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
        .init(id: AgentSessionStatus.todo.rawValue, name: "Todo", systemImage: "circle", sortOrder: 10),
        .init(id: AgentSessionStatus.inProgress.rawValue, name: "In Progress", systemImage: "play.circle", sortOrder: 20),
        .init(id: AgentSessionStatus.waiting.rawValue, name: "Waiting", systemImage: "clock", sortOrder: 30),
        .init(id: AgentSessionStatus.needsReview.rawValue, name: "Needs Review", systemImage: "exclamationmark.bubble", sortOrder: 40),
        .init(id: AgentSessionStatus.blocked.rawValue, name: "Blocked", systemImage: "nosign", sortOrder: 50),
        .init(id: AgentSessionStatus.done.rawValue, name: "Done", systemImage: "checkmark.circle", sortOrder: 60, isTerminal: true),
        .init(id: AgentSessionStatus.archived.rawValue, name: "Archived", systemImage: "archivebox", sortOrder: 70, isTerminal: true)
    ]
}

public struct AgentSessionLabelDefinition: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var valueType: AgentSessionLabelValueType
    public var colorName: String
    public var graphBindingKind: String?

    public init(id: String, name: String, valueType: AgentSessionLabelValueType = .boolean, colorName: String = "blue", graphBindingKind: String? = nil) {
        self.id = id
        self.name = name
        self.valueType = valueType
        self.colorName = colorName
        self.graphBindingKind = graphBindingKind
    }

    public static let defaults: [AgentSessionLabelDefinition] = [
        .init(id: "important", name: "Important", colorName: "orange"),
        .init(id: "research", name: "Research", colorName: "purple"),
        .init(id: "graph-review", name: "Graph Review", colorName: "teal"),
        .init(id: "priority", name: "Priority", valueType: .number, colorName: "red"),
        .init(id: "due", name: "Due", valueType: .date, colorName: "yellow"),
        .init(id: "project", name: "Project", valueType: .graphEntityRef, colorName: "green", graphBindingKind: "project")
    ]
}

public struct AgentSessionLabel: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: String
    public var value: String?

    public init(id: String, value: String? = nil) {
        self.id = id
        self.value = value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true ? nil : value
    }

    public var stableID: String { value.map { "\(id)::\($0)" } ?? id }
    public var displayText: String { value.map { "\(id): \($0)" } ?? id }
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
