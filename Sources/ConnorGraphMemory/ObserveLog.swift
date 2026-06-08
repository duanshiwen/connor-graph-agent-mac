import Foundation

public enum ObserveLogKind: String, Codable, Sendable, CaseIterable, Hashable {
    case operation
    case toolEvent = "tool_event"
    case insight
    case fragment
    case observation
    case candidateFact = "candidate_fact"
    case decisionHint = "decision_hint"
    case userPreference = "user_preference"
}

public enum ObserveLogSource: String, Codable, Sendable, CaseIterable, Hashable {
    case user
    case agent
    case tool
    case `import`
    case search
    case system
}

public enum ObserveLogStatus: String, Codable, Sendable, CaseIterable, Hashable {
    case active
    case promoted
    case dismissed
    case expired
}

public struct ObserveLogEntry: Codable, Sendable, Equatable, Identifiable {
    public static let defaultRetention: TimeInterval = 30 * 24 * 60 * 60

    public let id: String
    public var timestamp: Date
    public var kind: ObserveLogKind
    public var source: ObserveLogSource
    public var content: String
    public var normalizedSummary: String
    public var workObjectID: String?
    public var sessionID: String?
    public var relatedNodeIDs: [String]
    public var relatedEdgeIDs: [String]
    public var importance: Double
    public var confidence: Double
    public var status: ObserveLogStatus
    public var expiresAt: Date
    public var promotedNodeID: String?
    public var metadata: [String: String]

    public init(
        id: String,
        timestamp: Date = Date(),
        kind: ObserveLogKind,
        source: ObserveLogSource,
        content: String,
        normalizedSummary: String = "",
        workObjectID: String? = nil,
        sessionID: String? = nil,
        relatedNodeIDs: [String] = [],
        relatedEdgeIDs: [String] = [],
        importance: Double = 0.5,
        confidence: Double = 1.0,
        status: ObserveLogStatus = .active,
        expiresAt: Date? = nil,
        promotedNodeID: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.source = source
        self.content = content
        self.normalizedSummary = normalizedSummary
        self.workObjectID = workObjectID
        self.sessionID = sessionID
        self.relatedNodeIDs = relatedNodeIDs
        self.relatedEdgeIDs = relatedEdgeIDs
        self.importance = importance
        self.confidence = confidence
        self.status = status
        self.expiresAt = expiresAt ?? timestamp.addingTimeInterval(Self.defaultRetention)
        self.promotedNodeID = promotedNodeID
        self.metadata = metadata
    }

    public func promoted(toNodeID nodeID: String) -> ObserveLogEntry {
        var copy = self
        copy.status = .promoted
        copy.promotedNodeID = nodeID
        return copy
    }
}

public enum RollingMemoryClassification: String, Codable, Sendable, Equatable {
    case active
    case expiringSoon
    case expired
}

public struct RollingMemoryPolicy: Sendable, Equatable {
    public var expiringSoonWindow: TimeInterval

    public init(expiringSoonWindow: TimeInterval = 3 * 24 * 60 * 60) {
        self.expiringSoonWindow = expiringSoonWindow
    }

    public func classification(
        for entry: ObserveLogEntry,
        at date: Date = Date()
    ) -> RollingMemoryClassification {
        if entry.expiresAt <= date || entry.status == .expired {
            return .expired
        }
        if entry.expiresAt.timeIntervalSince(date) <= expiringSoonWindow {
            return .expiringSoon
        }
        return .active
    }
}
