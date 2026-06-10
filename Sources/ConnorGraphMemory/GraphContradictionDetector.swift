import Foundation
import ConnorGraphCore

public struct GraphStatementConflict: Sendable, Equatable, Identifiable {
    public var id: String { "\(incomingStatementID):\(existingStatementID):\(type.rawValue)" }
    public var incomingStatementID: String
    public var existingStatementID: String
    public var type: GraphAnomalyType
    public var severity: GraphAnomalySeverity
    public var reason: String

    public init(incomingStatementID: String, existingStatementID: String, type: GraphAnomalyType, severity: GraphAnomalySeverity, reason: String) {
        self.incomingStatementID = incomingStatementID
        self.existingStatementID = existingStatementID
        self.type = type
        self.severity = severity
        self.reason = reason
    }
}

public struct GraphContradictionDetector: Sendable, Equatable {
    public init() {}

    public func detect(incoming: GraphStatement, existingActiveStatements: [GraphStatement]) -> [GraphStatementConflict] {
        existingActiveStatements.compactMap { existing in
            guard existing.id != incoming.id else { return nil }
            guard existing.graphID == incoming.graphID else { return nil }
            guard existing.subjectEntityID == incoming.subjectEntityID else { return nil }
            guard existing.objectEntityID == incoming.objectEntityID else { return nil }
            guard areMutuallyExclusive(existing.predicate, incoming.predicate) else { return nil }
            return GraphStatementConflict(
                incomingStatementID: incoming.id,
                existingStatementID: existing.id,
                type: .directContradiction,
                severity: .high,
                reason: "Predicate \(incoming.predicate.rawValue) conflicts with existing \(existing.predicate.rawValue) for the same subject/object."
            )
        }
    }

    private func areMutuallyExclusive(_ lhs: GraphPredicate, _ rhs: GraphPredicate) -> Bool {
        switch (lhs, rhs) {
        case (.prefers, .dislikes), (.dislikes, .prefers): true
        case (.completedAt, .postponedTo), (.postponedTo, .completedAt): true
        case (.sameAs, .aliasOf), (.aliasOf, .sameAs): false
        default: false
        }
    }
}
