import Foundation
import ConnorGraphCore
import ConnorGraphMemory

public struct AppMemoryOSPipelineTriggerCoordinator: @unchecked Sendable {
    public var facade: AppMemoryOSFacade
    public var l1CountPolicy: MemoryOSL1ProcessingTriggerPolicy
    public var l1AgePolicy: MemoryOSL1ProcessingTriggerPolicy
    public var l2CountPolicy: MemoryOSL2KnowledgeSynthesisTriggerPolicy
    public var l2AgePolicy: MemoryOSL2KnowledgeSynthesisTriggerPolicy

    public init(
        facade: AppMemoryOSFacade,
        l1CountPolicy: MemoryOSL1ProcessingTriggerPolicy = MemoryOSL1ProcessingTriggerPolicy(maxPendingAge: nil),
        l1AgePolicy: MemoryOSL1ProcessingTriggerPolicy = MemoryOSL1ProcessingTriggerPolicy(minPendingCount: 1_000_000),
        l2CountPolicy: MemoryOSL2KnowledgeSynthesisTriggerPolicy = MemoryOSL2KnowledgeSynthesisTriggerPolicy(maxPendingAge: nil),
        l2AgePolicy: MemoryOSL2KnowledgeSynthesisTriggerPolicy = MemoryOSL2KnowledgeSynthesisTriggerPolicy(minPendingStatementCount: 1_000_000)
    ) {
        self.facade = facade
        self.l1CountPolicy = l1CountPolicy
        self.l1AgePolicy = l1AgePolicy
        self.l2CountPolicy = l2CountPolicy
        self.l2AgePolicy = l2AgePolicy
    }

    public func evaluateAfterL1Capture(now: Date = Date()) throws -> [MemoryOSQueueItem] {
        try facade.enqueueL1ToL2BackgroundJobs(policy: l1CountPolicy, now: now)
    }

    public func evaluateAfterL2PendingStatements(now: Date = Date()) throws -> [MemoryOSQueueItem] {
        try facade.enqueueL2ToKnowledgeBackgroundJobs(policy: l2CountPolicy, now: now)
    }

    public func runDailySweep(now: Date = Date()) throws -> [MemoryOSQueueItem] {
        let l1 = try facade.enqueueL1ToL2BackgroundJobs(policy: l1AgePolicy, now: now)
        let l2 = try facade.enqueueL2ToKnowledgeBackgroundJobs(policy: l2AgePolicy, now: now)
        return l1 + l2
    }
}
