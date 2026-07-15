import Foundation
import Observation

enum AppStartupPhase: Int, CaseIterable, Sendable, Comparable {
    case lightConstruction
    case coreBootstrap
    case interactiveReady
    case contentReady
    case maintenanceReady
    case failed

    static func < (lhs: AppStartupPhase, rhs: AppStartupPhase) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

@MainActor
@Observable
final class AppStartupCoordinator {
    typealias StageAction = @MainActor (_ generation: Int) async throws -> Void
    typealias ShutdownAction = @MainActor () -> Void
    typealias EarlyCommand = @MainActor () -> Void

    private let coreBootstrap: StageAction
    private let prepareInteractive: StageAction
    private let loadContent: StageAction
    private let startMaintenance: StageAction
    private let shutdownAction: ShutdownAction

    private var startupTask: Task<Void, Never>?
    private var generation = 0
    private var queuedEarlyCommands: [EarlyCommand] = []

    private(set) var phase: AppStartupPhase = .lightConstruction
    private(set) var phaseHistory: [AppStartupPhase] = [.lightConstruction]
    private(set) var failureMessage: String?
    private(set) var hasStarted = false
    private(set) var isShutdown = false

    var isInteractiveReady: Bool {
        phase >= .interactiveReady && phase != .failed
    }

    init(
        coreBootstrap: @escaping StageAction,
        prepareInteractive: @escaping StageAction,
        loadContent: @escaping StageAction,
        startMaintenance: @escaping StageAction,
        shutdown: @escaping ShutdownAction
    ) {
        self.coreBootstrap = coreBootstrap
        self.prepareInteractive = prepareInteractive
        self.loadContent = loadContent
        self.startMaintenance = startMaintenance
        self.shutdownAction = shutdown
    }

    func startIfNeeded() async {
        guard !isShutdown else { return }
        if let startupTask {
            await startupTask.value
            return
        }

        hasStarted = true
        generation &+= 1
        let currentGeneration = generation
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await runStage(.coreBootstrap, generation: currentGeneration, action: coreBootstrap)
                try await runStage(.interactiveReady, generation: currentGeneration, action: prepareInteractive)
                drainEarlyCommandsIfReady(generation: currentGeneration)
                try await runStage(.contentReady, generation: currentGeneration, action: loadContent)
                try await runStage(.maintenanceReady, generation: currentGeneration, action: startMaintenance)
            } catch is CancellationError {
                return
            } catch {
                guard acceptsResults(for: currentGeneration) else { return }
                failureMessage = String(describing: error)
                transition(to: .failed)
            }
        }
        startupTask = task
        await task.value
    }

    func performWhenInteractive(_ command: @escaping EarlyCommand) {
        guard !isShutdown else { return }
        if isInteractiveReady {
            command()
        } else {
            queuedEarlyCommands.append(command)
        }
    }

    func retry() async {
        guard !isShutdown, phase == .failed else { return }
        startupTask?.cancel()
        startupTask = nil
        failureMessage = nil
        phase = .lightConstruction
        phaseHistory = [.lightConstruction]
        await startIfNeeded()
    }

    func shutdown() {
        guard !isShutdown else { return }
        isShutdown = true
        generation &+= 1
        startupTask?.cancel()
        startupTask = nil
        queuedEarlyCommands.removeAll()
        shutdownAction()
    }

    private func runStage(
        _ nextPhase: AppStartupPhase,
        generation: Int,
        action: StageAction
    ) async throws {
        guard acceptsResults(for: generation) else { throw CancellationError() }
        AppStartupPerformance.event(eventName(for: nextPhase))
        switch nextPhase {
        case .coreBootstrap:
            try await AppStartupPerformance.measure("StartupCoreBootstrap") { try await action(generation) }
        case .interactiveReady:
            try await AppStartupPerformance.measure("StartupInteractiveReady") { try await action(generation) }
        case .contentReady:
            try await AppStartupPerformance.measure("StartupContentReady") { try await action(generation) }
        case .maintenanceReady:
            try await AppStartupPerformance.measure("StartupMaintenanceReady") { try await action(generation) }
        case .lightConstruction, .failed:
            try await action(generation)
        }
        guard acceptsResults(for: generation) else { throw CancellationError() }
        transition(to: nextPhase)
    }

    func acceptsResults(for candidateGeneration: Int) -> Bool {
        !isShutdown && !Task.isCancelled && generation == candidateGeneration
    }

    private func transition(to nextPhase: AppStartupPhase) {
        phase = nextPhase
        if phaseHistory.last != nextPhase { phaseHistory.append(nextPhase) }
    }

    private func drainEarlyCommandsIfReady(generation: Int) {
        guard acceptsResults(for: generation), isInteractiveReady else { return }
        let commands = queuedEarlyCommands
        queuedEarlyCommands.removeAll()
        commands.forEach { $0() }
    }

    private func eventName(for phase: AppStartupPhase) -> StaticString {
        switch phase {
        case .lightConstruction: "StartupLightConstruction"
        case .coreBootstrap: "StartupCoreBootstrap"
        case .interactiveReady: "StartupInteractiveReady"
        case .contentReady: "StartupContentReady"
        case .maintenanceReady: "StartupMaintenanceReady"
        case .failed: "StartupFailed"
        }
    }
}
