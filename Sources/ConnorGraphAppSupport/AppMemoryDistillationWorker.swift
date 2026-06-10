import Foundation
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphStore

public struct AppMemoryDistillationRunResult: Sendable, Equatable, Identifiable {
    public var id: String { bufferID }
    public var bufferID: String
    public var sessionID: String
    public var distillationResultID: String?
    public var enqueuedJobIDs: [String]
    public var discardedItemCount: Int
    public var outcome: GraphBackgroundJobOutcome
    public var message: String

    public init(
        bufferID: String,
        sessionID: String,
        distillationResultID: String? = nil,
        enqueuedJobIDs: [String] = [],
        discardedItemCount: Int = 0,
        outcome: GraphBackgroundJobOutcome,
        message: String = ""
    ) {
        self.bufferID = bufferID
        self.sessionID = sessionID
        self.distillationResultID = distillationResultID
        self.enqueuedJobIDs = enqueuedJobIDs
        self.discardedItemCount = discardedItemCount
        self.outcome = outcome
        self.message = message
    }
}

public struct AppMemoryDistillationWorker: Sendable {
    public var store: SQLiteGraphKernelStore
    public var stagingRepository: AppMemoryStagingBufferRepository
    public var distillationService: MemoryDistillationService
    public var graphID: String

    public init(
        store: SQLiteGraphKernelStore,
        graphID: String = "default",
        distillationService: MemoryDistillationService = MemoryDistillationService()
    ) {
        self.store = store
        self.stagingRepository = AppMemoryStagingBufferRepository(store: store)
        self.distillationService = distillationService
        self.graphID = graphID
    }

    public func runOnce(now: Date = Date()) throws -> AppMemoryDistillationRunResult? {
        guard let buffer = try stagingRepository.loadBuffers(status: .active, limit: 100)
            .first(where: { $0.pendingBundles.contains(where: { $0.status == .closed }) })
        else { return nil }
        return try run(buffer: buffer, now: now)
    }

    @discardableResult
    public func runAvailable(now: Date = Date(), limit: Int = 10) throws -> [AppMemoryDistillationRunResult] {
        var results: [AppMemoryDistillationRunResult] = []
        while results.count < limit {
            guard let result = try runOnce(now: now) else { break }
            results.append(result)
        }
        return results
    }

    public func run(buffer originalBuffer: MemoryStagingBuffer, now: Date = Date()) throws -> AppMemoryDistillationRunResult {
        let closedBundleCount = originalBuffer.pendingBundles.filter { $0.status == .closed }.count
        guard closedBundleCount > 0 else {
            return AppMemoryDistillationRunResult(
                bufferID: originalBuffer.id,
                sessionID: originalBuffer.sessionID,
                outcome: .skipped,
                message: "No closed bundles to distill."
            )
        }

        var buffer = originalBuffer
        buffer.markDistilling()
        try stagingRepository.saveBuffer(buffer, updatedAt: now)

        let triggerReasons = buffer.triggerReasons(at: now)
        let result = distillationService.distill(buffer: buffer, at: now, triggerReasons: triggerReasons)
        let jobIDs = try result.episodeCandidates.map { candidate in
            try enqueueExtractionJob(for: candidate, result: result, now: now)
        }

        buffer.pendingBundles.removeAll { $0.status == .closed }
        buffer.tokenEstimate = buffer.pendingBundles.reduce(0) { total, bundle in
            total + estimateTokens(distillationService.renderBundle(bundle))
        }
        buffer.lastDistilledAt = now
        buffer.status = buffer.pendingBundles.isEmpty ? .drained : .active
        var metadata = buffer.metadata
        metadata["last_distillation_result_id"] = result.id
        metadata["last_distillation_episode_candidate_count"] = "\(result.episodeCandidates.count)"
        metadata["last_distillation_enqueued_job_count"] = "\(jobIDs.count)"
        buffer.metadata = metadata
        try stagingRepository.saveBuffer(buffer, updatedAt: now)

        return AppMemoryDistillationRunResult(
            bufferID: buffer.id,
            sessionID: buffer.sessionID,
            distillationResultID: result.id,
            enqueuedJobIDs: jobIDs,
            discardedItemCount: result.discardedItems.count,
            outcome: .succeeded,
            message: "Distilled \(closedBundleCount) closed bundles into \(jobIDs.count) extraction jobs."
        )
    }

    private func enqueueExtractionJob(
        for candidate: MemoryDistillationCandidate,
        result: MemoryDistillationResult,
        now: Date
    ) throws -> String {
        let source = GraphExtractionSource(
            id: "memory-distillation-\(candidate.id)",
            graphID: graphID,
            sourceType: .chat,
            title: candidate.title.isEmpty ? "Memory distillation episode" : candidate.title,
            content: candidate.content,
            occurredAt: result.createdAt,
            sessionID: result.sessionID,
            metadata: [
                "memory_distillation_result_id": result.id,
                "memory_staging_buffer_id": result.sourceBufferID,
                "memory_candidate_id": candidate.id,
                "memory_candidate_kind": candidate.kind.rawValue,
                "memory_candidate_origin": candidate.metadata["candidate_origin"] ?? "memory_distillation",
                "bundle_id": candidate.metadata["bundle_id"] ?? ""
            ]
        )
        return try store.enqueueExtractionJob(graphID: graphID, source: source, priority: 6, now: now)
    }

    private func estimateTokens(_ text: String) -> Int {
        max(1, Int(ceil(Double(text.count) / 4.0)))
    }
}
