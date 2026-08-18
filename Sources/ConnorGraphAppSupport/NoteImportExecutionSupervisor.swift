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
    private var taskGenerations: [String: Int] = [:]
    private var states: [String: NoteImportRuntimeState] = [:]
    private var errors: [String: String] = [:]

    public init(coordinator: NoteImportCoordinator) {
        self.coordinator = coordinator
    }

    public func recoverPersistedJobs() async {
        let interval = NoteImportPerformanceLog.begin("Supervisor Recovery", jobID: "startup")
        defer { NoteImportPerformanceLog.end(interval, jobID: "startup") }
        do {
            let jobs = try await coordinator.recoverableJobs()
            NoteImportPerformanceLog.event("Recoverable Jobs", jobID: "startup", itemCount: jobs.count)
            for job in jobs {
                if [.created, .scanning].contains(job.status) {
                    try await coordinator.failInterruptedPreparation(jobID: job.id)
                    continue
                }
                guard shouldRecover(job) else { continue }
                if job.cancelRequestedAt != nil || job.status == .cancelling {
                    NoteImportPerformanceLog.event("Cancellation Recovery", jobID: job.id)
                }
                ensureRunning(jobID: job.id, recovering: true)
            }
            await recoverStuckRunners()
        } catch {
            errors["recovery"] = String(describing: error)
            NoteImportPerformanceLog.event("Supervisor Recovery Failed", jobID: "startup")
        }
    }

    /// 看门狗：替换持有过期租约的卡死 runner，让导入任务无需重启应用即可自愈。
    public func recoverStuckRunners() async {
        for jobID in tasks.keys {
            guard let stuck = try? await coordinator.hasStaleRunnerLeases(jobID: jobID), stuck else { continue }
            NoteImportPerformanceLog.event("Stuck Runner Replaced", jobID: jobID)
            await replaceRunner(jobID: jobID)
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

    public func delete(jobID: String) async throws {
        guard tasks[jobID] == nil else {
            throw AppNoteImportRepositoryError.jobControlUnavailable("Active import tasks cannot be deleted")
        }
        try await coordinator.delete(jobID: jobID)
        states.removeValue(forKey: jobID)
        errors.removeValue(forKey: jobID)
    }

    public func snapshot() -> NoteImportRuntimeSnapshot {
        NoteImportRuntimeSnapshot(statesByJobID: states, errorsByJobID: errors)
    }

    public func isRunning(jobID: String) -> Bool {
        tasks[jobID] != nil
    }

    public func waitUntilFinished(jobID: String) async {
        let task = tasks[jobID]
        await task?.value
    }

    private func shouldRecover(_ job: NoteImportJobRecord) -> Bool {
        if job.cancelRequestedAt != nil || job.status == .cancelling { return true }
        guard job.pauseRequestedAt == nil, job.status != .paused else { return false }
        return [.awaitingReview, .ready, .importing, .processing].contains(job.status)
    }

    private func ensureRunning(jobID: String, recovering: Bool) {
        guard tasks[jobID] == nil else {
            NoteImportPerformanceLog.event("Duplicate Runner Suppressed", jobID: jobID)
            // 已有 runner 时仍做一次卡死检查：租约过期则替换，避免僵尸任务永久占坑。
            Task { [weak self] in
                guard let self, let stuck = try? await self.coordinator.hasStaleRunnerLeases(jobID: jobID), stuck else { return }
                NoteImportPerformanceLog.event("Stuck Runner Replaced", jobID: jobID)
                await self.replaceRunner(jobID: jobID)
            }
            return
        }
        errors.removeValue(forKey: jobID)
        states[jobID] = recovering ? .recovering : .starting
        let coordinator = self.coordinator
        let generation = (taskGenerations[jobID] ?? 0) + 1
        taskGenerations[jobID] = generation
        if recovering {
            NoteImportPerformanceLog.event("Recovery Runner Registered", jobID: jobID)
        } else {
            NoteImportPerformanceLog.event("Runner Registered", jobID: jobID)
        }
        tasks[jobID] = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.markRunning(jobID: jobID)
            do {
                _ = try await coordinator.execute(jobID: jobID)
                await self.finish(jobID: jobID, error: nil, generation: generation)
            } catch is CancellationError {
                await self.finish(jobID: jobID, error: nil, generation: generation)
            } catch {
                await self.finish(jobID: jobID, error: error, generation: generation)
            }
        }
    }

    private func replaceRunner(jobID: String) {
        let zombie = tasks.removeValue(forKey: jobID)
        zombie?.cancel()
        ensureRunning(jobID: jobID, recovering: true)
    }

    private func markRunning(jobID: String) {
        states[jobID] = .running
    }

    private func finish(jobID: String, error: Error?, generation: Int) {
        // 旧代（已被看门狗替换的僵尸）完成时忽略，避免清理新 runner 的状态。
        guard taskGenerations[jobID] == generation else { return }
        tasks.removeValue(forKey: jobID)
        states.removeValue(forKey: jobID)
        if let error {
            errors[jobID] = String(describing: error)
            NoteImportPerformanceLog.event("Runner Failed", jobID: jobID)
        } else {
            NoteImportPerformanceLog.event("Runner Finished", jobID: jobID)
        }
    }
}
