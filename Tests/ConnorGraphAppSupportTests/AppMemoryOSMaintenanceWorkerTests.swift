import Foundation
import Testing
import ConnorGraphStore
@testable import ConnorGraphAppSupport

@Suite("App MemoryOS Maintenance Worker Tests")
struct AppMemoryOSMaintenanceWorkerTests {
    @Test func workerRunsBackgroundJobsThroughFacade() async throws {
        let store = try SQLiteMemoryOSStore(path: ":memory:")
        try store.migrate()
        let facade = AppMemoryOSFacade(store: store, canRunL1Extraction: { _ in true })
        let now = Date(timeIntervalSince1970: 1_000)
        let worker = AppMemoryOSMaintenanceWorker()

        let summary = try await worker.runBackgroundJobs(facade: facade, aiExecutorProvider: nil, now: now)

        #expect(summary.healthStatus == .healthy)
        #expect(summary.checkedAt == now)
    }

    @Test func workerKeepsL1JobsQueuedWithoutDeviceLease() async throws {
        let store = try SQLiteMemoryOSStore(path: ":memory:")
        try store.migrate()
        let facade = AppMemoryOSFacade(store: store, canRunL1Extraction: { _ in false })
        let now = Date(timeIntervalSince1970: 1_500)
        let provider = BackgroundAIExecutorProvider { _ in 42 }

        let summary = try await AppMemoryOSMaintenanceWorker().runBackgroundJobs(
            facade: facade,
            aiExecutorProvider: provider,
            now: now
        )

        #expect(summary.aiJobRunCount == 0)
        #expect(summary.checkedAt == now)
    }

    @Test func workerRunsDailySweepThroughCoordinator() async throws {
        let store = try SQLiteMemoryOSStore(path: ":memory:")
        try store.migrate()
        let facade = AppMemoryOSFacade(store: store)
        let now = Date(timeIntervalSince1970: 2_000)
        let worker = AppMemoryOSMaintenanceWorker()

        let items = try await worker.runDailySweep(facade: facade, now: now)

        #expect(items.isEmpty)
    }
}
