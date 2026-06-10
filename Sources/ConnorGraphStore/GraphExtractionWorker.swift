import Foundation
import ConnorGraphCore

public protocol GraphExtractorProvider: Sendable {
    func extract(from source: GraphExtractionSource) async throws -> GraphExtractionDraft
}

public struct GraphExtractionJobPayload: Sendable, Equatable {
    public var source: GraphExtractionSource

    public init(source: GraphExtractionSource) {
        self.source = source
    }

    public init(dictionary: [String: String]) throws {
        guard let id = dictionary["source_id"], !id.isEmpty else { throw GraphExtractionWorkerError.invalidPayload("source_id") }
        guard let graphID = dictionary["graph_id"], !graphID.isEmpty else { throw GraphExtractionWorkerError.invalidPayload("graph_id") }
        guard let sourceTypeRaw = dictionary["source_type"], let sourceType = GraphExtractionSourceType(rawValue: sourceTypeRaw) else { throw GraphExtractionWorkerError.invalidPayload("source_type") }
        guard let title = dictionary["title"] else { throw GraphExtractionWorkerError.invalidPayload("title") }
        guard let content = dictionary["content"] else { throw GraphExtractionWorkerError.invalidPayload("content") }
        let occurredAt = dictionary["occurred_at"].flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
        let metadata = dictionary
            .filter { $0.key.hasPrefix("metadata.") }
            .reduce(into: [String: String]()) { partial, item in
                partial[String(item.key.dropFirst("metadata.".count))] = item.value
            }
        self.source = GraphExtractionSource(
            id: id,
            graphID: graphID,
            sourceType: sourceType,
            title: title,
            content: content,
            occurredAt: occurredAt,
            sessionID: dictionary["session_id"],
            workObjectID: dictionary["work_object_id"],
            metadata: metadata
        )
    }

    public var dictionary: [String: String] {
        var payload: [String: String] = [
            "source_id": source.id,
            "graph_id": source.graphID,
            "source_type": source.sourceType.rawValue,
            "title": source.title,
            "content": source.content,
            "occurred_at": ISO8601DateFormatter().string(from: source.occurredAt)
        ]
        if let sessionID = source.sessionID { payload["session_id"] = sessionID }
        if let workObjectID = source.workObjectID { payload["work_object_id"] = workObjectID }
        for (key, value) in source.metadata {
            payload["metadata.\(key)"] = value
        }
        return payload
    }
}

public enum GraphExtractionWorkerAction: String, Sendable, Equatable {
    case committed
    case held
    case askUser = "ask_user"
    case discarded
    case failed
    case skipped
}

public struct GraphExtractionWorkerResult: Sendable, Equatable, Identifiable {
    public var id: String { jobID }
    public var jobID: String
    public var action: GraphExtractionWorkerAction
    public var writeResult: GraphOptimisticWriteResult
    public var extractedEntityCount: Int
    public var extractedStatementCount: Int
    public var errorMessage: String?
    public var admissionDecision: GraphWriteAdmissionDecision?

    public init(
        jobID: String,
        action: GraphExtractionWorkerAction,
        writeResult: GraphOptimisticWriteResult = GraphOptimisticWriteResult(),
        extractedEntityCount: Int = 0,
        extractedStatementCount: Int = 0,
        errorMessage: String? = nil,
        admissionDecision: GraphWriteAdmissionDecision? = nil
    ) {
        self.jobID = jobID
        self.action = action
        self.writeResult = writeResult
        self.extractedEntityCount = extractedEntityCount
        self.extractedStatementCount = extractedStatementCount
        self.errorMessage = errorMessage
        self.admissionDecision = admissionDecision
    }
}

public enum GraphExtractionWorkerError: Error, Equatable, CustomStringConvertible {
    case invalidPayload(String)

    public var description: String {
        switch self {
        case .invalidPayload(let key): "invalidPayload: \(key)"
        }
    }
}

public struct GraphExtractionWorker<Extractor: GraphExtractorProvider>: Sendable {
    public var store: SQLiteGraphKernelStore
    public var extractor: Extractor
    public var optimisticWriter: GraphOptimisticWriteService
    public var admissionPolicy: GraphWriteAdmissionPolicy

    public init(
        store: SQLiteGraphKernelStore,
        extractor: Extractor,
        optimisticWriter: GraphOptimisticWriteService? = nil,
        admissionPolicy: GraphWriteAdmissionPolicy = GraphWriteAdmissionPolicy()
    ) {
        self.store = store
        self.extractor = extractor
        self.optimisticWriter = optimisticWriter ?? GraphOptimisticWriteService(store: store)
        self.admissionPolicy = admissionPolicy
    }

    public func runNext(graphID: String, now: Date = Date()) async throws -> GraphExtractionWorkerResult? {
        guard let job = try store.runnableJobs(graphID: graphID, at: now, limit: 20).first(where: { $0.type == .extraction }) else {
            return nil
        }
        return try await run(job: job, now: now)
    }

    public func run(job: GraphJobV3, now: Date = Date()) async throws -> GraphExtractionWorkerResult {
        do {
            let payload = try GraphExtractionJobPayload(dictionary: job.payload)
            let draft = try await extractor.extract(from: payload.source)
            let admission = try admissionPolicy.decide(draft: draft, resolver: optimisticWriter.resolver)
            switch admission.action {
            case .autoCommit:
                let batch = try draft.toOptimisticWriteBatch(now: now)
                let writeResult = try optimisticWriter.commit(batch)
                try appendTrace(job: job, source: payload.source, draft: draft, outcome: .committed, admission: admission, writeResult: writeResult, now: now)
                try mark(job: job, status: .succeeded, now: now)
                return GraphExtractionWorkerResult(
                    jobID: job.id,
                    action: .committed,
                    writeResult: writeResult,
                    extractedEntityCount: draft.entities.count,
                    extractedStatementCount: draft.statements.count,
                    admissionDecision: admission
                )
            case .hold:
                try appendTrace(job: job, source: payload.source, draft: draft, outcome: .held, admission: admission, errorMessage: admission.message, now: now)
                try mark(job: job, status: .paused, now: now, errorCode: "admission_hold", errorMessage: admission.message)
                return GraphExtractionWorkerResult(
                    jobID: job.id,
                    action: .held,
                    extractedEntityCount: draft.entities.count,
                    extractedStatementCount: draft.statements.count,
                    errorMessage: admission.message,
                    admissionDecision: admission
                )
            case .askUser:
                try appendTrace(job: job, source: payload.source, draft: draft, outcome: .askUser, admission: admission, errorMessage: admission.message, now: now)
                try mark(job: job, status: .paused, now: now, errorCode: "admission_ask_user", errorMessage: admission.message)
                return GraphExtractionWorkerResult(
                    jobID: job.id,
                    action: .askUser,
                    extractedEntityCount: draft.entities.count,
                    extractedStatementCount: draft.statements.count,
                    errorMessage: admission.message,
                    admissionDecision: admission
                )
            case .discard:
                try appendTrace(job: job, source: payload.source, draft: draft, outcome: .discarded, admission: admission, errorMessage: admission.message, now: now)
                try mark(job: job, status: .succeeded, now: now, errorCode: "admission_discard", errorMessage: admission.message)
                return GraphExtractionWorkerResult(
                    jobID: job.id,
                    action: .discarded,
                    extractedEntityCount: draft.entities.count,
                    extractedStatementCount: draft.statements.count,
                    errorMessage: admission.message,
                    admissionDecision: admission
                )
            }
        } catch let failure as GraphExtractionAttemptFailure {
            let message = failure.description
            try appendFailureTrace(
                job: job,
                source: failure.source,
                errorMessage: message,
                metadata: failure.traceMetadata,
                now: now
            )
            try mark(job: job, status: .failed, now: now, errorCode: "extraction_failed", errorMessage: message)
            return GraphExtractionWorkerResult(jobID: job.id, action: .failed, errorMessage: message)
        } catch {
            let message = String(describing: error)
            try appendFailureTrace(job: job, errorMessage: message, now: now)
            try mark(job: job, status: .failed, now: now, errorCode: "extraction_failed", errorMessage: message)
            return GraphExtractionWorkerResult(jobID: job.id, action: .failed, errorMessage: message)
        }
    }

    private func appendTrace(
        job: GraphJobV3,
        source: GraphExtractionSource,
        draft: GraphExtractionDraft,
        outcome: GraphExtractionTraceOutcome,
        admission: GraphWriteAdmissionDecision,
        writeResult: GraphOptimisticWriteResult = GraphOptimisticWriteResult(),
        errorMessage: String? = nil,
        now: Date
    ) throws {
        var metadata = draft.metadata
        metadata["admission_message"] = admission.message
        try store.appendExtractionTrace(GraphExtractionTrace(
            id: "trace-\(job.id)-\(outcome.rawValue)-\(Int(now.timeIntervalSince1970 * 1000))",
            jobID: job.id,
            graphID: job.graphID,
            sourceID: source.id,
            sourceType: source.sourceType,
            outcome: outcome,
            admissionAction: admission.action,
            admissionReasons: admission.reasons,
            extractedEntityCount: draft.entities.count,
            extractedStatementCount: draft.statements.count,
            committedEntityCount: writeResult.committedEntityIDs.count,
            committedStatementCount: writeResult.committedStatementIDs.count,
            anomalyCount: writeResult.anomalyIDs.count,
            errorMessage: errorMessage,
            createdAt: now,
            metadata: metadata
        ))
    }

    private func appendFailureTrace(
        job: GraphJobV3,
        source: GraphExtractionSource? = nil,
        errorMessage: String,
        metadata: [String: String] = [:],
        now: Date
    ) throws {
        let sourceType = source?.sourceType ?? job.payload["source_type"].flatMap(GraphExtractionSourceType.init(rawValue:)) ?? .manual
        try store.appendExtractionTrace(GraphExtractionTrace(
            id: "trace-\(job.id)-failed-\(Int(now.timeIntervalSince1970 * 1000))",
            jobID: job.id,
            graphID: job.graphID,
            sourceID: source?.id ?? job.payload["source_id"] ?? "unknown",
            sourceType: sourceType,
            outcome: .failed,
            errorMessage: errorMessage,
            createdAt: now,
            metadata: metadata
        ))
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
