import Foundation
import ConnorGraphCore

public struct NoteImportProgress: Sendable, Equatable {
    public var jobID: String
    public var status: NoteImportJobStatus
    public var discovered: Int
    public var imported: Int
    public var completed: Int
    public var failed: Int
}

public actor NoteImportCoordinator {
    private let ledger: AppNoteImportRepository
    private let sessionService: HeadlessNoteSessionService
    private let schedulerVersion = "1"

    public init(ledger: AppNoteImportRepository, sessionService: HeadlessNoteSessionService) {
        self.ledger = ledger; self.sessionService = sessionService
    }

    public func scan(jobID: String, adapter: any NoteImportSourceAdapter, request: NoteImportScanRequest) async throws -> NoteImportJobRecord {
        _ = try ledger.transitionJob(id: jobID, to: .scanning)
        var job = try requireJob(jobID)
        for try await note in adapter.scan(request) {
            try Task.checkCancellation()
            if try requireJob(jobID).cancelRequestedAt != nil { break }
            let status: NoteImportItemStatus = note.diagnostics.contains { $0.code == .decodingAmbiguous } ? .needsEncodingReview : .ready
            let item = NoteImportItemRecord(jobID: jobID, sourceID: request.sourceID, sourceIdentity: note.sourceIdentity, externalID: note.externalID, relativePath: note.relativePath, title: note.title, status: status, rawByteHash: note.rawByteHash, normalizedTextHash: note.normalizedTextHash, sourceEncoding: note.sourceMetadata["encoding"], encodingConfidence: confidence(note.sourceMetadata["encoding_confidence"]), decoderVersion: note.sourceMetadata["decoder_version"], metadata: ["content": note.markdownContent])
            do { try ledger.saveItem(item); job.discoveredCount += 1 } catch { job.duplicateCount += 1 }
            job.updatedAt = Date(); try ledger.saveJob(job)
        }
        if try requireJob(jobID).cancelRequestedAt != nil { return try ledger.transitionJob(id: jobID, to: .cancelling) }
        return try ledger.transitionJob(id: jobID, to: .awaitingReview)
    }

    public func execute(jobID: String) async throws -> NoteImportJobRecord {
        var job = try requireJob(jobID)
        _ = try ledger.reconcileInterruptedItems(jobID: jobID)
        _ = try ledger.heartbeat(jobID: jobID, schedulerVersion: schedulerVersion)
        if job.status == .awaitingReview { job = try ledger.transitionJob(id: jobID, to: .ready) }
        if job.status == .ready { job = try ledger.transitionJob(id: jobID, to: .importing) }
        let scheduler = NoteImportExecutionScheduler(configuration: .init(concurrency: job.options.llmConcurrency))
        let llmMode = job.options.llmMode
        let pending = try ledger.items(jobID: jobID, statuses: [.ready, .duplicateChanged])
        let results = await scheduler.run(elements: pending) { [ledger, sessionService, llmMode] item in
            let control = try ledger.job(id: jobID)
            if control?.cancelRequestedAt != nil { throw CancellationError() }
            while try ledger.job(id: jobID)?.pauseRequestedAt != nil { try await Task.sleep(for: .milliseconds(200)) }
            do {
                _ = try ledger.transitionItem(id: item.id, to: .creatingSession)
                let session = try await sessionService.createNoteSession(title: item.title)
                guard var imported = try ledger.item(id: item.id) else { throw AppNoteImportRepositoryError.itemNotFound(item.id) }; imported.sessionID = session.id; imported.status = .imported; imported.updatedAt = Date(); try ledger.saveItem(imported)
                if llmMode == .automatic {
                    _ = try ledger.transitionItem(id: item.id, to: .queuedForLLM)
                    _ = try ledger.transitionItem(id: item.id, to: .runningLLM)
                    _ = try await sessionService.run(.init(sessionID: session.id, prompt: item.metadata["content"] ?? ""))
                }
                _ = try ledger.transitionItem(id: item.id, to: .completed)
                return true
            } catch {
                guard !(error is CancellationError) else { throw error }
                guard var failed = try ledger.item(id: item.id) else { throw error }; failed.status = failed.sessionID == nil ? .sessionFailed : .llmFailed; failed.errorMessage = String(describing: error); failed.updatedAt = Date(); try ledger.saveItem(failed); return false
            }
        }
        job = try requireJob(jobID)
        if job.cancelRequestedAt != nil { if job.status != .cancelling { job = try ledger.transitionJob(id: jobID, to: .cancelling) }; return try ledger.transitionJob(id: jobID, to: .cancelled) }
        job.importedCount += results.reduce(0) { count, result in count + ((try? result.get()) == true ? 1 : 0) }
        job.failedCount += results.reduce(0) { count, result in count + ((try? result.get()) == false ? 1 : 0) }
        job.updatedAt = Date(); try ledger.saveJob(job)
        if job.status == .importing && job.options.llmMode == .automatic { job = try ledger.transitionJob(id: jobID, to: .processing) }
        return try ledger.transitionJob(id: jobID, to: job.failedCount > 0 ? .completedWithIssues : .completed)
    }

    public func pause(jobID: String) throws { _ = try ledger.requestPause(jobID: jobID) }
    public func resume(jobID: String) throws { guard var job = try ledger.job(id: jobID) else { throw AppNoteImportRepositoryError.jobNotFound(jobID) }; job.pauseRequestedAt = nil; job.resumedAt = Date(); job.updatedAt = Date(); try ledger.saveJob(job) }
    public func cancel(jobID: String) async throws { _ = try ledger.requestCancel(jobID: jobID); for item in try ledger.items(jobID: jobID, statuses: [.runningLLM]) { if let sessionID = item.sessionID { await sessionService.cancel(sessionID: sessionID) } } }
    public func recoverableJobs() throws -> [NoteImportJobRecord] { try ledger.recoverableJobs() }
    public func progress(jobID: String) throws -> NoteImportProgress { let job = try requireJob(jobID); let items = try ledger.items(jobID: jobID); return .init(jobID: jobID, status: job.status, discovered: job.discoveredCount, imported: job.importedCount, completed: items.filter { $0.status == .completed }.count, failed: job.failedCount) }
    private func requireJob(_ id: String) throws -> NoteImportJobRecord { guard let value = try ledger.job(id: id) else { throw AppNoteImportRepositoryError.jobNotFound(id) }; return value }
    private func requireItem(_ id: String) throws -> NoteImportItemRecord { guard let value = try ledger.item(id: id) else { throw AppNoteImportRepositoryError.itemNotFound(id) }; return value }
    private func confidence(_ value: String?) -> Double? { switch value { case "certain": 1; case "high": 0.9; case "medium": 0.7; case "low": 0.4; case "ambiguous": 0.2; default: nil } }
}
