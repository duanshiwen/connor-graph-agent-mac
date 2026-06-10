import Foundation
import ConnorGraphCore
import ConnorGraphStore

/// App-level wrapper for `GraphBackgroundJobRunner` that provides a simple
/// interface for running queued background jobs (extraction, index refresh,
/// anomaly resolution, entity merge review).
///
/// Uses `StubGraphExtractor` by default. Replace with an LLM-backed extractor
/// when real extraction is needed.
public struct AppGraphBackgroundJobRunner: @unchecked Sendable {
    public let runner: GraphBackgroundJobRunner<StubGraphExtractor>
    public let graphID: String

    public init(store: SQLiteGraphKernelStore, graphID: String = "default") {
        self.runner = GraphBackgroundJobRunner(store: store, extractor: StubGraphExtractor())
        self.graphID = graphID
    }

    /// Run a single available job. Returns nil if no jobs are queued.
    public func runOnce(now: Date = Date()) async throws -> GraphBackgroundJobRunResult? {
        try await runner.runOnce(graphID: graphID, now: now)
    }

    /// Run up to `limit` available jobs. Returns results for each job processed.
    @discardableResult
    public func runAvailable(now: Date = Date(), limit: Int = 10) async throws -> [GraphBackgroundJobRunResult] {
        try await runner.runAvailable(graphID: graphID, now: now, limit: limit)
    }
}
