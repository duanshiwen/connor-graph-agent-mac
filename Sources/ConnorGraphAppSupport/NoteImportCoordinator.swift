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
        if job.cancelRequestedAt != nil { return try finalizeCancellation(jobID: jobID) }
        if job.pauseRequestedAt != nil || job.status == .paused { return job }
        if job.status == .awaitingReview { job = try ledger.transitionJob(id: jobID, to: .ready) }
        if job.status == .ready { job = try ledger.transitionJob(id: jobID, to: .importing) }
        if job.status == .importing && job.options.llmMode == .automatic {
            job = try ledger.transitionJob(id: jobID, to: .processing)
        }

        let executionConcurrency = job.options.llmMode == .automatic ? job.options.llmConcurrency : 1
        let scheduler = NoteImportExecutionScheduler(configuration: .init(concurrency: executionConcurrency))
        let pending = try ledger.items(
            jobID: jobID,
            statuses: [.ready, .duplicateChanged, .imported, .queuedForLLM]
        )
        let options = job.options
        let payloadStore = self.payloadStore
        _ = await scheduler.run(elements: pending) { [ledger, sessionService, attachmentImporter, payloadStore, options] item in
            let itemInterval = NoteImportPerformanceLog.begin("Import Item", jobID: jobID, itemCount: 1)
            defer { NoteImportPerformanceLog.end(itemInterval, jobID: jobID, itemCount: 1) }
            if try ledger.job(id: jobID)?.cancelRequestedAt != nil { throw CancellationError() }
            while let control = try ledger.job(id: jobID), control.pauseRequestedAt != nil {
                if control.cancelRequestedAt != nil { throw CancellationError() }
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(200))
            }
            do {
                let note = try Self.decodePayload(item, payloadStore: payloadStore)
                var current = try ledger.item(id: item.id) ?? item
                var attachmentRefs: [AgentMessageAttachmentRef] = []
                var savedOriginalContent = false

                if [.ready, .duplicateChanged].contains(current.status) {
                    _ = try ledger.transitionItem(id: current.id, to: .creatingSession)
                    let canCreateInSingleWrite = options.llmMode != .automatic
                        && (!options.importAttachments || note.attachments.isEmpty)
                    let session: AgentSession
                    if canCreateInSingleWrite {
                        session = try await sessionService.createImportedNoteSession(
                            title: current.title,
                            content: note.markdownContent,
                            createdAt: note.createdAt ?? Date()
                        )
                        savedOriginalContent = true
                    } else {
                        session = try await sessionService.createNoteSession(title: current.title)
                        if options.importAttachments, let attachmentImporter {
                            attachmentRefs = try await attachmentImporter
                                .importAttachments(note.attachments, sessionID: session.id)
                                .map(\.messageRef)
                        }
                    }
                    guard var imported = try ledger.item(id: current.id) else {
                        throw AppNoteImportRepositoryError.itemNotFound(current.id)
                    }
                    imported.sessionID = session.id
                    imported.status = .imported
                    imported.updatedAt = Date()
                    try ledger.saveItem(imported)
                    current = imported
                }

                guard let sessionID = current.sessionID else {
                    throw AppNoteImportRepositoryError.itemNotFound("Missing session for item \(current.id)")
                }
                if options.llmMode == .automatic {
                    if current.status == .imported {
                        current = try ledger.transitionItem(id: current.id, to: .queuedForLLM)
                    }
                    if current.status == .queuedForLLM {
                        current = try ledger.transitionItem(id: current.id, to: .runningLLM)
                    }
                    _ = try await sessionService.run(.init(
                        sessionID: sessionID,
                        prompt: note.markdownContent,
                        attachmentIDs: attachmentRefs.map(\.id),
                        allowNetworkReadTools: options.allowNetworkReadTools
                    ))
                } else if !savedOriginalContent && current.status == .imported {
                    _ = try await sessionService.saveImportedNote(
                        sessionID: sessionID,
                        content: note.markdownContent,
                        attachments: attachmentRefs,
                        createdAt: note.createdAt ?? Date()
                    )
                }
                _ = try ledger.transitionItem(id: current.id, to: .completed)
                return true
            } catch {
                guard !(error is CancellationError) else { throw error }
                guard var failed = try ledger.item(id: item.id) else { throw error }
                failed.status = failed.sessionID == nil ? .sessionFailed : .llmFailed
                failed.errorMessage = String(describing: error)
                failed.updatedAt = Date()
                try ledger.saveItem(failed)
                return false
            }
        }

        job = try requireJob(jobID)
        if job.cancelRequestedAt != nil { return try finalizeCancellation(jobID: jobID) }
        if job.pauseRequestedAt != nil { return job }
        job = try ledger.recalculateJobCounts(jobID: jobID)
        let remaining = try ledger.items(
            jobID: jobID,
            statuses: [.ready, .duplicateChanged, .creatingSession, .imported, .queuedForLLM, .runningLLM]
        )
        guard remaining.isEmpty else { return job }
        return try ledger.transitionJob(id: jobID, to: job.failedCount > 0 ? .completedWithIssues : .completed)
    }

    private func finalizeCancellation(jobID: String) throws -> NoteImportJobRecord {
        var job = try requireJob(jobID)
        if [.scanning, .importing, .processing, .paused].contains(job.status) {
            job = try ledger.transitionJob(id: jobID, to: .cancelling)
        }
        _ = try ledger.cancelRemainingItems(jobID: jobID)
        _ = try ledger.recalculateJobCounts(jobID: jobID)
        return try ledger.transitionJob(id: jobID, to: .cancelled)
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
