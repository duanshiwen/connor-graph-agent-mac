import Foundation
import ConnorGraphCore

public actor AppMemoryOSMaintenanceWorker {
    public init() {}

    public func runBackgroundJobs(
        facade: AppMemoryOSFacade,
        aiExecutorProvider: BackgroundAIExecutorProvider?,
        now: Date = Date()
    ) async throws -> AppMemoryOSBackgroundRunSummary {
        let eligible = facade.canRunL1Extraction(now)
        var summary = try await AppMemoryOSBackgroundJobRunner(
            aiExecutorProvider: eligible ? aiExecutorProvider : nil
        ).runOnce(facade: facade, now: now)
        if !eligible {
            // A different device owns L1. Keep local maintenance active without
            // presenting the intentionally paused AI queue as a missing-provider error.
            summary.attentionMessage = nil
        }
        return summary
    }

    public func runDailySweep(
        facade: AppMemoryOSFacade,
        now: Date = Date()
    ) throws -> [MemoryOSQueueItem] {
        try AppMemoryOSPipelineTriggerCoordinator(facade: facade).runDailySweep(now: now)
    }
}
