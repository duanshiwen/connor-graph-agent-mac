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
    case failed
    case skipped
}

public struct GraphExtractionWorkerResult: Sendable, Equatable, Identifiable {
    public var id: String { jobID }
    public var jobID: String
    public var action: GraphExtractionWorkerAction
    public var writeResult: GraphOptimisticWriteResult

    public init(jobID: String, action: GraphExtractionWorkerAction, writeResult: GraphOptimisticWriteResult = GraphOptimisticWriteResult()) {
        self.jobID = jobID
        self.action = action
        self.writeResult = writeResult
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

    public init(store: SQLiteGraphKernelStore, extractor: Extractor, optimisticWriter: GraphOptimisticWriteService? = nil) {
        self.store = store
        self.extractor = extractor
        self.optimisticWriter = optimisticWriter ?? GraphOptimisticWriteService(store: store)
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
            let batch = try draft.toOptimisticWriteBatch(now: now)
            let writeResult = try optimisticWriter.commit(batch)
            try mark(job: job, status: .succeeded, now: now)
            return GraphExtractionWorkerResult(jobID: job.id, action: .committed, writeResult: writeResult)
        } catch {
            try mark(job: job, status: .failed, now: now, errorCode: "extraction_failed", errorMessage: String(describing: error))
            return GraphExtractionWorkerResult(jobID: job.id, action: .failed)
        }
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
