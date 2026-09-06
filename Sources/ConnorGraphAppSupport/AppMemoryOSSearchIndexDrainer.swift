import Foundation
import ConnorGraphSearch

/// Consumes the `memory_search_index_queue` backlog into the Tantivy search
/// kernel in batches. The kernel owns per-record resolution (upsert live
/// records, delete stale ones) and queue bookkeeping; this actor just keeps
/// calling it until the backlog is empty. Concurrent callers coalesce into a
/// single drain run, and failures are logged and retried on the next tick.
///
/// Incremental drains leave Tantivy segment fragmentation behind over time
/// (the index grows far beyond its live document set), so this actor also
/// triggers a periodic full rebuild from the source SQLite database — after
/// `fullRebuildInterval` has elapsed since the previous rebuild, or once
/// `batchesBetweenFullRebuilds` drain batches have been committed, whichever
/// comes first. A full rebuild rewrites the index from scratch, which
/// compacts it back to roughly its live size.
public actor AppMemoryOSSearchIndexDrainer {
    public struct DrainOutcome: Sendable, Equatable {
        public var processed: Int
        public var remaining: Int
        public var failed: Int
        public var didFullRebuild: Bool

        public init(processed: Int, remaining: Int, failed: Int, didFullRebuild: Bool = false) {
            self.processed = processed
            self.remaining = remaining
            self.failed = failed
            self.didFullRebuild = didFullRebuild
        }
    }

    public var batchSize: Int
    public var fullRebuildInterval: TimeInterval?
    public var batchesBetweenFullRebuilds: Int?
    private var isDraining = false
    private var lastFullRebuildDate: Date?
    private var batchesSinceFullRebuild = 0

    public init(
        batchSize: Int = 500,
        fullRebuildInterval: TimeInterval? = 7 * 24 * 60 * 60,
        batchesBetweenFullRebuilds: Int? = 200
    ) {
        self.batchSize = max(1, min(batchSize, 5_000))
        self.fullRebuildInterval = fullRebuildInterval
        self.batchesBetweenFullRebuilds = batchesBetweenFullRebuilds.map { max(1, $0) }
    }

    public func drainIfNeeded(kernel: MemoryOSSearchKernel, databaseURL: URL) async -> DrainOutcome {
        guard !isDraining else { return DrainOutcome(processed: 0, remaining: 0, failed: 0) }
        isDraining = true
        defer { isDraining = false }

        let didFullRebuild = rebuildIndexIfDue(kernel: kernel, databaseURL: databaseURL)

        var totalProcessed = 0
        var totalFailed = 0
        var remaining = 0
        var batchesCommitted = 0
        do {
            while true {
                let result = try kernel.drainQueue(databaseURL: databaseURL, limit: batchSize)
                totalProcessed += result.processed
                totalFailed += result.failed
                remaining = result.remaining
                batchesCommitted += 1
                if result.remaining == 0 || result.processed == 0 {
                    break
                }
            }
            batchesSinceFullRebuild += batchesCommitted
        } catch {
            return DrainOutcome(
                processed: totalProcessed,
                remaining: remaining,
                failed: totalFailed + 1,
                didFullRebuild: didFullRebuild
            )
        }
        return DrainOutcome(
            processed: totalProcessed,
            remaining: remaining,
            failed: totalFailed,
            didFullRebuild: didFullRebuild
        )
    }

    /// Runs a full index rebuild when the time/batch thresholds are due. A
    /// failed rebuild is best-effort: the stale-but-usable index stays in
    /// place and the next drain tick retries.
    private func rebuildIndexIfDue(kernel: MemoryOSSearchKernel, databaseURL: URL) -> Bool {
        guard fullRebuildInterval != nil || batchesBetweenFullRebuilds != nil else { return false }
        resolveLastFullRebuildDate(indexDirectory: kernel.indexDirectory)
        var timeThresholdDue = false
        if let interval = fullRebuildInterval, let last = lastFullRebuildDate {
            timeThresholdDue = Date().timeIntervalSince(last) >= interval
        }
        var batchThresholdDue = false
        if let batchThreshold = batchesBetweenFullRebuilds {
            batchThresholdDue = batchesSinceFullRebuild >= batchThreshold
        }
        guard timeThresholdDue || batchThresholdDue else { return false }
        do {
            let documentCount = try kernel.rebuildFromSQLite(databaseURL: databaseURL)
            try AppMemoryOSSearchKernelFactory.writeMeta(
                indexDirectory: kernel.indexDirectory,
                databaseURL: databaseURL,
                documentCount: documentCount
            )
        } catch {
            return false
        }
        lastFullRebuildDate = Date()
        batchesSinceFullRebuild = 0
        return true
    }

    /// Seeds the rebuild clock from `connor-meta.json` the first time we see a
    /// given index. A missing/unreadable timestamp counts as freshly rebuilt
    /// so a legacy index is not torn down on the first launch after upgrade.
    private func resolveLastFullRebuildDate(indexDirectory: URL) {
        guard lastFullRebuildDate == nil else { return }
        lastFullRebuildDate = AppMemoryOSSearchKernelFactory.lastFullRebuildDate(indexDirectory: indexDirectory) ?? Date()
    }
}
