import Foundation
import ConnorGraphCore

public enum GraphSelfHealingAction: String, Sendable, Codable, Equatable {
    case dismissedIncoming = "dismissed_incoming"
    case acceptedIncoming = "accepted_incoming"
    case needsReview = "needs_review"
    case skipped = "skipped"
}

public struct GraphSelfHealingResult: Sendable, Equatable, Identifiable {
    public var id: String { jobID }
    public var jobID: String
    public var anomalyID: String?
    public var action: GraphSelfHealingAction
    public var message: String

    public init(jobID: String, anomalyID: String?, action: GraphSelfHealingAction, message: String) {
        self.jobID = jobID
        self.anomalyID = anomalyID
        self.action = action
        self.message = message
    }
}

public struct GraphSelfHealingService: Sendable {
    public var store: SQLiteGraphKernelStore
    public var confidenceMargin: Double

    public init(store: SQLiteGraphKernelStore, confidenceMargin: Double = 0.2) {
        self.store = store
        self.confidenceMargin = confidenceMargin
    }

    public func runNext(graphID: String, now: Date = Date()) throws -> GraphSelfHealingResult? {
        guard let job = try store.runnableJobs(graphID: graphID, at: now, limit: 20).first(where: { $0.type == .anomalyResolution }) else {
            return nil
        }
        return try run(job: job, now: now)
    }

    public func run(job: GraphJobV3, now: Date = Date()) throws -> GraphSelfHealingResult {
        guard let anomalyID = job.payload["anomaly_id"], let anomaly = try store.anomaly(id: anomalyID) else {
            try mark(job: job, status: .failed, now: now, errorCode: "missing_anomaly", errorMessage: "Anomaly id missing or not found")
            return GraphSelfHealingResult(jobID: job.id, anomalyID: job.payload["anomaly_id"], action: .skipped, message: "Missing anomaly")
        }

        guard anomaly.status == .open || anomaly.status == .investigating else {
            try mark(job: job, status: .succeeded, now: now)
            return GraphSelfHealingResult(jobID: job.id, anomalyID: anomaly.id, action: .skipped, message: "Anomaly already closed")
        }

        switch anomaly.anomalyType {
        case .directContradiction:
            return try resolveDirectContradiction(job: job, anomaly: anomaly, now: now)
        default:
            var paused = job
            paused.status = .paused
            paused.updatedAt = now
            paused.errorCode = "manual_review_required"
            paused.errorMessage = "No automatic resolver for \(anomaly.anomalyType.rawValue)"
            try store.upsert(job: paused)
            return GraphSelfHealingResult(jobID: job.id, anomalyID: anomaly.id, action: .needsReview, message: "Manual review required")
        }
    }

    private func resolveDirectContradiction(job: GraphJobV3, anomaly: GraphAnomaly, now: Date) throws -> GraphSelfHealingResult {
        guard var incoming = try store.statement(id: anomaly.statementID),
              let relatedID = anomaly.relatedStatementIDs.first,
              var existing = try store.statement(id: relatedID)
        else {
            try mark(job: job, status: .failed, now: now, errorCode: "missing_statement", errorMessage: "Incoming or related statement missing")
            return GraphSelfHealingResult(jobID: job.id, anomalyID: anomaly.id, action: .skipped, message: "Missing statement")
        }

        if incoming.confidence + confidenceMargin < existing.confidence {
            incoming.beliefStatus = .dismissed
            incoming.metadata["self_healing_resolution"] = GraphSelfHealingAction.dismissedIncoming.rawValue
            try store.upsert(statement: incoming)
            try resolve(anomaly: anomaly, action: .dismissedIncoming, now: now)
            try mark(job: job, status: .succeeded, now: now)
            return GraphSelfHealingResult(jobID: job.id, anomalyID: anomaly.id, action: .dismissedIncoming, message: "Dismissed lower-confidence incoming statement")
        }

        if existing.confidence + confidenceMargin < incoming.confidence {
            incoming.beliefStatus = .active
            incoming.supersedesStatementIDs = Array(Set(incoming.supersedesStatementIDs + [existing.id]))
            incoming.metadata["self_healing_resolution"] = GraphSelfHealingAction.acceptedIncoming.rawValue
            existing.beliefStatus = .superseded
            existing.invalidAt = now
            existing.invalidatedByStatementID = incoming.id
            existing.metadata["self_healing_resolution"] = GraphSelfHealingAction.acceptedIncoming.rawValue
            try store.upsert(statement: incoming)
            try store.upsert(statement: existing)
            try resolve(anomaly: anomaly, action: .acceptedIncoming, now: now)
            try mark(job: job, status: .succeeded, now: now)
            return GraphSelfHealingResult(jobID: job.id, anomalyID: anomaly.id, action: .acceptedIncoming, message: "Accepted higher-confidence incoming statement and superseded existing statement")
        }

        var investigating = anomaly
        investigating.status = .investigating
        investigating.resolution["action"] = GraphSelfHealingAction.needsReview.rawValue
        investigating.resolution["reason"] = "Confidence scores are too close for automatic resolution."
        try store.upsert(anomaly: investigating)
        var paused = job
        paused.status = .paused
        paused.updatedAt = now
        paused.errorCode = "ambiguous_confidence"
        paused.errorMessage = "Confidence scores are too close for automatic resolution."
        try store.upsert(job: paused)
        return GraphSelfHealingResult(jobID: job.id, anomalyID: anomaly.id, action: .needsReview, message: "Needs review")
    }

    private func resolve(anomaly: GraphAnomaly, action: GraphSelfHealingAction, now: Date) throws {
        var resolved = anomaly
        resolved.status = .resolved
        resolved.resolvedAt = now
        resolved.resolution["action"] = action.rawValue
        resolved.resolution["resolved_by"] = "GraphSelfHealingService"
        try store.upsert(anomaly: resolved)
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
