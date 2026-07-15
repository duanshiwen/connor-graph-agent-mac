import Testing
@testable import ConnorGraphAgentMac

@MainActor
@Suite("App Startup Coordinator Tests")
struct AppStartupCoordinatorTests {
    @Test func stagesRunInDependencyOrderExactlyOnceAcrossConcurrentStarts() async {
        var calls: [String] = []
        let coordinator = makeCoordinator(calls: { calls.append($0) })
        async let first: Void = coordinator.startIfNeeded()
        async let second: Void = coordinator.startIfNeeded()
        _ = await (first, second)
        #expect(calls == ["core", "interactive", "content", "maintenance"])
        #expect(coordinator.phaseHistory == [.lightConstruction, .coreBootstrap, .interactiveReady, .contentReady, .maintenanceReady])
    }

    @Test func earlyCommandsRunOnceAfterInteractiveReady() async {
        var calls: [String] = []
        let coordinator = makeCoordinator(calls: { calls.append($0) })
        coordinator.performWhenInteractive { calls.append("command") }
        await coordinator.startIfNeeded()
        #expect(calls == ["core", "interactive", "command", "content", "maintenance"])
    }

    @Test func shutdownDropsQueuedCommandsAndPreventsStartup() async {
        var calls: [String] = []
        let coordinator = makeCoordinator(calls: { calls.append($0) })
        coordinator.performWhenInteractive { calls.append("command") }
        coordinator.shutdown()
        await coordinator.startIfNeeded()
        #expect(calls == ["shutdown"])
        #expect(coordinator.phase == .lightConstruction)
    }

    @Test func shutdownDuringCoreRejectsStaleResultAndQueuedCommand() async {
        var calls: [String] = []
        var releaseCore: CheckedContinuation<Void, Never>?
        let coordinator = AppStartupCoordinator(
            coreBootstrap: { _ in
                calls.append("core-start")
                await withCheckedContinuation { releaseCore = $0 }
                calls.append("core-return")
            },
            prepareInteractive: { _ in calls.append("interactive") },
            loadContent: { _ in calls.append("content") },
            startMaintenance: { _ in calls.append("maintenance") },
            shutdown: { calls.append("shutdown") }
        )
        coordinator.performWhenInteractive { calls.append("command") }
        let startTask = Task { await coordinator.startIfNeeded() }
        while releaseCore == nil { await Task.yield() }
        coordinator.shutdown()
        releaseCore?.resume()
        await startTask.value
        #expect(calls == ["core-start", "shutdown", "core-return"])
        #expect(coordinator.phase == .coreBootstrap || coordinator.phase == .lightConstruction)
    }

    @Test func stageFailureStopsLaterStagesAndRetryCanComplete() async {
        var attempts = 0
        var calls: [String] = []
        let coordinator = AppStartupCoordinator(
            coreBootstrap: { _ in calls.append("core") },
            prepareInteractive: { _ in
                attempts += 1
                calls.append("interactive")
                if attempts == 1 { throw TestFailure.expected }
            },
            loadContent: { _ in calls.append("content") },
            startMaintenance: { _ in calls.append("maintenance") },
            shutdown: { calls.append("shutdown") }
        )
        await coordinator.startIfNeeded()
        #expect(coordinator.phase == .failed)
        #expect(calls == ["core", "interactive"])
        await coordinator.retry()
        #expect(coordinator.phase == .maintenanceReady)
        #expect(calls == ["core", "interactive", "core", "interactive", "content", "maintenance"])
    }

    private func makeCoordinator(calls: @escaping (String) -> Void) -> AppStartupCoordinator {
        AppStartupCoordinator(
            coreBootstrap: { _ in calls("core") },
            prepareInteractive: { _ in calls("interactive") },
            loadContent: { _ in calls("content") },
            startMaintenance: { _ in calls("maintenance") },
            shutdown: { calls("shutdown") }
        )
    }

    private enum TestFailure: Error { case expected }
}
