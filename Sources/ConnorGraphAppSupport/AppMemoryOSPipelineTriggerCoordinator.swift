import Foundation
import ConnorGraphCore
import ConnorGraphMemory

public struct AppMemoryOSPipelineTriggerCoordinator: @unchecked Sendable {
    public var facade: AppMemoryOSFacade
    public var l1CountPolicy: MemoryOSL1ProcessingTriggerPolicy
    public var l1AgePolicy: MemoryOSL1ProcessingTriggerPolicy

    public init(
        facade: AppMemoryOSFacade,
        l1CountPolicy: MemoryOSL1ProcessingTriggerPolicy = MemoryOSL1ProcessingTriggerPolicy(maxPendingAge: nil),
        l1AgePolicy: MemoryOSL1ProcessingTriggerPolicy = MemoryOSL1ProcessingTriggerPolicy(minPendingCount: 1_000_000)
    ) {
        self.facade = facade
        self.l1CountPolicy = l1CountPolicy
        self.l1AgePolicy = l1AgePolicy
    }

    public func evaluateAfterL1Capture(now: Date = Date()) throws -> [MemoryOSQueueItem] {
        try facade.enqueueL1UnifiedProjectionBackgroundJobs(policy: l1CountPolicy, now: now)
    }

    public func runDailySweep(now: Date = Date()) throws -> [MemoryOSQueueItem] {
        try facade.enqueueL1UnifiedProjectionBackgroundJobs(policy: l1AgePolicy, now: now)
    }
}
