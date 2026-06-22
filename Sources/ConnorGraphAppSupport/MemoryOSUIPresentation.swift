import Foundation
import ConnorGraphCore

public struct MemoryOSDashboardSnapshot: Sendable, Equatable, Codable {
    public var healthStatus: MemoryOSHealthStatus
    public var l0ProvenanceObjectCount: Int
    public var l1PendingCaptureCount: Int
    public var l1PendingQueueCount: Int
    public var l1DeadLetterCount: Int
    public var l1RetryScheduledCount: Int
    public var l1ExpiredLeaseCount: Int
    public var l2StatementCount: Int
    public var l2DiagnosticCount: Int
    public var l3BeliefCount: Int
    public var l4EntityCount: Int
    public var lastCheckedAt: Date

    public init(
        healthStatus: MemoryOSHealthStatus,
        l0ProvenanceObjectCount: Int = 0,
        l1PendingCaptureCount: Int = 0,
        l1PendingQueueCount: Int = 0,
        l1DeadLetterCount: Int = 0,
        l1RetryScheduledCount: Int = 0,
        l1ExpiredLeaseCount: Int = 0,
        l2StatementCount: Int = 0,
        l2DiagnosticCount: Int = 0,
        l3BeliefCount: Int = 0,
        l4EntityCount: Int = 0,
        lastCheckedAt: Date = Date()
    ) {
        self.healthStatus = healthStatus
        self.l0ProvenanceObjectCount = l0ProvenanceObjectCount
        self.l1PendingCaptureCount = l1PendingCaptureCount
        self.l1PendingQueueCount = l1PendingQueueCount
        self.l1DeadLetterCount = l1DeadLetterCount
        self.l1RetryScheduledCount = l1RetryScheduledCount
        self.l1ExpiredLeaseCount = l1ExpiredLeaseCount
        self.l2StatementCount = l2StatementCount
        self.l2DiagnosticCount = l2DiagnosticCount
        self.l3BeliefCount = l3BeliefCount
        self.l4EntityCount = l4EntityCount
        self.lastCheckedAt = lastCheckedAt
    }
}

public struct MemoryOSDashboardPresentation: Sendable, Equatable, Codable {
    public var title: String
    public var healthLabel: String
    public var layerRows: [MemoryOSDashboardLayerRow]
    public var operationalWarnings: [String]

    public init(title: String, healthLabel: String, layerRows: [MemoryOSDashboardLayerRow], operationalWarnings: [String] = []) {
        self.title = title
        self.healthLabel = healthLabel
        self.layerRows = layerRows
        self.operationalWarnings = operationalWarnings
    }
}

public struct MemoryOSDashboardLayerRow: Sendable, Equatable, Codable, Identifiable {
    public var id: String
    public var label: String
    public var primaryMetric: String
    public var detail: String

    public init(id: String, label: String, primaryMetric: String, detail: String) {
        self.id = id
        self.label = label
        self.primaryMetric = primaryMetric
        self.detail = detail
    }
}

public struct MemoryOSDashboardPresentationBuilder: Sendable {
    public init() {}

    public func presentation(for snapshot: MemoryOSDashboardSnapshot) -> MemoryOSDashboardPresentation {
        var warnings: [String] = []
        if snapshot.l1DeadLetterCount > 0 {
            warnings.append("Dead-letter queue contains \(snapshot.l1DeadLetterCount) item(s).")
        }
        if snapshot.l1ExpiredLeaseCount > 0 {
            warnings.append("Expired Memory OS queue leases: \(snapshot.l1ExpiredLeaseCount).")
        }
        if snapshot.healthStatus != .healthy {
            warnings.append("Memory OS store health is \(snapshot.healthStatus.rawValue).")
        }
        return MemoryOSDashboardPresentation(
            title: "Connor Memory OS",
            healthLabel: snapshot.healthStatus.rawValue,
            layerRows: [
                MemoryOSDashboardLayerRow(id: "l0", label: "L0 Provenance Vault", primaryMetric: "\(snapshot.l0ProvenanceObjectCount)", detail: "Evidence objects"),
                MemoryOSDashboardLayerRow(id: "l1", label: "L1 Capture Ledger", primaryMetric: "\(snapshot.l1PendingCaptureCount)", detail: "Pending captures; queue \(snapshot.l1PendingQueueCount); retry \(snapshot.l1RetryScheduledCount); expired leases \(snapshot.l1ExpiredLeaseCount)"),
                MemoryOSDashboardLayerRow(id: "l2", label: "L2 Operational Memory", primaryMetric: "\(snapshot.l2StatementCount)", detail: "Temporal statements; diagnostics \(snapshot.l2DiagnosticCount)"),
                MemoryOSDashboardLayerRow(id: "l3", label: "L3 Belief Layer", primaryMetric: "\(snapshot.l3BeliefCount)", detail: "Beliefs"),
                MemoryOSDashboardLayerRow(id: "l4", label: "L4 Stable Entity Layer", primaryMetric: "\(snapshot.l4EntityCount)", detail: "Stable entities")
            ],
            operationalWarnings: warnings
        )
    }
}
