import Foundation
import ConnorGraphCore

public enum NoteImportRuntimeState: String, Sendable, Equatable {
    case starting
    case running
    case recovering
    case finalizingCancellation = "finalizing_cancellation"
    case failed
}

public struct NoteImportRuntimeSnapshot: Sendable, Equatable {
    public var statesByJobID: [String: NoteImportRuntimeState]
    public var errorsByJobID: [String: String]

    public init(
        statesByJobID: [String: NoteImportRuntimeState] = [:],
        errorsByJobID: [String: String] = [:]
    ) {
        self.statesByJobID = statesByJobID
        self.errorsByJobID = errorsByJobID
    }

    public func state(for jobID: String) -> NoteImportRuntimeState? {
        statesByJobID[jobID]
    }
}

public actor NoteImportExecutionSupervisor {
    private let coordinator: NoteImportCoordinator
    private var tasks: [String: Task<Void, Never>] = [:]
    private var states: [String: NoteImportRuntimeState] = [:]
    private var errors: [String: String] = [:]

    public init(coordinator: NoteImportCoordinator) {
        self.coordinator = coordinator
    }

    public func recoverPersistedJobs() async {
        do {
            for job in try await coordinator.recoverableJobs() {
                guard shouldRecover(job) else { continue }
                ensureRunning(jobID: job.id, recovering: true)
            }
        } catch {
            errors["recovery"] = String(describing: error)
        }
    }

    public func ensureRunning(jobID: String) {
        ensureRunning(jobID: jobID, recovering: false)
    }

    public func requestPause(jobID: String) async throws {
        try await coordinator.pause(jobID: jobID)
    }

    public func resume(jobID: String) async throws {
        try await coordinator.resume(jobID: jobID)
        ensureRunning(jobID: jobID, recovering: true)
    }

    public func requestCancel(jobID: String) async throws {
        try await coordinator.cancel(jobID: jobID)
        ensureRunning(jobID: jobID, recovering: tasks[jobID] == nil)
    }

    public func snapshot() -> NoteImportRuntimeSnapshot {
        NoteImportRuntimeSnapshot(statesByJobID: states, errorsByJobID: errors)
    }

    public func isRunning(jobID: String) -> Bool {
        tasks[jobID] != nil
    }

    private func shouldRecover(_ job: NoteImportJobRecord) -> Bool {
        if job.cancelRequestedAt != nil || job.status == .cancelling { return true }
        guard job.pauseRequestedAt == nil, job.status != .paused else { return false }
        return [.ready, .importing, .processing].contains(job.status)
    }

    private func ensureRunning(jobID: String, recovering: Bool) {
        guard tasks[jobID] == nil else { return }
        errors.removeValue(forKey: jobID)
        states[jobID] = recovering ? .recovering : .starting
        let coordinator = self.coordinator
        tasks[jobID] = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.markRunning(jobID: jobID)
            do {
                _ = try await coordinator.execute(jobID: jobID)
                await self.finish(jobID: jobID, error: nil)
            } catch is CancellationError {
                await self.finish(jobID: jobID, error: nil)
            } catch {
                await self.finish(jobID: jobID, error: error)
            }
        }
    }

    private func markRunning(jobID: String) {
        states[jobID] = .running
    }

    private func finish(jobID: String, error: Error?) {
        tasks.removeValue(forKey: jobID)
        states.removeValue(forKey: jobID)
        if let error {
            errors[jobID] = String(describing: error)
        }
    }
}
