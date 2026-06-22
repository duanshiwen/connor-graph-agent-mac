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
    public var healthStatus: MemoryOSHealthStatus
    public var checkedAt: Date

    public init(expiredLeaseCount: Int, projectionRunCount: Int = 0, healthStatus: MemoryOSHealthStatus, checkedAt: Date = Date()) {
        self.expiredLeaseCount = expiredLeaseCount
        self.projectionRunCount = projectionRunCount
        self.healthStatus = healthStatus
        self.checkedAt = checkedAt
    }
}

public struct AppMemoryOSBackgroundJobRunner: Sendable {
    public var recoveryService: MemoryOSRecoveryService

    public init(recoveryService: MemoryOSRecoveryService = MemoryOSRecoveryService()) {
        self.recoveryService = recoveryService
    }

    public func shouldRecover(queueStatus: MemoryOSQueueStatus, leaseExpiresAt: Date?, now: Date = Date()) -> Bool {
        recoveryService.shouldRecoverLease(status: queueStatus, leaseExpiresAt: leaseExpiresAt, now: now)
    }

    public func runOnce(facade: AppMemoryOSFacade, now: Date = Date()) throws -> AppMemoryOSBackgroundRunSummary {
        let projectionRuns = try facade.runProjectionQueueOnce(now: now)
        let summary = try facade.operationalSummary(now: now)
        return AppMemoryOSBackgroundRunSummary(
            expiredLeaseCount: summary.expiredLeaseCount,
            projectionRunCount: projectionRuns.count,
            healthStatus: summary.healthReport.status,
            checkedAt: now
        )
    }
}
