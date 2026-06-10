import Foundation
import ConnorGraphCore

public enum GraphGroundingCheckAction: String, Sendable, Codable, Equatable {
    case verified
    case flagged
    case skipped
    case failed
}

public struct GraphGroundingCheckResult: Sendable, Equatable, Identifiable {
    public var id: String { jobID }
    public var jobID: String
    public var statementID: String?
    public var action: GraphGroundingCheckAction
    public var anomalyID: String?
    public var message: String

    public init(
        jobID: String,
        statementID: String?,
        action: GraphGroundingCheckAction,
        anomalyID: String? = nil,
        message: String = ""
    ) {
        self.jobID = jobID
        self.statementID = statementID
        self.action = action
        self.anomalyID = anomalyID
        self.message = message
    }
}

public struct GraphGroundingCheckWorker: Sendable {
    public var store: SQLiteGraphKernelStore
    public var minimumGroundingStrength: Double

    public init(store: SQLiteGraphKernelStore, minimumGroundingStrength: Double = 0.1) {
        self.store = store
        self.minimumGroundingStrength = minimumGroundingStrength
    }

    public func runNext(graphID: String, now: Date = Date()) throws -> GraphGroundingCheckResult? {
        guard let job = try store.runnableJobs(graphID: graphID, at: now, limit: 20).first(where: { $0.type == .groundingCheck }) else {
            return nil
        }
        return try run(job: job, now: now)
    }

    public func run(job: GraphJobV3, now: Date = Date()) throws -> GraphGroundingCheckResult {
        guard job.type == .groundingCheck else {
            try mark(job: job, status: .failed, now: now, errorCode: "wrong_job_type", errorMessage: "Expected grounding_check job")
            return GraphGroundingCheckResult(jobID: job.id, statementID: nil, action: .failed, message: "Wrong job type")
        }

        let statements = try targetStatements(for: job)
        guard !statements.isEmpty else {
            try mark(job: job, status: .succeeded, now: now)
            return GraphGroundingCheckResult(jobID: job.id, statementID: job.payload["statement_id"], action: .skipped, message: "No active statements to check")
        }

        var flaggedAnomalyIDs: [String] = []
        var verifiedStatementIDs: [String] = []
        for var statement in statements {
            let assessment = assess(statement)
            statement.metadata["grounding_status"] = assessment.isGrounded ? "verified" : "needs_review"
            statement.metadata["grounding_checked_at"] = iso(now)
            statement.metadata["grounding_score"] = String(format: "%.3f", assessment.score)
            if assessment.isGrounded {
                statement.metadata["grounding_reason"] = assessment.reason
                verifiedStatementIDs.append(statement.id)
                try store.upsert(statement: statement)
            } else {
                let anomalyID = stableAnomalyID(statementID: statement.id)
                statement.metadata["grounding_anomaly_id"] = anomalyID
                statement.metadata["grounding_reason"] = assessment.reason
                try store.upsert(statement: statement)
                let anomaly = GraphAnomaly(
                    id: anomalyID,
                    graphID: statement.graphID,
                    anomalyType: .commonSenseViolation,
                    statementID: statement.id,
                    severity: severity(for: statement),
                    status: .open,
                    detectedAt: now,
                    metadata: [
                        "anomaly_subtype": "ungrounded_statement",
                        "detected_by": "GraphGroundingCheckWorker",
                        "grounding_score": String(format: "%.3f", assessment.score),
                        "grounding_reason": assessment.reason,
                        "statement_text": statement.statementText
                    ]
                )
                try store.upsert(anomaly: anomaly)
                try enqueueAnomalyResolutionJob(graphID: statement.graphID, anomalyID: anomalyID, now: now)
                flaggedAnomalyIDs.append(anomalyID)
            }
        }

        if flaggedAnomalyIDs.isEmpty {
            try mark(job: job, status: .succeeded, now: now, metadata: [
                "verified_statement_ids": verifiedStatementIDs.joined(separator: ","),
                "flagged_anomaly_ids": ""
            ])
            return GraphGroundingCheckResult(
                jobID: job.id,
                statementID: singleStatementID(from: statements),
                action: .verified,
                message: "Verified grounding for \(verifiedStatementIDs.count) statement(s)"
            )
        }

        try mark(job: job, status: .succeeded, now: now, metadata: [
            "verified_statement_ids": verifiedStatementIDs.joined(separator: ","),
            "flagged_anomaly_ids": flaggedAnomalyIDs.joined(separator: ",")
        ])
        return GraphGroundingCheckResult(
            jobID: job.id,
            statementID: singleStatementID(from: statements),
            action: .flagged,
            anomalyID: flaggedAnomalyIDs.first,
            message: "Flagged \(flaggedAnomalyIDs.count) ungrounded statement(s) for review"
        )
    }

    private func targetStatements(for job: GraphJobV3) throws -> [GraphStatement] {
        if let statementID = job.payload["statement_id"] {
            guard let statement = try store.statement(id: statementID), statement.graphID == job.graphID, statement.beliefStatus == .active else {
                return []
            }
            return [statement]
        }
        let limit = Int(job.payload["limit"] ?? "50") ?? 50
        return Array(try store.statements(graphID: job.graphID).prefix(limit))
    }

    private func assess(_ statement: GraphStatement) -> (isGrounded: Bool, score: Double, reason: String) {
        if !statement.sourceEpisodeIDs.isEmpty {
            return (true, 1.0, "has_source_episode")
        }
        if statement.justifications.contains(where: { justification in
            justification.strength >= minimumGroundingStrength && justification.evidenceSpan?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }) {
            return (true, 0.9, "has_evidence_span_justification")
        }
        if statement.justifications.contains(where: { $0.type == .externalGrounded && $0.strength >= minimumGroundingStrength }) {
            return (true, 0.8, "has_external_grounding_justification")
        }
        if statement.metadata["evidence_span_ids"]?.isEmpty == false || statement.metadata["evidence_spans"]?.isEmpty == false || statement.metadata["evidence_text"]?.isEmpty == false {
            return (true, 0.7, "has_evidence_metadata")
        }
        return (false, 0.0, "missing_source_episode_or_evidence")
    }

    private func severity(for statement: GraphStatement) -> GraphAnomalySeverity {
        if statement.confidence >= 0.85 { return .medium }
        return .low
    }

    private func enqueueAnomalyResolutionJob(graphID: String, anomalyID: String, now: Date) throws {
        try store.upsert(job: GraphJobV3(
            id: "job-anomaly-resolution-\(anomalyID)",
            graphID: graphID,
            type: .anomalyResolution,
            status: .queued,
            priority: 3,
            payload: ["anomaly_id": anomalyID],
            createdAt: now,
            nextRunAt: now,
            metadata: ["created_by": "GraphGroundingCheckWorker"]
        ))
    }

    private func mark(
        job: GraphJobV3,
        status: GraphJobV3Status,
        now: Date,
        errorCode: String? = nil,
        errorMessage: String? = nil,
        metadata: [String: String] = [:]
    ) throws {
        var updated = job
        updated.status = status
        updated.updatedAt = now
        updated.finishedAt = now
        updated.errorCode = errorCode
        updated.errorMessage = errorMessage
        updated.metadata.merge(metadata) { _, new in new }
        try store.upsert(job: updated)
    }

    private func singleStatementID(from statements: [GraphStatement]) -> String? {
        statements.count == 1 ? statements[0].id : nil
    }

    private func stableAnomalyID(statementID: String) -> String {
        "anomaly-grounding-\(statementID)"
    }

    private func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
