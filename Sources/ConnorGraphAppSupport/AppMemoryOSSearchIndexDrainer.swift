import Foundation
import ConnorGraphSearch

/// Consumes the `memory_search_index_queue` backlog into the Tantivy search
/// kernel in batches. The kernel owns per-record resolution (upsert live
/// records, delete stale ones) and queue bookkeeping; this actor just keeps
/// calling it until the backlog is empty. Concurrent callers coalesce into a
/// single drain run, and failures are logged and retried on the next tick.
public actor AppMemoryOSSearchIndexDrainer {
    public struct DrainOutcome: Sendable, Equatable {
        public var processed: Int
        public var remaining: Int
        public var failed: Int

        public init(processed: Int, remaining: Int, failed: Int) {
            self.processed = processed
            self.remaining = remaining
            self.failed = failed
        }
    }

    public var batchSize: Int
    private var isDraining = false

    public init(batchSize: Int = 500) {
        self.batchSize = max(1, min(batchSize, 5_000))
    }

    public func drainIfNeeded(kernel: MemoryOSSearchKernel, databaseURL: URL) async -> DrainOutcome {
        guard !isDraining else { return DrainOutcome(processed: 0, remaining: 0, failed: 0) }
        isDraining = true
        defer { isDraining = false }

        var totalProcessed = 0
        var totalFailed = 0
        var remaining = 0
        do {
            while true {
                let result = try kernel.drainQueue(databaseURL: databaseURL, limit: batchSize)
                totalProcessed += result.processed
                totalFailed += result.failed
                remaining = result.remaining
                if result.remaining == 0 || result.processed == 0 {
                    break
                }
            }
        } catch {
            return DrainOutcome(
                processed: totalProcessed,
                remaining: remaining,
                failed: totalFailed + 1
            )
        }
        return DrainOutcome(processed: totalProcessed, remaining: remaining, failed: totalFailed)
    }
}
