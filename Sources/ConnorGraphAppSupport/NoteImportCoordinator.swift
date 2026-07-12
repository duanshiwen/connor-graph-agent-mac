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
    private var pausedJobs: Set<String> = []
    private var cancelledJobs: Set<String> = []

    public init(ledger: AppNoteImportRepository, sessionService: HeadlessNoteSessionService) {
        self.ledger = ledger; self.sessionService = sessionService
    }

    public func scan(jobID: String, adapter: any NoteImportSourceAdapter, request: NoteImportScanRequest) async throws -> NoteImportJobRecord {
        _ = try ledger.transitionJob(id: jobID, to: .scanning)
        var job = try requireJob(jobID)
        for try await note in adapter.scan(request) {
            try Task.checkCancellation()
            if cancelledJobs.contains(jobID) { break }
            let status: NoteImportItemStatus = note.diagnostics.contains { $0.code == .decodingAmbiguous } ? .needsEncodingReview : .ready
            let item = NoteImportItemRecord(jobID: jobID, sourceID: request.sourceID, sourceIdentity: note.sourceIdentity, externalID: note.externalID, relativePath: note.relativePath, title: note.title, status: status, rawByteHash: note.rawByteHash, normalizedTextHash: note.normalizedTextHash, sourceEncoding: note.sourceMetadata["encoding"], encodingConfidence: confidence(note.sourceMetadata["encoding_confidence"]), decoderVersion: note.sourceMetadata["decoder_version"], metadata: ["content": note.markdownContent])
            do { try ledger.saveItem(item); job.discoveredCount += 1 } catch { job.duplicateCount += 1 }
            job.updatedAt = Date(); try ledger.saveJob(job)
        }
        if cancelledJobs.contains(jobID) { return try ledger.transitionJob(id: jobID, to: .cancelling) }
        return try ledger.transitionJob(id: jobID, to: .awaitingReview)
    }

    public func execute(jobID: String) async throws -> NoteImportJobRecord {
        var job = try requireJob(jobID)
        if job.status == .awaitingReview { job = try ledger.transitionJob(id: jobID, to: .ready) }
        if job.status == .ready { job = try ledger.transitionJob(id: jobID, to: .importing) }
        for item in try ledger.items(jobID: jobID, statuses: [.ready, .duplicateChanged]) {
            while pausedJobs.contains(jobID) { try await Task.sleep(for: .milliseconds(200)) }
            if cancelledJobs.contains(jobID) { _ = try ledger.transitionJob(id: jobID, to: .cancelling); return try ledger.transitionJob(id: jobID, to: .cancelled) }
            do {
                _ = try ledger.transitionItem(id: item.id, to: .creatingSession)
                let session = try await sessionService.createNoteSession(title: item.title)
                var imported = try requireItem(item.id); imported.sessionID = session.id; imported.status = .imported; imported.updatedAt = Date(); try ledger.saveItem(imported)
                if job.options.llmMode == .automatic {
                    _ = try ledger.transitionItem(id: item.id, to: .queuedForLLM)
                    _ = try ledger.transitionItem(id: item.id, to: .runningLLM)
                    _ = try await sessionService.run(.init(sessionID: session.id, prompt: item.metadata["content"] ?? ""))
                }
                _ = try ledger.transitionItem(id: item.id, to: .completed)
                job.importedCount += 1
            } catch {
                var failed = try requireItem(item.id); failed.status = failed.sessionID == nil ? .sessionFailed : .llmFailed; failed.errorMessage = String(describing: error); failed.updatedAt = Date(); try ledger.saveItem(failed); job.failedCount += 1
            }
            job.updatedAt = Date(); try ledger.saveJob(job)
        }
        if job.status == .importing && job.options.llmMode == .automatic { job = try ledger.transitionJob(id: jobID, to: .processing) }
        return try ledger.transitionJob(id: jobID, to: job.failedCount > 0 ? .completedWithIssues : .completed)
    }

    public func pause(jobID: String) { pausedJobs.insert(jobID) }
    public func resume(jobID: String) { pausedJobs.remove(jobID) }
    public func cancel(jobID: String) { cancelledJobs.insert(jobID); pausedJobs.remove(jobID) }
    public func recoverableJobs() throws -> [NoteImportJobRecord] { try ledger.recoverableJobs() }
    public func progress(jobID: String) throws -> NoteImportProgress { let job = try requireJob(jobID); let items = try ledger.items(jobID: jobID); return .init(jobID: jobID, status: job.status, discovered: job.discoveredCount, imported: job.importedCount, completed: items.filter { $0.status == .completed }.count, failed: job.failedCount) }
    private func requireJob(_ id: String) throws -> NoteImportJobRecord { guard let value = try ledger.job(id: id) else { throw AppNoteImportRepositoryError.jobNotFound(id) }; return value }
    private func requireItem(_ id: String) throws -> NoteImportItemRecord { guard let value = try ledger.item(id: id) else { throw AppNoteImportRepositoryError.itemNotFound(id) }; return value }
    private func confidence(_ value: String?) -> Double? { switch value { case "certain": 1; case "high": 0.9; case "medium": 0.7; case "low": 0.4; case "ambiguous": 0.2; default: nil } }
}
