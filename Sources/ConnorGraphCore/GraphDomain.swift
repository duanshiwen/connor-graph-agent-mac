import Foundation

public enum NodeType: String, Codable, Sendable, CaseIterable, Equatable {
    case episode
    case entity
    case workObject = "work_object"
    case question
    case answer
    case decision
    case procedure
    case person
    case document
    case preference
    case observation
}

public enum NodeStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case active
    case draft
    case archived
    case superseded
    case dismissed
}

public struct GraphNode: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var type: NodeType
    public var title: String
    public var summary: String
    public var sourcePath: String?
    public var status: NodeStatus
    public var createdAt: Date
    public var validAt: Date?
    public var metadata: [String: String]

    public init(
        id: String,
        type: NodeType,
        title: String,
        summary: String = "",
        sourcePath: String? = nil,
        status: NodeStatus = .active,
        createdAt: Date = Date(),
        validAt: Date? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.summary = summary
        self.sourcePath = sourcePath
        self.status = status
        self.createdAt = createdAt
        self.validAt = validAt
        self.metadata = metadata
    }
}

public extension GraphNode {
    static func question(id: String, title: String, summary: String = "") -> GraphNode {
        GraphNode(id: id, type: .question, title: title, summary: summary)
    }

    static func answer(id: String, title: String, summary: String = "") -> GraphNode {
        GraphNode(id: id, type: .answer, title: title, summary: summary)
    }

    static func workObject(id: String, title: String, summary: String = "") -> GraphNode {
        GraphNode(id: id, type: .workObject, title: title, summary: summary)
    }

    static func decision(id: String, title: String, summary: String = "") -> GraphNode {
        GraphNode(id: id, type: .decision, title: title, summary: summary)
    }

    static func procedure(id: String, title: String, summary: String = "") -> GraphNode {
        GraphNode(id: id, type: .procedure, title: title, summary: summary)
    }

    static func person(id: String, title: String, summary: String = "") -> GraphNode {
        GraphNode(id: id, type: .person, title: title, summary: summary)
    }
}

public enum RelationType: String, Codable, Sendable, CaseIterable, Equatable {
    case belongsTo = "BELONGS_TO"
    case about = "ABOUT"
    case mentions = "MENTIONS"
    case answers = "ANSWERS"
    case answeredBy = "ANSWERED_BY"
    case derivedFrom = "DERIVED_FROM"
    case supportedBy = "SUPPORTED_BY"
    case supersedes = "SUPERSEDES"
    case implements = "IMPLEMENTS"
    case appliesTo = "APPLIES_TO"
    case hasPreference = "HAS_PREFERENCE"
    case worksOn = "WORKS_ON"
    case relatedTo = "RELATED_TO"
    case observedIn = "OBSERVED_IN"
    case promotedFrom = "PROMOTED_FROM"
}

public struct SemanticEdge: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var sourceNodeID: String
    public var targetNodeID: String
    public var relation: RelationType
    public var fact: String
    public var confidence: Double
    public var createdAt: Date
    public var validAt: Date?
    public var invalidAt: Date?
    public var sourceEpisodeID: String?
    public var metadata: [String: String]

    public init(
        id: String,
        sourceNodeID: String,
        targetNodeID: String,
        relation: RelationType,
        fact: String = "",
        confidence: Double = 1.0,
        createdAt: Date = Date(),
        validAt: Date? = nil,
        invalidAt: Date? = nil,
        sourceEpisodeID: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.sourceNodeID = sourceNodeID
        self.targetNodeID = targetNodeID
        self.relation = relation
        self.fact = fact
        self.confidence = confidence
        self.createdAt = createdAt
        self.validAt = validAt
        self.invalidAt = invalidAt
        self.sourceEpisodeID = sourceEpisodeID
        self.metadata = metadata
    }

    public func isActive(at date: Date = Date()) -> Bool {
        if let validAt, date < validAt {
            return false
        }
        if let invalidAt, date >= invalidAt {
            return false
        }
        return true
    }
}

public extension SemanticEdge {
    static func answeredBy(questionID: String, answerID: String) -> SemanticEdge {
        SemanticEdge(
            id: "edge-\(questionID)-answered-by-\(answerID)",
            sourceNodeID: questionID,
            targetNodeID: answerID,
            relation: .answeredBy,
            fact: "\(questionID) is answered by \(answerID)"
        )
    }
}
