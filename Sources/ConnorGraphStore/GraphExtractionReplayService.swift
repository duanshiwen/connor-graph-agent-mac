import Foundation
import ConnorGraphCore

public enum GraphExtractionReplayMode: String, Sendable, Equatable {
    case decodeStoredRawResponse
    case rerunAdmissionOnly
}

public struct GraphExtractionReplayResult: Sendable, Equatable {
    public var originalTraceID: String
    public var replayTraceID: String
    public var mode: GraphExtractionReplayMode
    public var draft: GraphExtractionDraft?
    public var admissionDecision: GraphWriteAdmissionDecision?
    public var errorMessage: String?

    public init(
        originalTraceID: String,
        replayTraceID: String,
        mode: GraphExtractionReplayMode,
        draft: GraphExtractionDraft? = nil,
        admissionDecision: GraphWriteAdmissionDecision? = nil,
        errorMessage: String? = nil
    ) {
        self.originalTraceID = originalTraceID
        self.replayTraceID = replayTraceID
        self.mode = mode
        self.draft = draft
        self.admissionDecision = admissionDecision
        self.errorMessage = errorMessage
    }
}

public struct GraphExtractionReplayService: @unchecked Sendable {
    public var store: SQLiteGraphKernelStore
    public var decoder: GraphExtractionDecoder
    public var admissionPolicy: GraphWriteAdmissionPolicy
    public var resolver: SQLiteGraphEntityResolver

    public init(
        store: SQLiteGraphKernelStore,
        decoder: GraphExtractionDecoder = GraphExtractionDecoder(),
        admissionPolicy: GraphWriteAdmissionPolicy = GraphWriteAdmissionPolicy(),
        resolver: SQLiteGraphEntityResolver? = nil
    ) {
        self.store = store
        self.decoder = decoder
        self.admissionPolicy = admissionPolicy
        self.resolver = resolver ?? SQLiteGraphEntityResolver(store: store)
    }

    public func replay(traceID: String, mode: GraphExtractionReplayMode, now: Date = Date()) throws -> GraphExtractionReplayResult {
        guard let trace = try store.extractionTrace(id: traceID) else {
            throw GraphExtractionReplayError.traceNotFound(traceID)
        }
        guard let payload = try store.extractionTracePayload(traceID: traceID) else {
            throw GraphExtractionReplayError.payloadNotFound(traceID)
        }
        guard let job = try store.job(id: trace.jobID) else {
            throw GraphExtractionReplayError.jobNotFound(trace.jobID)
        }
        let source = try GraphExtractionJobPayload(dictionary: job.payload).source
        let replayTraceID = "trace-\(trace.jobID)-replay-\(mode.rawValue)-\(Int(now.timeIntervalSince1970 * 1000))"

        do {
            let json = try replayJSON(from: payload, mode: mode)
            let decoded = try decoder.decode(json)
            var draft = try decoded.output.toDraft(source: source, requireStatementEvidence: decoder.requireStatementEvidence)
            draft.metadata = [
                "replay_mode": mode.rawValue,
                "replayed_from_trace_id": traceID,
                "normalized_json": decoded.normalizedJSON
            ]
            if !decoded.warnings.isEmpty {
                draft.metadata["decoder_warnings"] = decoded.warnings.joined(separator: ",")
            }
            let resolutionPlan = try GraphEntityResolutionPlanner(resolver: resolver).plan(for: draft)
            let conflictPreview = try GraphExtractionConflictPreflight(store: store).preview(draft: draft, resolutionPlan: resolutionPlan, now: now)
            draft = draft
                .withEntityResolutionPlanMetadata(resolutionPlan)
                .withConflictPreviewMetadata(conflictPreview)
            let decision = try admissionPolicy.decide(draft: draft, resolutionPlan: resolutionPlan, conflictPreview: conflictPreview)
            let outcome = replayOutcome(for: decision.action)
            try store.appendExtractionTrace(GraphExtractionTrace(
                id: replayTraceID,
                jobID: trace.jobID,
                graphID: trace.graphID,
                sourceID: trace.sourceID,
                sourceType: trace.sourceType,
                outcome: outcome,
                admissionAction: decision.action,
                admissionReasons: decision.reasons,
                extractedEntityCount: draft.entities.count,
                extractedStatementCount: draft.statements.count,
                committedEntityCount: 0,
                committedStatementCount: 0,
                anomalyCount: 0,
                errorMessage: decision.action == .autoCommit ? "replay dry run; no graph write committed" : decision.message,
                createdAt: now,
                metadata: [
                    "replay_mode": mode.rawValue,
                    "replayed_from_trace_id": traceID,
                    "admission_message": decision.message,
                    "dry_run": "true"
                ]
                .merging(resolutionPlan.traceMetadata) { current, _ in current }
                .merging(conflictPreview.traceMetadata) { current, _ in current }
            ))
            try store.appendExtractionTracePayload(GraphExtractionTracePayload(
                traceID: replayTraceID,
                rawResponseJSON: payload.rawResponseJSON,
                normalizedJSON: decoded.normalizedJSON,
                createdAt: now,
                metadata: ["replayed_from_trace_id": traceID]
            ))
            return GraphExtractionReplayResult(
                originalTraceID: traceID,
                replayTraceID: replayTraceID,
                mode: mode,
                draft: draft,
                admissionDecision: decision
            )
        } catch {
            let message = String(describing: error)
            try store.appendExtractionTrace(GraphExtractionTrace(
                id: replayTraceID,
                jobID: trace.jobID,
                graphID: trace.graphID,
                sourceID: trace.sourceID,
                sourceType: trace.sourceType,
                outcome: .failed,
                errorMessage: message,
                createdAt: now,
                metadata: [
                    "replay_mode": mode.rawValue,
                    "replayed_from_trace_id": traceID,
                    "dry_run": "true"
                ]
            ))
            try store.appendExtractionTracePayload(GraphExtractionTracePayload(
                traceID: replayTraceID,
                rawResponseJSON: payload.rawResponseJSON,
                normalizedJSON: payload.normalizedJSON,
                decoderErrorKind: "replay_failed",
                decoderErrorMessage: message,
                createdAt: now,
                metadata: ["replayed_from_trace_id": traceID]
            ))
            return GraphExtractionReplayResult(
                originalTraceID: traceID,
                replayTraceID: replayTraceID,
                mode: mode,
                errorMessage: message
            )
        }
    }

    private func replayJSON(from payload: GraphExtractionTracePayload, mode: GraphExtractionReplayMode) throws -> String {
        switch mode {
        case .decodeStoredRawResponse, .rerunAdmissionOnly:
            guard let json = payload.normalizedJSON ?? payload.rawResponseJSON, !json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw GraphExtractionReplayError.noReplayableJSON(payload.traceID)
            }
            return json
        }
    }

    private func replayOutcome(for action: GraphWriteAdmissionDecisionAction) -> GraphExtractionTraceOutcome {
        switch action {
        case .autoCommit: return .committed
        case .hold: return .held
        case .askUser: return .askUser
        case .discard: return .discarded
        }
    }
}

public enum GraphExtractionReplayError: Error, Sendable, Equatable, CustomStringConvertible {
    case traceNotFound(String)
    case payloadNotFound(String)
    case jobNotFound(String)
    case noReplayableJSON(String)

    public var description: String {
        switch self {
        case .traceNotFound(let id): return "traceNotFound: \(id)"
        case .payloadNotFound(let id): return "payloadNotFound: \(id)"
        case .jobNotFound(let id): return "jobNotFound: \(id)"
        case .noReplayableJSON(let id): return "noReplayableJSON: \(id)"
        }
    }
}
