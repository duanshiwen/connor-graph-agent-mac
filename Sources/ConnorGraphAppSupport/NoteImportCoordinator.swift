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
    private let attachmentImporter: NoteImportAttachmentImporter?
    private let payloadStore: NoteImportPayloadStore?
    private let schedulerVersion = "2"
    private static let payloadMetadataKey = "imported_note_payload"
    private static let scanBatchSize = 50

    public init(
        ledger: AppNoteImportRepository,
        sessionService: HeadlessNoteSessionService,
        attachmentImporter: NoteImportAttachmentImporter? = nil,
        payloadStore: NoteImportPayloadStore? = nil
    ) {
        self.ledger = ledger
        self.sessionService = sessionService
        self.attachmentImporter = attachmentImporter
        self.payloadStore = payloadStore
    }

    public func scan(jobID: String, adapter: any NoteImportSourceAdapter, request: NoteImportScanRequest) async throws -> NoteImportJobRecord {
        let interval = NoteImportPerformanceLog.begin("Import Scan", jobID: jobID)
        defer { NoteImportPerformanceLog.end(interval, jobID: jobID) }
        _ = try ledger.transitionJob(id: jobID, to: .scanning)
        var batch: [NoteImportItemRecord] = []
        batch.reserveCapacity(Self.scanBatchSize)

        for try await note in adapter.scan(request) {
            try Task.checkCancellation()
            if try requireJob(jobID).cancelRequestedAt != nil { break }
            let status: NoteImportItemStatus = note.diagnostics.contains { $0.code == .decodingAmbiguous || $0.code == .decodingFailed } ? .needsEncodingReview : .ready
            let itemID = UUID().uuidString
            let metadata: [String: String]
            if let payloadStore {
                metadata = try payloadStore.save(note, jobID: jobID, itemID: itemID)
            } else {
                metadata = [Self.payloadMetadataKey: try Self.encodePayload(note)]
            }
            batch.append(NoteImportItemRecord(id: itemID, jobID: jobID, sourceID: request.sourceID, sourceIdentity: note.sourceIdentity, externalID: note.externalID, relativePath: note.relativePath, title: note.title, status: status, rawByteHash: note.rawByteHash, normalizedTextHash: note.normalizedTextHash, sourceEncoding: note.sourceMetadata["encoding"], encodingConfidence: confidence(note.sourceMetadata["encoding_confidence"]), decoderVersion: note.sourceMetadata["decoder_version"], metadata: metadata))
            if batch.count >= Self.scanBatchSize {
                let items = batch
                batch.removeAll(keepingCapacity: true)
                _ = try ledger.appendScannedItems(jobID: jobID, items: items)
                NoteImportPerformanceLog.event("Scan Batch", jobID: jobID, itemCount: items.count)
                await Task.yield()
            }
        }
        if !batch.isEmpty {
            _ = try ledger.appendScannedItems(jobID: jobID, items: batch)
            NoteImportPerformanceLog.event("Scan Batch", jobID: jobID, itemCount: batch.count)
            await Task.yield()
        }
        if try requireJob(jobID).cancelRequestedAt != nil { return try ledger.transitionJob(id: jobID, to: .cancelling) }
        return try ledger.transitionJob(id: jobID, to: .awaitingReview)
    }

    public func execute(jobID: String) async throws -> NoteImportJobRecord {
        let interval = NoteImportPerformanceLog.begin("Import Execute", jobID: jobID)
        defer { NoteImportPerformanceLog.end(interval, jobID: jobID) }
        var job = try requireJob(jobID)
        _ = try ledger.reconcileInterruptedItems(jobID: jobID)
        _ = try ledger.heartbeat(jobID: jobID, schedulerVersion: schedulerVersion)
        if job.status == .awaitingReview { job = try ledger.transitionJob(id: jobID, to: .ready) }
        if job.status == .ready { job = try ledger.transitionJob(id: jobID, to: .importing) }
        let llmMode = job.options.llmMode
        let executionConcurrency = llmMode == .automatic ? job.options.llmConcurrency : 1
        let scheduler = NoteImportExecutionScheduler(configuration: .init(concurrency: executionConcurrency))
        let pending = try ledger.items(jobID: jobID, statuses: [.ready, .duplicateChanged])
        let options = job.options
        let payloadStore = self.payloadStore
        let results = await scheduler.run(elements: pending) { [ledger, sessionService, attachmentImporter, payloadStore, llmMode, options] item in
            let itemInterval = NoteImportPerformanceLog.begin("Import Item", jobID: jobID, itemCount: 1)
            defer { NoteImportPerformanceLog.end(itemInterval, jobID: jobID, itemCount: 1) }
            let control = try ledger.job(id: jobID)
            if control?.cancelRequestedAt != nil { throw CancellationError() }
            while try ledger.job(id: jobID)?.pauseRequestedAt != nil { try await Task.sleep(for: .milliseconds(200)) }
            do {
                _ = try ledger.transitionItem(id: item.id, to: .creatingSession)
                let note = try Self.decodePayload(item, payloadStore: payloadStore)
                let canCreateInSingleWrite = llmMode != .automatic
                    && (!options.importAttachments || note.attachments.isEmpty)
                let session: AgentSession
                var attachmentRefs: [AgentMessageAttachmentRef] = []
                if canCreateInSingleWrite {
                    session = try await sessionService.createImportedNoteSession(
                        title: item.title,
                        content: note.markdownContent,
                        createdAt: note.createdAt ?? Date()
                    )
                } else {
                    session = try await sessionService.createNoteSession(title: item.title)
                    if options.importAttachments, let attachmentImporter {
                        attachmentRefs = try await attachmentImporter.importAttachments(note.attachments, sessionID: session.id).map(\.messageRef)
                    }
                }
                guard var imported = try ledger.item(id: item.id) else { throw AppNoteImportRepositoryError.itemNotFound(item.id) }
                imported.sessionID = session.id
                imported.status = .imported
                imported.updatedAt = Date()
                try ledger.saveItem(imported)
                if llmMode == .automatic {
                    _ = try ledger.transitionItem(id: item.id, to: .queuedForLLM)
                    _ = try ledger.transitionItem(id: item.id, to: .runningLLM)
                    _ = try await sessionService.run(.init(
                        sessionID: session.id,
                        prompt: note.markdownContent,
                        attachmentIDs: attachmentRefs.map(\.id),
                        allowNetworkReadTools: options.allowNetworkReadTools
                    ))
                } else if !canCreateInSingleWrite {
                    _ = try await sessionService.saveImportedNote(
                        sessionID: session.id,
                        content: note.markdownContent,
                        attachments: attachmentRefs,
                        createdAt: note.createdAt ?? Date()
                    )
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
    public func resume(jobID: String) throws { _ = try ledger.resumeJob(jobID: jobID) }
    public func cancel(jobID: String) async throws { _ = try ledger.requestCancel(jobID: jobID); for item in try ledger.items(jobID: jobID, statuses: [.runningLLM]) { if let sessionID = item.sessionID { await sessionService.cancel(sessionID: sessionID) } } }
    public func recoverableJobs() throws -> [NoteImportJobRecord] { try ledger.recoverableJobs() }
    public func progress(jobID: String) throws -> NoteImportProgress { let job = try requireJob(jobID); let items = try ledger.items(jobID: jobID); return .init(jobID: jobID, status: job.status, discovered: job.discoveredCount, imported: job.importedCount, completed: items.filter { $0.status == .completed }.count, failed: job.failedCount) }
    private func requireJob(_ id: String) throws -> NoteImportJobRecord { guard let value = try ledger.job(id: id) else { throw AppNoteImportRepositoryError.jobNotFound(id) }; return value }
    private func requireItem(_ id: String) throws -> NoteImportItemRecord { guard let value = try ledger.item(id: id) else { throw AppNoteImportRepositoryError.itemNotFound(id) }; return value }
    private func confidence(_ value: String?) -> Double? { switch value { case "certain": 1; case "high": 0.9; case "medium": 0.7; case "low": 0.4; case "ambiguous": 0.2; default: nil } }

    private static func encodePayload(_ note: ImportedNote) throws -> String {
        let interval = NoteImportPerformanceLog.begin("Payload Encode", jobID: "preview")
        defer { NoteImportPerformanceLog.end(interval, jobID: "preview") }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(note).base64EncodedString()
    }

    private static func decodePayload(_ item: NoteImportItemRecord, payloadStore: NoteImportPayloadStore?) throws -> ImportedNote {
        let interval = NoteImportPerformanceLog.begin("Payload Decode", jobID: item.jobID)
        defer { NoteImportPerformanceLog.end(interval, jobID: item.jobID) }
        if let payloadStore, let staged = try payloadStore.load(metadata: item.metadata) {
            return staged
        }
        guard let encoded = item.metadata[payloadMetadataKey], let data = Data(base64Encoded: encoded) else {
            throw NoteImportErrorCode.internalInvariantViolation
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ImportedNote.self, from: data)
    }
}
