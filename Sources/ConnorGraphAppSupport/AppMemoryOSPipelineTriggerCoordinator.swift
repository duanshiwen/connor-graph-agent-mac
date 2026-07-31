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
        guard facade.canRunL1Extraction(now) else { return [] }
        return try facade.enqueueL1UnifiedProjectionBackgroundJobs(policy: l1CountPolicy, now: now)
    }

    public func evaluateAfterPreferenceWrite(now: Date = Date()) throws -> [MemoryOSQueueItem] {
        guard let item = try facade.enqueuePreferenceCompactionBackgroundJob(now: now)
        else { return [] }
        return [item]
    }

    public func runDailySweep(now: Date = Date()) throws -> [MemoryOSQueueItem] {
        var items: [MemoryOSQueueItem] = []
        if facade.canRunL1Extraction(now) {
            items = try facade.enqueueL1UnifiedProjectionBackgroundJobs(policy: l1AgePolicy, now: now)
        }
        if let preferenceItem = try facade.enqueuePreferenceCompactionBackgroundJob(forceIfOlderThan24Hours: true, now: now) {
            items.append(preferenceItem)
        }
        return items
    }
}
