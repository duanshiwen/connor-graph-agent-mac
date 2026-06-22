import Foundation
import Testing
import ConnorGraphAppSupport
import ConnorGraphCore

@Test func memoryOSDashboardPresentationShowsAllLayers() {
    let snapshot = MemoryOSDashboardSnapshot(
        healthStatus: .healthy,
        l0ProvenanceObjectCount: 10,
        l1PendingCaptureCount: 2,
        l1PendingQueueCount: 3,
        l2StatementCount: 20,
        l3BeliefCount: 4,
        l4EntityCount: 5
    )

    let presentation = MemoryOSDashboardPresentationBuilder().presentation(for: snapshot)

    #expect(presentation.title == "Connor Memory OS")
    #expect(presentation.layerRows.map(\.id) == ["l0", "l1", "l2", "l3", "l4"])
    #expect(presentation.layerRows.first?.primaryMetric == "10")
    #expect(presentation.operationalWarnings.isEmpty)
}

@Test func memoryOSDashboardPresentationShowsQueueRecoveryMetrics() {
    let snapshot = MemoryOSDashboardSnapshot(
        healthStatus: .healthy,
        l1PendingCaptureCount: 2,
        l1PendingQueueCount: 3,
        l1RetryScheduledCount: 1,
        l1ExpiredLeaseCount: 1
    )

    let presentation = MemoryOSDashboardPresentationBuilder().presentation(for: snapshot)
    let l1 = presentation.layerRows.first { $0.id == "l1" }

    #expect(l1?.detail.contains("retry 1") == true)
    #expect(l1?.detail.contains("expired leases 1") == true)
    #expect(presentation.operationalWarnings.contains("Expired Memory OS queue leases: 1."))
}

@Test func memoryOSDashboardPresentationWarnsForDeadLettersAndHealthIssues() {
    let snapshot = MemoryOSDashboardSnapshot(healthStatus: .warning, l1DeadLetterCount: 2)

    let presentation = MemoryOSDashboardPresentationBuilder().presentation(for: snapshot)

    #expect(presentation.operationalWarnings.contains { $0.contains("Dead-letter") })
    #expect(presentation.operationalWarnings.contains { $0.contains("warning") })
}
