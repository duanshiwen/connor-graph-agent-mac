import Foundation
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphStore

public struct AppMemoryOSRepository: Sendable {
    public var provenanceRepository: MemoryOSProvenanceRepository
    public var captureRepository: MemoryOSCaptureRepository

    public init(store: SQLiteMemoryOSStore) {
        self.provenanceRepository = MemoryOSProvenanceRepository(store: store)
        self.captureRepository = MemoryOSCaptureRepository(store: store)
    }

    public init(provenanceRepository: MemoryOSProvenanceRepository, captureRepository: MemoryOSCaptureRepository) {
        self.provenanceRepository = provenanceRepository
        self.captureRepository = captureRepository
    }

    public func save(_ result: MemoryOSIngestionResult) throws {
        guard let object = result.provenanceObject, let span = result.span, let captureEvent = result.captureEvent else { return }
        try provenanceRepository.save(object)
        try provenanceRepository.save(span)
        try captureRepository.save(captureEvent)
    }
}

public struct AppMemoryOSBackgroundRunSummary: Sendable, Equatable, Codable {
    public var expiredLeaseCount: Int
    public var projectionRunCount: Int
    public var aiJobRunCount: Int
    public var healthStatus: MemoryOSHealthStatus
    public var retryScheduledCount: Int
    public var deadLetterCount: Int
    public var attentionMessage: String?
    public var checkedAt: Date

    public init(expiredLeaseCount: Int, projectionRunCount: Int = 0, aiJobRunCount: Int = 0, healthStatus: MemoryOSHealthStatus, retryScheduledCount: Int = 0, deadLetterCount: Int = 0, attentionMessage: String? = nil, checkedAt: Date = Date()) {
        self.expiredLeaseCount = expiredLeaseCount
        self.projectionRunCount = projectionRunCount
        self.aiJobRunCount = aiJobRunCount
        self.healthStatus = healthStatus
        self.retryScheduledCount = retryScheduledCount
        self.deadLetterCount = deadLetterCount
        self.attentionMessage = attentionMessage
        self.checkedAt = checkedAt
    }
}

public struct BackgroundAIExecutorProvider: Sendable {
    public var runAIBatch: @Sendable (AppMemoryOSFacade) throws -> Int

    public init(runAIBatch: @escaping @Sendable (AppMemoryOSFacade) throws -> Int) {
        self.runAIBatch = runAIBatch
    }
}

public struct AppMemoryOSBackgroundJobRunner: Sendable {
    public var recoveryService: MemoryOSRecoveryService
    public var aiExecutorProvider: BackgroundAIExecutorProvider?

    public init(
        recoveryService: MemoryOSRecoveryService = MemoryOSRecoveryService(),
        aiExecutorProvider: BackgroundAIExecutorProvider? = nil
    ) {
        self.recoveryService = recoveryService
        self.aiExecutorProvider = aiExecutorProvider
    }

    public func shouldRecover(queueStatus: MemoryOSQueueStatus, leaseExpiresAt: Date?, now: Date = Date()) -> Bool {
        recoveryService.shouldRecoverLease(status: queueStatus, leaseExpiresAt: leaseExpiresAt, now: now)
    }

    public func runOnce(facade: AppMemoryOSFacade, now: Date = Date()) throws -> AppMemoryOSBackgroundRunSummary {
        let recoveredLeaseCount = try facade.recoverExpiredBackgroundQueueLeases(now: now)
        let projectionRuns = try facade.runProjectionQueueOnce(now: now)

        var aiRunCount = 0
        if let aiExecutorProvider {
            aiRunCount = try aiExecutorProvider.runAIBatch(facade)
        }

        let summary = try facade.operationalSummary(now: now)
        let attentionMessage: String?
        if summary.l1DeadLetterCount > 0 {
            attentionMessage = "Memory OS 有 \(summary.l1DeadLetterCount) 个后台任务需要处理，请检查 LLM 连接、余额或模型配置。"
        } else if summary.l1RetryScheduledCount > 0 {
            attentionMessage = "Memory OS 有 \(summary.l1RetryScheduledCount) 个后台任务正在等待自动重试。"
        } else if aiExecutorProvider == nil && summary.l1PendingQueueCount > 0 {
            attentionMessage = "Memory OS 有 \(summary.l1PendingQueueCount) 个后台任务等待执行，但当前没有可用的 LLM 连接。"
        } else {
            attentionMessage = nil
        }
        return AppMemoryOSBackgroundRunSummary(
            expiredLeaseCount: recoveredLeaseCount,
            projectionRunCount: projectionRuns.count,
            aiJobRunCount: aiRunCount,
            healthStatus: summary.healthReport.status,
            retryScheduledCount: summary.l1RetryScheduledCount,
            deadLetterCount: summary.l1DeadLetterCount,
            attentionMessage: attentionMessage,
            checkedAt: now
        )
    }
}
