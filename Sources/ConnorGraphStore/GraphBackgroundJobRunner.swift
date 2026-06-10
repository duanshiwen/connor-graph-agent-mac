import Foundation
import ConnorGraphCore

public enum GraphBackgroundJobOutcome: String, Sendable, Codable, Equatable {
    case succeeded
    case failed
    case paused
    case skipped
}

public struct GraphBackgroundJobRunResult: Sendable, Equatable, Identifiable {
    public var id: String { jobID }
    public var jobID: String
    public var jobType: GraphJobV3Type
    public var outcome: GraphBackgroundJobOutcome
    public var message: String

    public init(jobID: String, jobType: GraphJobV3Type, outcome: GraphBackgroundJobOutcome, message: String = "") {
        self.jobID = jobID
        self.jobType = jobType
        self.outcome = outcome
        self.message = message
    }
}

public struct GraphBackgroundJobRunner<Extractor: GraphExtractorProvider>: Sendable {
    public var store: SQLiteGraphKernelStore
    public var extractionWorker: GraphExtractionWorker<Extractor>
    public var indexRefreshWorker: GraphIndexRefreshWorker
    public var selfHealingService: GraphSelfHealingService
    public var entityMergeReviewWorker: GraphEntityMergeReviewWorker
    public var groundingCheckWorker: GraphGroundingCheckWorker

    public init(store: SQLiteGraphKernelStore, extractor: Extractor) {
        self.store = store
        self.extractionWorker = GraphExtractionWorker(store: store, extractor: extractor)
        self.indexRefreshWorker = GraphIndexRefreshWorker(store: store)
        self.selfHealingService = GraphSelfHealingService(store: store)
        self.entityMergeReviewWorker = GraphEntityMergeReviewWorker(store: store)
        self.groundingCheckWorker = GraphGroundingCheckWorker(store: store)
    }

    public init(
        store: SQLiteGraphKernelStore,
        extractionWorker: GraphExtractionWorker<Extractor>,
        indexRefreshWorker: GraphIndexRefreshWorker,
        selfHealingService: GraphSelfHealingService,
        entityMergeReviewWorker: GraphEntityMergeReviewWorker,
        groundingCheckWorker: GraphGroundingCheckWorker
    ) {
        self.store = store
        self.extractionWorker = extractionWorker
        self.indexRefreshWorker = indexRefreshWorker
        self.selfHealingService = selfHealingService
        self.entityMergeReviewWorker = entityMergeReviewWorker
        self.groundingCheckWorker = groundingCheckWorker
    }

    public func runOnce(graphID: String, now: Date = Date()) async throws -> GraphBackgroundJobRunResult? {
        guard let job = try store.runnableJobs(graphID: graphID, at: now, limit: 1).first else {
            return nil
        }
        return try await run(job: job, now: now)
    }

    public func runAvailable(graphID: String, now: Date = Date(), limit: Int = 10) async throws -> [GraphBackgroundJobRunResult] {
        var results: [GraphBackgroundJobRunResult] = []
        while results.count < limit {
            guard let result = try await runOnce(graphID: graphID, now: now) else { break }
            results.append(result)
        }
        return results
    }

    public func run(job: GraphJobV3, now: Date = Date()) async throws -> GraphBackgroundJobRunResult {
        switch job.type {
        case .extraction:
            let result = try await extractionWorker.run(job: job, now: now)
            let outcome: GraphBackgroundJobOutcome
            switch result.action {
            case .committed, .discarded:
                outcome = .succeeded
            case .held, .askUser:
                outcome = .paused
            case .failed:
                outcome = .failed
            case .skipped:
                outcome = .skipped
            }
            return GraphBackgroundJobRunResult(jobID: job.id, jobType: job.type, outcome: outcome, message: result.admissionDecision?.message ?? result.errorMessage ?? "")
        case .indexRefresh:
            let result = try indexRefreshWorker.run(job: job, now: now)
            return GraphBackgroundJobRunResult(jobID: job.id, jobType: job.type, outcome: result.action == .refreshed ? .succeeded : .failed, message: result.message)
        case .anomalyResolution:
            let result = try selfHealingService.run(job: job, now: now)
            let outcome: GraphBackgroundJobOutcome
            switch result.action {
            case .dismissedIncoming, .acceptedIncoming, .skipped: outcome = .succeeded
            case .needsReview: outcome = .paused
            }
            return GraphBackgroundJobRunResult(jobID: job.id, jobType: job.type, outcome: outcome, message: result.message)
        case .entityMergeReview:
            let result = try entityMergeReviewWorker.run(job: job, now: now)
            let outcome: GraphBackgroundJobOutcome
            switch result.action {
            case .merged, .skipped: outcome = .succeeded
            case .needsReview: outcome = .paused
            case .failed: outcome = .failed
            }
            return GraphBackgroundJobRunResult(jobID: job.id, jobType: job.type, outcome: outcome, message: result.message)
        case .groundingCheck:
            let result = try groundingCheckWorker.run(job: job, now: now)
            let outcome: GraphBackgroundJobOutcome = result.action == .failed ? .failed : .succeeded
            return GraphBackgroundJobRunResult(jobID: job.id, jobType: job.type, outcome: outcome, message: result.message)
        case .confidenceDecay, .ontologyPromotion:
            try pauseUnsupported(job: job, now: now)
            return GraphBackgroundJobRunResult(jobID: job.id, jobType: job.type, outcome: .paused, message: "Worker not implemented for \(job.type.rawValue)")
        }
    }

    private func pauseUnsupported(job: GraphJobV3, now: Date) throws {
        var paused = job
        paused.status = .paused
        paused.updatedAt = now
        paused.finishedAt = now
        paused.errorCode = "worker_not_implemented"
        paused.errorMessage = "Worker not implemented for \(job.type.rawValue)"
        try store.upsert(job: paused)
    }
}
