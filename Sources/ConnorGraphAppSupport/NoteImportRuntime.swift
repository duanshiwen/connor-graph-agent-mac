import Foundation
import ConnorGraphCore

public enum NoteImportRuntimeEvent: Sendable, Equatable {
    case ledgerChanged(jobID: String?)
    case noteSessionCreated(jobID: String, itemID: String, sessionID: String)
    case jobFailed(jobID: String, message: String)
}

/// App-owned execution boundary for note imports. UI objects submit commands and observe
/// events, but do not own the worker tasks themselves.
public actor NoteImportRuntime {
    private let ledger: AppNoteImportRepository
    private let coordinator: NoteImportCoordinator
    private var tasks: [String: Task<Void, Never>] = [:]
    private var continuations: [UUID: AsyncStream<NoteImportRuntimeEvent>.Continuation] = [:]

    public init(ledger: AppNoteImportRepository, coordinator: NoteImportCoordinator) {
        self.ledger = ledger
        self.coordinator = coordinator
    }

    deinit {
        for task in tasks.values { task.cancel() }
        for continuation in continuations.values { continuation.finish() }
    }

    public func events() -> AsyncStream<NoteImportRuntimeEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    @discardableResult
    public func submit(jobID: String) -> Bool {
        guard tasks[jobID] == nil else { return false }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.run(jobID: jobID)
        }
        tasks[jobID] = task
        yield(.ledgerChanged(jobID: jobID))
        return true
    }

    public func recover() throws {
        for job in try ledger.recoverableJobs() where shouldAutomaticallyRecover(job) {
            _ = submit(jobID: job.id)
        }
    }

    public func pause(jobID: String) async throws {
        try await coordinator.pause(jobID: jobID)
        yield(.ledgerChanged(jobID: jobID))
    }

    public func resume(jobID: String) async throws {
        try await coordinator.resume(jobID: jobID)
        _ = submit(jobID: jobID)
        yield(.ledgerChanged(jobID: jobID))
    }

    public func cancel(jobID: String) async throws {
        try await coordinator.cancel(jobID: jobID)
        tasks[jobID]?.cancel()
        yield(.ledgerChanged(jobID: jobID))
    }

    public func isRunning(jobID: String) -> Bool { tasks[jobID] != nil }

    private func run(jobID: String) async {
        let monitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                await self?.yield(.ledgerChanged(jobID: jobID))
            }
        }
        defer {
            monitor.cancel()
            tasks.removeValue(forKey: jobID)
            yield(.ledgerChanged(jobID: jobID))
        }
        do {
            _ = try await coordinator.execute(jobID: jobID)
        } catch is CancellationError {
            if let job = try? ledger.job(id: jobID), job.status == .cancelling {
                _ = try? ledger.transitionJob(id: jobID, to: .cancelled)
            }
        } catch {
            let message = String(describing: error)
            if let job = try? ledger.job(id: jobID), !job.status.isTerminal {
                var failed = job
                failed.errorMessage = message
                failed.updatedAt = Date()
                try? ledger.saveJob(failed)
                _ = try? ledger.transitionJob(id: jobID, to: .failed)
            }
            yield(.jobFailed(jobID: jobID, message: message))
        }
    }

    private func shouldAutomaticallyRecover(_ job: NoteImportJobRecord) -> Bool {
        guard job.pauseRequestedAt == nil, job.cancelRequestedAt == nil else { return false }
        // Jobs are created only after the user confirms the wizard. A job that reached
        // awaitingReview has therefore already been approved for import.
        return [.awaitingReview, .ready, .importing, .processing].contains(job.status)
    }

    private func yield(_ event: NoteImportRuntimeEvent) {
        for continuation in continuations.values { continuation.yield(event) }
    }

    private func removeContinuation(_ id: UUID) { continuations.removeValue(forKey: id) }
}
