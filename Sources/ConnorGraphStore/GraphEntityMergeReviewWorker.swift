import Foundation
import ConnorGraphCore

public enum GraphEntityMergeReviewAction: String, Sendable, Codable, Equatable {
    case merged
    case needsReview = "needs_review"
    case failed
    case skipped
}

public struct GraphEntityMergeReviewResult: Sendable, Equatable, Identifiable {
    public var id: String { jobID }
    public var jobID: String
    public var action: GraphEntityMergeReviewAction
    public var incomingEntityID: String?
    public var existingEntityID: String?
    public var message: String

    public init(jobID: String, action: GraphEntityMergeReviewAction, incomingEntityID: String? = nil, existingEntityID: String? = nil, message: String = "") {
        self.jobID = jobID
        self.action = action
        self.incomingEntityID = incomingEntityID
        self.existingEntityID = existingEntityID
        self.message = message
    }
}

public enum GraphEntityMergeReviewWorkerError: Error, Equatable, CustomStringConvertible {
    case invalidPayload(String)
    case missingEntity(String)
    case incompatibleEntities(String)

    public var description: String {
        switch self {
        case .invalidPayload(let key): "invalidPayload: \(key)"
        case .missingEntity(let id): "missingEntity: \(id)"
        case .incompatibleEntities(let reason): "incompatibleEntities: \(reason)"
        }
    }
}

public struct GraphEntityMergeReviewWorker: Sendable {
    public var store: SQLiteGraphKernelStore
    public var confidenceAutoMergeFloor: Double

    public init(store: SQLiteGraphKernelStore, confidenceAutoMergeFloor: Double = 0.6) {
        self.store = store
        self.confidenceAutoMergeFloor = confidenceAutoMergeFloor
    }

    public func runNext(graphID: String, now: Date = Date()) throws -> GraphEntityMergeReviewResult? {
        guard let job = try store.runnableJobs(graphID: graphID, at: now, limit: 20).first(where: { $0.type == .entityMergeReview }) else {
            return nil
        }
        return try run(job: job, now: now)
    }

    public func run(job: GraphJobV3, now: Date = Date()) throws -> GraphEntityMergeReviewResult {
        let incomingID = job.payload["incoming_entity_id"]
        let existingID = job.payload["existing_entity_id"]
        do {
            guard let incomingID, !incomingID.isEmpty else { throw GraphEntityMergeReviewWorkerError.invalidPayload("incoming_entity_id") }
            guard let existingID, !existingID.isEmpty else { throw GraphEntityMergeReviewWorkerError.invalidPayload("existing_entity_id") }
            guard var incoming = try store.entity(id: incomingID) else { throw GraphEntityMergeReviewWorkerError.missingEntity(incomingID) }
            guard let existing = try store.entity(id: existingID) else { throw GraphEntityMergeReviewWorkerError.missingEntity(existingID) }
            guard incoming.graphID == existing.graphID else { throw GraphEntityMergeReviewWorkerError.incompatibleEntities("graph_id") }
            guard incoming.entityKind == existing.entityKind else { throw GraphEntityMergeReviewWorkerError.incompatibleEntities("entity_kind") }
            guard incoming.scope == existing.scope else { throw GraphEntityMergeReviewWorkerError.incompatibleEntities("scope") }

            if shouldAutoMerge(incoming: incoming, existing: existing) {
                incoming.status = .superseded
                incoming.supersededByEntityID = existing.id
                incoming.updatedAt = now
                incoming.metadata["merge_review_action"] = GraphEntityMergeReviewAction.merged.rawValue
                incoming.metadata["merge_review_existing_entity_id"] = existing.id
                try store.upsert(entity: incoming)
                try mark(job: job, status: .succeeded, now: now)
                return GraphEntityMergeReviewResult(jobID: job.id, action: .merged, incomingEntityID: incoming.id, existingEntityID: existing.id, message: "Incoming entity superseded by existing entity")
            }

            var paused = job
            paused.status = .paused
            paused.updatedAt = now
            paused.finishedAt = now
            paused.errorCode = "manual_review_required"
            paused.errorMessage = "Entity duplicate candidate is ambiguous."
            paused.metadata["review_reason"] = duplicateReason(incoming: incoming, existing: existing)
            try store.upsert(job: paused)
            return GraphEntityMergeReviewResult(jobID: job.id, action: .needsReview, incomingEntityID: incoming.id, existingEntityID: existing.id, message: "Manual review required")
        } catch {
            try mark(job: job, status: .failed, now: now, errorCode: "entity_merge_review_failed", errorMessage: String(describing: error))
            return GraphEntityMergeReviewResult(jobID: job.id, action: .failed, incomingEntityID: incomingID, existingEntityID: existingID, message: String(describing: error))
        }
    }

    private func shouldAutoMerge(incoming: GraphEntity, existing: GraphEntity) -> Bool {
        guard incoming.confidence >= confidenceAutoMergeFloor || existing.confidence >= confidenceAutoMergeFloor else { return false }
        if incoming.stableKey == existing.stableKey { return true }
        let incomingName = GraphStableKeyBuilder.normalized(incoming.name)
        let existingName = GraphStableKeyBuilder.normalized(existing.name)
        if incomingName == existingName { return true }
        let existingAliases = existing.aliases.map(GraphStableKeyBuilder.normalized)
        if existingAliases.contains(incomingName) { return true }
        let incomingAliases = incoming.aliases.map(GraphStableKeyBuilder.normalized)
        if incomingAliases.contains(existingName) { return true }
        return false
    }

    private func duplicateReason(incoming: GraphEntity, existing: GraphEntity) -> String {
        "incoming=\(incoming.name), existing=\(existing.name), same_kind=\(incoming.entityKind == existing.entityKind), same_scope=\(incoming.scope == existing.scope)"
    }

    private func mark(job: GraphJobV3, status: GraphJobV3Status, now: Date, errorCode: String? = nil, errorMessage: String? = nil) throws {
        var updated = job
        updated.status = status
        updated.updatedAt = now
        updated.finishedAt = now
        updated.errorCode = errorCode
        updated.errorMessage = errorMessage
        try store.upsert(job: updated)
    }
}
