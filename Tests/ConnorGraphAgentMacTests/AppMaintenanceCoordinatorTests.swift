import Foundation
import Testing
@testable import ConnorGraphAgentMac

@MainActor
@Suite("App maintenance coordinator")
struct AppMaintenanceCoordinatorTests {
    @Test func schedulerStartIsIdempotentAndStopCancelsFutureRuns() async throws {
        let coordinator = AppMaintenanceCoordinator()
        var runs = 0
        coordinator.runScheduledTasks = { runs += 1 }
        coordinator.startScheduler(interval: 0.02)
        coordinator.startScheduler(interval: 0.02)
        try await Task.sleep(for: .milliseconds(75))
        coordinator.stopScheduler()
        let stopped = runs
        try await Task.sleep(for: .milliseconds(50))
        #expect(stopped >= 1)
        #expect(runs == stopped)
    }

    @Test func concurrentReconcileForSameScopeCoalesces() async throws {
        let coordinator = AppMaintenanceCoordinator()
        var calls = 0
        coordinator.reconcileSources = { _ in
            calls += 1
            try await Task.sleep(for: .milliseconds(40))
        }
        async let first: Void = coordinator.reconcile(.allSources)
        async let second: Void = coordinator.reconcile(.allSources)
        _ = try await (first, second)
        #expect(calls == 1)
    }

    @Test func shutdownCancelsQueuedReconcileBeforeOperationStarts() async {
        let coordinator = AppMaintenanceCoordinator()
        var calls = 0
        coordinator.reconcileSources = { _ in calls += 1 }
        let task = Task { try await coordinator.reconcile(.allSources) }
        coordinator.shutdown()
        _ = try? await task.value
        #expect(calls == 0)
    }

    @Test func shutdownIsIdempotentAndRejectsNewWork() async {
        let coordinator = AppMaintenanceCoordinator()
        var calls = 0
        coordinator.runScheduledTasks = { calls += 1 }
        coordinator.shutdown()
        coordinator.shutdown()
        coordinator.startScheduler(interval: 0.01)
        coordinator.runScheduledTasksOnce()
        try? await Task.sleep(for: .milliseconds(30))
        #expect(calls == 0)
    }
}
