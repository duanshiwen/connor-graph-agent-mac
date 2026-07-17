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

    @Test func schedulerAlsoPollsPersistentBackgroundJobs() async throws {
        let coordinator = AppMaintenanceCoordinator()
        var backgroundRuns = 0
        coordinator.runBackgroundJobs = { backgroundRuns += 1 }

        coordinator.startScheduler(interval: 0.02)
        try await Task.sleep(for: .milliseconds(75))
        coordinator.stopScheduler()

        #expect(backgroundRuns >= 2)
    }

    @Test func schedulerRunsDailySweepImmediatelyOnLaunch() async throws {
        let coordinator = AppMaintenanceCoordinator()
        var dailySweepRuns = 0
        coordinator.runDailySweep = { dailySweepRuns += 1 }

        coordinator.startScheduler(interval: 10)
        try await Task.sleep(for: .milliseconds(30))
        coordinator.stopScheduler()

        #expect(dailySweepRuns == 1)
    }

    @Test func backgroundTriggerWhileWorkerIsBusyRunsAnotherBatch() async throws {
        let coordinator = AppMaintenanceCoordinator()
        var backgroundRuns = 0
        coordinator.runBackgroundJobs = {
            backgroundRuns += 1
            if backgroundRuns == 1 {
                try? await Task.sleep(for: .milliseconds(30))
            }
        }

        coordinator.scheduleBackgroundJobs()
        coordinator.scheduleBackgroundJobs()
        try await Task.sleep(for: .milliseconds(80))

        #expect(backgroundRuns == 2)
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
