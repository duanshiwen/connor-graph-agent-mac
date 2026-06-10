import Foundation
import ConnorGraphCore

public enum MemoryPromotionError: Error, Equatable, Sendable {
    case unsupportedKind(expected: ObserveLogKind, actual: ObserveLogKind)
    case missingRelatedNodes(required: Int, actual: Int)
    case missingPersonEntity
}

public struct MemoryPromotionResult: Sendable, Equatable {
    public var entities: [GraphEntity]
    public var statements: [GraphStatement]
    public var promotedEntry: ObserveLogEntry

    public init(entities: [GraphEntity], statements: [GraphStatement], promotedEntry: ObserveLogEntry) {
        self.entities = entities
        self.statements = statements
        self.promotedEntry = promotedEntry
    }
}

public struct MemoryPromotionService: Sendable, Equatable {
    public var graphID: String

    public init(graphID: String = "default") {
        self.graphID = graphID
    }

    public func promoteCandidateFact(_ entry: ObserveLogEntry) throws -> MemoryPromotionResult {
        guard entry.kind == .candidateFact else {
            throw MemoryPromotionError.unsupportedKind(expected: .candidateFact, actual: entry.kind)
        }
        guard entry.relatedNodeIDs.count >= 2 else {
            throw MemoryPromotionError.missingRelatedNodes(required: 2, actual: entry.relatedNodeIDs.count)
        }

        let sourceID = entry.relatedNodeIDs[0]
        let targetID = entry.relatedNodeIDs[1]
        let statement = GraphStatement(
            id: "statement-promoted-\(entry.id)",
            graphID: graphID,
            subjectEntityID: sourceID,
            predicate: .relatedTo,
            objectEntityID: targetID,
            statementText: entry.content,
            validAt: entry.timestamp,
            committedAt: entry.timestamp,
            confidence: entry.confidence,
            beliefStatus: .active,
            justifications: [GraphJustification(type: .extracted, source: entry.id, strength: entry.confidence)],
            sourceEpisodeIDs: [entry.id],
            metadata: ["promoted_from": entry.id, "promotion_kind": entry.kind.rawValue]
        )

        return MemoryPromotionResult(entities: [], statements: [statement], promotedEntry: entry.promoted(toNodeID: statement.id))
    }

    public func promoteDecisionHint(_ entry: ObserveLogEntry) throws -> MemoryPromotionResult {
        guard entry.kind == .decisionHint else {
            throw MemoryPromotionError.unsupportedKind(expected: .decisionHint, actual: entry.kind)
        }

        let entity = GraphEntity(
            id: "decision-\(slug(entry.content))",
            graphID: graphID,
            name: entry.content,
            stableKey: "\(GraphScope.project.rawValue):\(GraphEntityKind.entity.rawValue):decision:\(slug(entry.content))",
            entityKind: .entity,
            scope: .project,
            canonicalClassID: "decision",
            summary: entry.normalizedSummary,
            confidence: entry.confidence,
            status: .draft,
            createdAt: entry.timestamp,
            updatedAt: entry.timestamp,
            metadata: ["promoted_from": entry.id, "promotion_kind": entry.kind.rawValue]
        )
        var statements: [GraphStatement] = []
        if let workObjectID = entry.workObjectID {
            statements.append(GraphStatement(
                id: "statement-\(entity.id)-part-of-\(workObjectID)",
                graphID: graphID,
                subjectEntityID: entity.id,
                predicate: .partOf,
                objectEntityID: workObjectID,
                statementText: "\(entity.name) is part of \(workObjectID)",
                validAt: entry.timestamp,
                committedAt: entry.timestamp,
                confidence: entry.confidence,
                beliefStatus: .active,
                justifications: [GraphJustification(type: .extracted, source: entry.id, strength: entry.confidence)],
                sourceEpisodeIDs: [entry.id],
                metadata: ["promoted_from": entry.id]
            ))
        }

        return MemoryPromotionResult(entities: [entity], statements: statements, promotedEntry: entry.promoted(toNodeID: entity.id))
    }

    public func promoteUserPreference(_ entry: ObserveLogEntry) throws -> MemoryPromotionResult {
        guard entry.kind == .userPreference else {
            throw MemoryPromotionError.unsupportedKind(expected: .userPreference, actual: entry.kind)
        }
        guard let personID = entry.relatedNodeIDs.first else {
            throw MemoryPromotionError.missingPersonEntity
        }

        let entity = GraphEntity(
            id: "preference-\(slug(entry.content))",
            graphID: graphID,
            name: entry.content,
            stableKey: "\(GraphScope.personal.rawValue):\(GraphEntityKind.lifeObject.rawValue):preference:\(slug(entry.content))",
            entityKind: .lifeObject,
            scope: .personal,
            canonicalClassID: "preference",
            summary: entry.normalizedSummary,
            confidence: entry.confidence,
            status: .draft,
            createdAt: entry.timestamp,
            updatedAt: entry.timestamp,
            metadata: ["promoted_from": entry.id, "promotion_kind": entry.kind.rawValue]
        )
        let statement = GraphStatement(
            id: "statement-\(personID)-prefers-\(entity.id)",
            graphID: graphID,
            subjectEntityID: personID,
            predicate: .prefers,
            objectEntityID: entity.id,
            statementText: entry.content,
            validAt: entry.timestamp,
            committedAt: entry.timestamp,
            confidence: entry.confidence,
            beliefStatus: .active,
            justifications: [GraphJustification(type: .extracted, source: entry.id, strength: entry.confidence)],
            sourceEpisodeIDs: [entry.id],
            metadata: ["promoted_from": entry.id]
        )

        return MemoryPromotionResult(entities: [entity], statements: [statement], promotedEntry: entry.promoted(toNodeID: entity.id))
    }

    public func dismiss(_ entry: ObserveLogEntry) -> ObserveLogEntry {
        var copy = entry
        copy.status = .dismissed
        copy.promotedNodeID = nil
        return copy
    }

    public func pin(_ entry: ObserveLogEntry, at date: Date = Date(), additionalDays: Int = 30) -> ObserveLogEntry {
        var copy = entry
        copy.status = .active
        copy.expiresAt = date.addingTimeInterval(TimeInterval(additionalDays) * 24 * 60 * 60)
        return copy
    }

    private func slug(_ value: String) -> String {
        GraphStableKeyBuilder.normalized(value).replacingOccurrences(of: "_", with: "-")
    }
}
