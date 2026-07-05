import Foundation
import ConnorGraphCore

public actor AppMemoryOSMaintenanceWorker {
    public init() {}

    public func runBackgroundJobs(
        facade: AppMemoryOSFacade,
        aiExecutorProvider: BackgroundAIExecutorProvider?,
        now: Date = Date()
    ) throws -> AppMemoryOSBackgroundRunSummary {
        try AppMemoryOSBackgroundJobRunner(aiExecutorProvider: aiExecutorProvider).runOnce(facade: facade, now: now)
    }

    public func runDailySweep(
        facade: AppMemoryOSFacade,
        now: Date = Date()
    ) throws -> [MemoryOSQueueItem] {
        try AppMemoryOSPipelineTriggerCoordinator(facade: facade).runDailySweep(now: now)
    }
}
