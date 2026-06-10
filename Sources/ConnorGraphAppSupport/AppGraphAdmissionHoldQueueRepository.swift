import Foundation
import ConnorGraphCore
import ConnorGraphStore

public struct AppGraphAdmissionHoldQueuePresentation: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String
    public var status: GraphAdmissionHoldQueueStatus
    public var reasons: [GraphWriteAdmissionReason]
    public var recommendedActions: [GraphAdmissionHoldRecommendedAction]
    public var createdAt: Date

    public init(item: GraphAdmissionHoldQueueItem) {
        self.id = item.id
        self.status = item.status
        self.reasons = item.reasons
        self.recommendedActions = item.recommendedActions
        self.createdAt = item.createdAt
        self.title = "\(item.status.rawValue) · \(item.sourceType.rawValue) · \(item.sourceID)"
        let reasonsText = item.reasons.map(\.rawValue).joined(separator: ", ")
        let actionsText = item.recommendedActions.map(\.rawValue).joined(separator: ", ")
        self.detail = "trace: \(item.traceID) · job: \(item.jobID) · reasons: \(reasonsText.isEmpty ? "none" : reasonsText) · actions: \(actionsText.isEmpty ? "none" : actionsText) · \(item.message)"
    }
}

public struct AppGraphAdmissionHoldApprovalResult: Sendable, Equatable {
    public var itemID: String
    public var committedEntityIDs: [String]
    public var committedStatementIDs: [String]
    public var replayTraceID: String

    public init(itemID: String, committedEntityIDs: [String], committedStatementIDs: [String], replayTraceID: String) {
        self.itemID = itemID
        self.committedEntityIDs = committedEntityIDs
        self.committedStatementIDs = committedStatementIDs
        self.replayTraceID = replayTraceID
    }
}

public struct AppGraphAdmissionHoldRerunResult: Sendable, Equatable {
    public var itemID: String
    public var jobID: String
    public var status: GraphJobV3Status

    public init(itemID: String, jobID: String, status: GraphJobV3Status) {
        self.itemID = itemID
        self.jobID = jobID
        self.status = status
    }
}

public struct AppGraphAdmissionHoldEvidenceInspection: Sendable, Equatable {
    public var itemID: String
    public var traceID: String
    public var entityCount: Int
    public var statementCount: Int
    public var evidenceSpanCount: Int
    public var missingEvidenceStatementCount: Int
    public var preview: String

    public init(
        itemID: String,
        traceID: String,
        entityCount: Int,
        statementCount: Int,
        evidenceSpanCount: Int,
        missingEvidenceStatementCount: Int,
        preview: String
    ) {
        self.itemID = itemID
        self.traceID = traceID
        self.entityCount = entityCount
        self.statementCount = statementCount
        self.evidenceSpanCount = evidenceSpanCount
        self.missingEvidenceStatementCount = missingEvidenceStatementCount
        self.preview = preview
    }

    public var summary: String {
        "entities: \(entityCount), statements: \(statementCount), evidence spans: \(evidenceSpanCount), missing evidence statements: \(missingEvidenceStatementCount)\n\(preview)"
    }
}

public struct AppGraphAdmissionHoldQueueRepository: @unchecked Sendable {
    public let store: SQLiteGraphKernelStore
    public var graphID: String
    public var decoder: GraphExtractionDecoder
    public var optimisticWriter: GraphOptimisticWriteService

    public init(
        store: SQLiteGraphKernelStore,
        graphID: String = "default",
        decoder: GraphExtractionDecoder = GraphExtractionDecoder(),
        optimisticWriter: GraphOptimisticWriteService? = nil
    ) {
        self.store = store
        self.graphID = graphID
        self.decoder = decoder
        self.optimisticWriter = optimisticWriter ?? GraphOptimisticWriteService(store: store)
    }

    public func loadOpenItems(limit: Int = 100) throws -> [AppGraphAdmissionHoldQueuePresentation] {
        try store.admissionHoldQueueItems(graphID: graphID, status: .open, limit: limit)
            .map(AppGraphAdmissionHoldQueuePresentation.init(item:))
    }

    public func approveAndCommit(_ itemID: String, now: Date = Date()) throws -> AppGraphAdmissionHoldApprovalResult {
        let item = try requireItem(itemID)
        let trace = try requireTrace(item.traceID)
        let payload = try requireTracePayload(item.traceID)
        let job = try requireJob(item.jobID)
        let source = try GraphExtractionJobPayload(dictionary: job.payload).source
        let draft = try committedDraft(from: payload, source: source)
        let writeResult = try optimisticWriter.commit(try draft.toOptimisticWriteBatch(now: now))
        let approvalTraceID = "trace-\(job.id)-manual-approval-\(Int(now.timeIntervalSince1970 * 1000))"

        try store.appendExtractionTrace(GraphExtractionTrace(
            id: approvalTraceID,
            jobID: job.id,
            graphID: trace.graphID,
            sourceID: trace.sourceID,
            sourceType: trace.sourceType,
            outcome: .committed,
            admissionAction: .autoCommit,
            admissionReasons: [.highConfidenceEvidenceBacked],
            extractedEntityCount: draft.entities.count,
            extractedStatementCount: draft.statements.count,
            committedEntityCount: writeResult.committedEntityIDs.count,
            committedStatementCount: writeResult.committedStatementIDs.count,
            anomalyCount: writeResult.anomalyIDs.count,
            errorMessage: "manual admission hold approval; committed via resolver-backed optimistic writer",
            createdAt: now,
            metadata: [
                "approved_hold_item_id": item.id,
                "approved_from_trace_id": item.traceID,
                "manual_approval": "true"
            ]
        ))
        try store.appendMemoryChangeLogEntry(GraphMemoryChangeLogEntry(
            id: "change-\(approvalTraceID)",
            graphID: trace.graphID,
            action: .extractionCommitted,
            traceID: approvalTraceID,
            jobID: job.id,
            sourceID: trace.sourceID,
            sourceType: trace.sourceType,
            entityIDs: writeResult.committedEntityIDs + Array(writeResult.resolvedEntityIDs.values),
            statementIDs: writeResult.committedStatementIDs,
            anomalyIDs: writeResult.anomalyIDs,
            summary: "manual hold approval committed: \(writeResult.committedEntityIDs.count) entities, \(writeResult.committedStatementIDs.count) statements",
            createdAt: now,
            metadata: [
                "approved_hold_item_id": item.id,
                "approved_from_trace_id": item.traceID,
                "manual_approval": "true"
            ]
        ))

        var resolvedJob = job
        resolvedJob.status = .succeeded
        resolvedJob.updatedAt = now
        resolvedJob.finishedAt = now
        resolvedJob.errorCode = nil
        resolvedJob.errorMessage = nil
        resolvedJob.metadata["resolved_by_hold_action"] = "approve"
        resolvedJob.metadata["resolved_hold_item_id"] = item.id
        try store.upsert(job: resolvedJob)
        try store.updateAdmissionHoldQueueItemStatus(id: item.id, status: .resolved, resolvedAt: now, now: now)
        return AppGraphAdmissionHoldApprovalResult(
            itemID: item.id,
            committedEntityIDs: writeResult.committedEntityIDs,
            committedStatementIDs: writeResult.committedStatementIDs,
            replayTraceID: approvalTraceID
        )
    }

    public func reject(_ itemID: String, now: Date = Date()) throws {
        let item = try requireItem(itemID)
        if var job = try store.job(id: item.jobID) {
            job.status = .cancelled
            job.updatedAt = now
            job.finishedAt = now
            job.errorCode = "admission_hold_rejected"
            job.errorMessage = "Admission hold dismissed by reviewer"
            job.metadata["resolved_by_hold_action"] = "reject"
            job.metadata["resolved_hold_item_id"] = item.id
            try store.upsert(job: job)
        }
        try store.updateAdmissionHoldQueueItemStatus(id: item.id, status: .dismissed, resolvedAt: now, now: now)
    }

    public func rerunExtraction(_ itemID: String, now: Date = Date()) throws -> AppGraphAdmissionHoldRerunResult {
        let item = try requireItem(itemID)
        var job = try requireJob(item.jobID)
        guard job.type == .extraction else { throw AppGraphAdmissionHoldQueueError.unsupportedJobType(job.type) }
        job.status = .queued
        job.updatedAt = now
        job.nextRunAt = now
        job.startedAt = nil
        job.finishedAt = nil
        job.errorCode = nil
        job.errorMessage = nil
        job.metadata["rerun_from_hold_item_id"] = item.id
        job.metadata["rerun_from_trace_id"] = item.traceID
        try store.upsert(job: job)
        try store.updateAdmissionHoldQueueItemStatus(id: item.id, status: .investigating, resolvedAt: nil, now: now)
        return AppGraphAdmissionHoldRerunResult(itemID: item.id, jobID: job.id, status: job.status)
    }

    public func inspectEvidence(_ itemID: String) throws -> AppGraphAdmissionHoldEvidenceInspection {
        let item = try requireItem(itemID)
        let payload = try requireTracePayload(item.traceID)
        let json = try replayJSON(from: payload)
        let decoded = try decoder.decode(json).output
        let missingEvidenceStatements = decoded.statements.filter(\.evidenceSpanIDs.isEmpty)
        let spanPreview = decoded.evidenceSpans.prefix(5).map { span in
            "- \(span.id): \(span.text.prefix(240))"
        }.joined(separator: "\n")
        let statementPreview = decoded.statements.prefix(5).map { statement in
            let evidence = statement.evidenceSpanIDs.isEmpty ? "missing" : statement.evidenceSpanIDs.joined(separator: ",")
            return "- \(statement.subjectLocalID) \(statement.predicate.rawValue) \(statement.objectLocalID) [evidence: \(evidence)]"
        }.joined(separator: "\n")
        let preview = [
            spanPreview.isEmpty ? "evidence spans: none" : "evidence spans:\n\(spanPreview)",
            statementPreview.isEmpty ? "statements: none" : "statements:\n\(statementPreview)"
        ].joined(separator: "\n")
        return AppGraphAdmissionHoldEvidenceInspection(
            itemID: item.id,
            traceID: item.traceID,
            entityCount: decoded.entities.count,
            statementCount: decoded.statements.count,
            evidenceSpanCount: decoded.evidenceSpans.count,
            missingEvidenceStatementCount: missingEvidenceStatements.count,
            preview: preview
        )
    }

    private func committedDraft(from payload: GraphExtractionTracePayload, source: GraphExtractionSource) throws -> GraphExtractionDraft {
        let json = try replayJSON(from: payload)
        let decoded = try decoder.decode(json)
        var draft = try decoded.output.toDraft(source: source, requireStatementEvidence: decoder.requireStatementEvidence)
        let resolutionPlan = try GraphEntityResolutionPlanner(resolver: optimisticWriter.resolver).plan(for: draft)
        let conflictPreview = try GraphExtractionConflictPreflight(store: store, detector: optimisticWriter.contradictionDetector)
            .preview(draft: draft, resolutionPlan: resolutionPlan)
        draft.metadata = [
            "manual_hold_approval": "true",
            "normalized_json": decoded.normalizedJSON
        ]
        draft = draft
            .withEntityResolutionPlanMetadata(resolutionPlan)
            .withConflictPreviewMetadata(conflictPreview)
        return draft
    }

    private func replayJSON(from payload: GraphExtractionTracePayload) throws -> String {
        guard let json = payload.normalizedJSON ?? payload.rawResponseJSON, !json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppGraphAdmissionHoldQueueError.noReplayableJSON(payload.traceID)
        }
        return json
    }

    private func requireItem(_ itemID: String) throws -> GraphAdmissionHoldQueueItem {
        guard let item = try store.admissionHoldQueueItem(id: itemID) else {
            throw AppGraphAdmissionHoldQueueError.itemNotFound(itemID)
        }
        return item
    }

    private func requireTrace(_ traceID: String) throws -> GraphExtractionTrace {
        guard let trace = try store.extractionTrace(id: traceID) else {
            throw AppGraphAdmissionHoldQueueError.traceNotFound(traceID)
        }
        return trace
    }

    private func requireTracePayload(_ traceID: String) throws -> GraphExtractionTracePayload {
        guard let payload = try store.extractionTracePayload(traceID: traceID) else {
            throw AppGraphAdmissionHoldQueueError.payloadNotFound(traceID)
        }
        return payload
    }

    private func requireJob(_ jobID: String) throws -> GraphJobV3 {
        guard let job = try store.job(id: jobID) else {
            throw AppGraphAdmissionHoldQueueError.jobNotFound(jobID)
        }
        return job
    }
}

public enum AppGraphAdmissionHoldQueueError: Error, Sendable, Equatable, CustomStringConvertible {
    case itemNotFound(String)
    case traceNotFound(String)
    case payloadNotFound(String)
    case jobNotFound(String)
    case noReplayableJSON(String)
    case unsupportedJobType(GraphJobV3Type)

    public var description: String {
        switch self {
        case .itemNotFound(let id): return "Admission hold item not found: \(id)"
        case .traceNotFound(let id): return "Extraction trace not found: \(id)"
        case .payloadNotFound(let id): return "Extraction trace payload not found: \(id)"
        case .jobNotFound(let id): return "Graph job not found: \(id)"
        case .noReplayableJSON(let id): return "Trace payload has no replayable JSON: \(id)"
        case .unsupportedJobType(let type): return "Admission hold action does not support job type: \(type.rawValue)"
        }
    }
}
