import Foundation
import ConnorGraphCore
import ConnorGraphMemory

public struct GraphExtractionConflictPreview: Sendable, Equatable {
    public var conflicts: [GraphStatementConflict]

    public init(conflicts: [GraphStatementConflict] = []) {
        self.conflicts = conflicts
    }

    public var conflictCount: Int { conflicts.count }
    public var hasConflicts: Bool { !conflicts.isEmpty }

    public var traceMetadata: [String: String] {
        var metadata: [String: String] = [
            "extraction_conflict_count": String(conflictCount)
        ]
        let compact = conflicts.map { conflict in
            [
                conflict.incomingStatementID,
                conflict.existingStatementID,
                conflict.type.rawValue,
                conflict.severity.rawValue
            ].joined(separator: ":")
        }.joined(separator: ",")
        if !compact.isEmpty {
            metadata["extraction_conflict_preview"] = compact
        }
        return metadata
    }
}

public struct GraphExtractionConflictPreflight: Sendable {
    public var store: SQLiteGraphKernelStore
    public var detector: GraphContradictionDetector

    public init(store: SQLiteGraphKernelStore, detector: GraphContradictionDetector = GraphContradictionDetector()) {
        self.store = store
        self.detector = detector
    }

    public func preview(draft: GraphExtractionDraft, resolutionPlan: GraphEntityResolutionPlan, now: Date = Date()) throws -> GraphExtractionConflictPreview {
        let batch = try draft.toOptimisticWriteBatch(now: now)
        let idMap = incomingEntityIDMap(batch: batch, resolutionPlan: resolutionPlan)
        let existing = try store.statements(graphID: batch.graphID, beliefStatus: .active)
        let conflicts = batch.statements.flatMap { statement in
            detector.detect(incoming: rewrite(statement, entityIDMap: idMap), existingActiveStatements: existing)
        }
        return GraphExtractionConflictPreview(conflicts: conflicts)
    }

    private func incomingEntityIDMap(batch: GraphOptimisticWriteBatch, resolutionPlan: GraphEntityResolutionPlan) -> [String: String] {
        var incomingEntityIDByLocalID: [String: String] = [:]
        for entity in batch.entities {
            if let localID = entity.metadata["extraction_local_id"] {
                incomingEntityIDByLocalID[localID] = entity.id
            }
        }

        // GraphExtractionDraft currently generates stable incoming entity IDs from localID.
        // If metadata is not present, reconstruct the same localID-based id shape used by toOptimisticWriteBatch.
        for entry in resolutionPlan.entries where incomingEntityIDByLocalID[entry.localID] == nil {
            incomingEntityIDByLocalID[entry.localID] = "entity-\(batch.graphID)-\(entry.localID.lowercased().replacingOccurrences(of: " ", with: "-"))"
        }

        var map: [String: String] = [:]
        for entry in resolutionPlan.entries {
            guard entry.action == .matched, let matchedEntityID = entry.matchedEntityID, let incomingID = incomingEntityIDByLocalID[entry.localID] else {
                continue
            }
            map[incomingID] = matchedEntityID
        }
        return map
    }

    private func rewrite(_ statement: GraphStatement, entityIDMap: [String: String]) -> GraphStatement {
        var rewritten = statement
        if let subject = entityIDMap[statement.subjectEntityID] {
            rewritten.subjectEntityID = subject
        }
        if let object = entityIDMap[statement.objectEntityID] {
            rewritten.objectEntityID = object
        }
        return rewritten
    }
}

public extension GraphExtractionDraft {
    func withConflictPreviewMetadata(_ preview: GraphExtractionConflictPreview) -> GraphExtractionDraft {
        var copy = self
        for (key, value) in preview.traceMetadata {
            copy.metadata[key] = value
        }
        return copy
    }
}
