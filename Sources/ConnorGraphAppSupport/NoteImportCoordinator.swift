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
    private let sourceAccessService: NoteImportSourceAccessService
    private let rateLimiter: NoteImportProviderRateLimiter
    private let retryPolicy: NoteImportRetryPolicy
    private let onSessionImported: @Sendable (AgentSession) -> Void
    private let schedulerVersion = "2"
    private var activeSchedulers: [String: NoteImportExecutionScheduler] = [:]
    private static let payloadMetadataKey = "imported_note_payload"
    private static let scanBatchSize = 50

    public init(
        ledger: AppNoteImportRepository,
        sessionService: HeadlessNoteSessionService,
        attachmentImporter: NoteImportAttachmentImporter? = nil,
        payloadStore: NoteImportPayloadStore? = nil,
        sourceAccessService: NoteImportSourceAccessService = .init(),
        rateLimiter: NoteImportProviderRateLimiter = .init(),
        retryPolicy: NoteImportRetryPolicy = .init(maxAttempts: 20),
        onSessionImported: @escaping @Sendable (AgentSession) -> Void = { _ in }
    ) {
        self.ledger = ledger
        self.sessionService = sessionService
        self.attachmentImporter = attachmentImporter
        self.payloadStore = payloadStore
        self.sourceAccessService = sourceAccessService
        self.rateLimiter = rateLimiter
        self.retryPolicy = retryPolicy
        self.onSessionImported = onSessionImported
    }

    public func prepareImport(
        sourceURL: URL,
        kind: NoteImportSourceKind,
        options: NoteImportOptions
    ) throws -> NoteImportJobRecord {
        let standardizedPath = sourceURL.standardizedFileURL.path
        var source = try ledger.sources().first {
            $0.kind == kind && $0.metadata["authorized_path"] == standardizedPath
        } ?? NoteImportSourceRecord(
            kind: kind,
            displayName: sourceURL.deletingPathExtension().lastPathComponent
        )
        source = try sourceAccessService.authorize(url: sourceURL, source: source)
        try ledger.saveSource(source)
        var flattenedOptions = options
        flattenedOptions.preserveHierarchy = false
        let job = NoteImportJobRecord(sourceID: source.id, options: flattenedOptions)
        try ledger.saveJob(job)
        return job
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
            var status: NoteImportItemStatus = note.diagnostics.contains { $0.code == .decodingAmbiguous || $0.code == .decodingFailed } ? .needsEncodingReview : .ready
            let itemID = UUID().uuidString
            var metadata: [String: String]
            if let payloadStore {
                metadata = try payloadStore.save(note, jobID: jobID, itemID: itemID)
            } else {
                metadata = [Self.payloadMetadataKey: try Self.encodePayload(note)]
            }
            var previousSessionID: String?
            if status == .ready, request.options.duplicatePolicy != .createCopy,
               let previous = try ledger.latestItem(sourceID: request.sourceID, sourceIdentity: note.sourceIdentity) {
                previousSessionID = previous.sessionID ?? previous.metadata["previous_session_id"]
                metadata["previous_item_id"] = previous.id
                if let previousSessionID { metadata["previous_session_id"] = previousSessionID }
                if previous.normalizedTextHash == note.normalizedTextHash {
                    status = .duplicateUnchanged
                } else if request.options.duplicatePolicy == .appendUpdate {
                    status = .duplicateChanged
                }
            }
            batch.append(NoteImportItemRecord(id: itemID, jobID: jobID, sourceID: request.sourceID, sourceIdentity: note.sourceIdentity, externalID: note.externalID, relativePath: note.relativePath, title: note.title, status: status, sessionID: request.options.duplicatePolicy == .appendUpdate ? previousSessionID : nil, rawByteHash: note.rawByteHash, normalizedTextHash: note.normalizedTextHash, sourceEncoding: note.sourceMetadata["encoding"], encodingConfidence: confidence(note.sourceMetadata["encoding_confidence"]), decoderVersion: note.sourceMetadata["decoder_version"], metadata: metadata))
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
        _ = try ledger.recalculateJobCounts(jobID: jobID)
        if try requireJob(jobID).cancelRequestedAt != nil { return try ledger.transitionJob(id: jobID, to: .cancelling) }
        return try ledger.transitionJob(id: jobID, to: .awaitingReview)
    }

    public func execute(jobID: String) async throws -> NoteImportJobRecord {
        let interval = NoteImportPerformanceLog.begin("Import Execute", jobID: jobID)
        defer { NoteImportPerformanceLog.end(interval, jobID: jobID) }
        var job = try requireJob(jobID)
        if job.status == .completedWithIssues {
            job = try reopenFailedItems(jobID: jobID, options: job.options)
        }
        _ = try ledger.reconcileInterruptedItems(jobID: jobID)
        job = try ledger.recalculateJobCounts(jobID: jobID)
        _ = try ledger.heartbeat(jobID: jobID, schedulerVersion: schedulerVersion)
        if job.cancelRequestedAt != nil { return try finalizeCancellationAndCleanup(jobID: jobID) }
        if job.pauseRequestedAt != nil || job.status == .paused { return job }
        if job.status == .awaitingReview { job = try ledger.transitionJob(id: jobID, to: .ready) }
        if job.status == .ready { job = try ledger.transitionJob(id: jobID, to: .importing) }
        if job.status == .importing && job.options.llmMode == .automatic {
            job = try ledger.transitionJob(id: jobID, to: .processing)
        }

        let source = try ledger.source(id: job.sourceID)
        let sourceLease = try source.flatMap { source in
            source.locationBookmark == nil ? nil : try sourceAccessService.access(source: source)
        }
        defer { sourceLease?.release() }
        let enexLease = NoteImportSourceAccessLease(
            rootURL: FileManager.default.temporaryDirectory.appendingPathComponent("connor-enex-resources", isDirectory: true),
            didStart: false
        )

        let executionConcurrency = job.options.llmMode == .automatic ? job.options.llmConcurrency : 1
        let scheduler = NoteImportExecutionScheduler(configuration: .init(concurrency: executionConcurrency))
        activeSchedulers[jobID] = scheduler
        defer { activeSchedulers.removeValue(forKey: jobID) }
        let pending = try ledger.items(
            jobID: jobID,
            statuses: [.ready, .duplicateChanged, .imported, .queuedForLLM]
        )
        let options = job.options
        let payloadStore = self.payloadStore
        let retryPolicy = self.retryPolicy
        let rateLimiter = self.rateLimiter
        let providerKey = NoteImportProviderKey(connection: "note-import", provider: "active-runtime", model: "active")
        await rateLimiter.configure(.init(maxConcurrent: options.llmConcurrency, requestsPerMinute: 60), for: providerKey)
        _ = await scheduler.run(elements: pending) { [ledger, sessionService, attachmentImporter, payloadStore, options, sourceLease, enexLease, retryPolicy, rateLimiter, onSessionImported] item in
            let itemInterval = NoteImportPerformanceLog.begin("Import Item", jobID: jobID, itemCount: 1)
            defer { NoteImportPerformanceLog.end(itemInterval, jobID: jobID, itemCount: 1) }
            let owner = "\(jobID):\(UUID().uuidString)"
            while true {
                try await Self.waitForJobControl(jobID: jobID, ledger: ledger)
                guard var current = try ledger.item(id: item.id) else { return false }
                if let retryAt = current.nextRetryAt, retryAt > Date() {
                    try await Self.sleep(retryAt.timeIntervalSinceNow)
                }
                guard let claimed = try ledger.claimItem(id: current.id, owner: owner, leaseDuration: 300) else { return false }
                current = claimed
                var limiterAcquired = false
                do {
                    let note = try Self.decodePayload(current, payloadStore: payloadStore)
                    let sessionID = current.sessionID ?? "note-import-session:\(current.id)"
                    let messageID = "note-import-message:\(current.id)"

                    if [.ready, .duplicateChanged].contains(current.status) {
                        current = try ledger.transitionItem(id: current.id, to: .creatingSession)
                        let importedSession = try await sessionService.createImportedNoteSession(
                            id: sessionID,
                            title: current.title,
                            content: note.markdownContent,
                            messageID: messageID,
                            createdAt: note.createdAt ?? current.createdAt
                        )
                        onSessionImported(importedSession)
                        current.sessionID = sessionID
                        current.status = .imported
                        current.errorCode = nil
                        current.errorMessage = nil
                        current.updatedAt = Date()
                        try ledger.saveItem(current)
                    }

                    guard let boundSessionID = current.sessionID else {
                        throw AppNoteImportRepositoryError.itemNotFound("Missing session for item \(current.id)")
                    }
                    if current.status == .imported {
                        var attachmentRefs: [AgentMessageAttachmentRef] = []
                        if options.importAttachments, let attachmentImporter, !note.attachments.isEmpty {
                            let authorizedRoot = note.sourceKind == .evernoteENEX ? enexLease : sourceLease
                            attachmentRefs = try await attachmentImporter.importAttachments(
                                note.attachments,
                                sessionID: boundSessionID,
                                authorizedRoot: authorizedRoot
                            ).map(\.messageRef)
                        }
                        let importedSession = try await sessionService.upsertImportedNoteMessage(
                            sessionID: boundSessionID,
                            messageID: messageID,
                            content: note.markdownContent,
                            attachments: attachmentRefs,
                            createdAt: note.createdAt ?? current.createdAt
                        )
                        onSessionImported(importedSession)
                        current = options.llmMode == .automatic
                            ? try ledger.transitionItem(id: current.id, to: .queuedForLLM)
                            : try ledger.transitionItem(id: current.id, to: .completed)
                    }
                    if current.status == .queuedForLLM {
                        _ = try await sessionService.trimMessagesAfterImportedNote(
                            sessionID: boundSessionID,
                            messageID: messageID
                        )
                        while let delay = await rateLimiter.acquire(providerKey) {
                            try await Self.sleep(delay)
                            try await Self.waitForJobControl(jobID: jobID, ledger: ledger)
                        }
                        limiterAcquired = true
                        current = try ledger.transitionItem(id: current.id, to: .runningLLM)
                        _ = try await sessionService.run(.init(
                            sessionID: boundSessionID,
                            prompt: "请理解并整理上一条已导入的笔记，提炼主题、关键观点和概念关系。",
                            allowNetworkReadTools: options.allowNetworkReadTools
                        ))
                        if let importedSession = try await sessionService.loadSession(id: boundSessionID) {
                            onSessionImported(importedSession)
                        }
                        await rateLimiter.release(providerKey)
                        limiterAcquired = false
                        _ = try ledger.transitionItem(id: current.id, to: .completed)
                    }
                    _ = try ledger.releaseItemLease(id: current.id)
                    return true
                } catch {
                    if limiterAcquired { await rateLimiter.release(providerKey) }
                    if error is CancellationError {
                        _ = try? ledger.releaseItemLease(id: current.id)
                        throw error
                    }
                    guard var failed = try ledger.item(id: current.id) else { throw error }
                    if (failed.status == .runningLLM || failed.status == .queuedForLLM),
                       let sessionID = failed.sessionID {
                        _ = try? await sessionService.trimMessagesAfterImportedNote(
                            sessionID: sessionID,
                            messageID: "note-import-message:\(failed.id)"
                        )
                    }
                    let failure = Self.classify(error)
                    if failure.retryable && failed.attemptCount < retryPolicy.maxAttempts {
                        if failed.status == .runningLLM {
                            failed.status = .queuedForLLM
                        } else if failed.sessionID == nil {
                            failed.status = .ready
                        } else {
                            failed.status = .imported
                        }
                        failed.errorCode = failure.code
                        failed.errorMessage = String(describing: error)
                        failed.updatedAt = Date()
                        try ledger.saveItem(failed)
                        let delay = retryPolicy.delay(attempt: failed.attemptCount, retryAfter: failure.retryAfter)
                        if failure.retryAfter != nil { await rateLimiter.block(providerKey, retryAfter: delay) }
                        _ = try ledger.releaseItemLease(id: failed.id, nextRetryAt: Date().addingTimeInterval(delay))
                        try await Self.sleep(delay)
                        continue
                    }
                    if failed.status == .runningLLM || failed.status == .queuedForLLM {
                        failed.status = .llmFailed
                    } else if failed.sessionID == nil {
                        failed.status = .sessionFailed
                    } else {
                        failed.status = .attachmentFailed
                    }
                    failed.errorCode = failure.code
                    failed.errorMessage = String(describing: error)
                    failed.updatedAt = Date()
                    try ledger.saveItem(failed)
                    _ = try ledger.releaseItemLease(id: failed.id)
                    return false
                }
            }
        }

        job = try requireJob(jobID)
        if job.cancelRequestedAt != nil { return try finalizeCancellationAndCleanup(jobID: jobID) }
        if job.pauseRequestedAt != nil { return job }
        job = try ledger.recalculateJobCounts(jobID: jobID)
        let remaining = try ledger.items(
            jobID: jobID,
            statuses: [.ready, .duplicateChanged, .creatingSession, .imported, .queuedForLLM, .runningLLM]
        )
        guard remaining.isEmpty else { return job }
        let terminal = try ledger.transitionJob(id: jobID, to: job.failedCount > 0 ? .completedWithIssues : .completed)
        if terminal.status == .completed { cleanupStaging(jobID: jobID) }
        return terminal
    }

    private func finalizeCancellationAndCleanup(jobID: String) throws -> NoteImportJobRecord {
        var job = try requireJob(jobID)
        if [.scanning, .importing, .processing, .paused].contains(job.status) {
            job = try ledger.transitionJob(id: jobID, to: .cancelling)
        }
        _ = try ledger.cancelRemainingItems(jobID: jobID)
        _ = try ledger.recalculateJobCounts(jobID: jobID)
        let cancelled = try ledger.transitionJob(id: jobID, to: .cancelled)
        cleanupStaging(jobID: jobID)
        return cancelled
    }

    public func pause(jobID: String) throws { _ = try ledger.requestPause(jobID: jobID) }
    public func resume(jobID: String) throws { _ = try ledger.resumeJob(jobID: jobID) }
    public func cancel(jobID: String) async throws {
        _ = try ledger.requestCancel(jobID: jobID)
        await activeSchedulers[jobID]?.cancel()
        for item in try ledger.items(jobID: jobID, statuses: [.runningLLM]) {
            if let sessionID = item.sessionID { await sessionService.cancel(sessionID: sessionID) }
        }
    }
    public func recoverableJobs() throws -> [NoteImportJobRecord] { try ledger.recoverableJobs() }
    public func delete(jobID: String) throws {
        guard try requireJob(jobID).status.isTerminal else {
            throw AppNoteImportRepositoryError.jobControlUnavailable("Active import tasks cannot be deleted")
        }
        cleanupStaging(jobID: jobID)
        try ledger.deleteJob(id: jobID)
    }
    public func progress(jobID: String) throws -> NoteImportProgress { let job = try requireJob(jobID); let items = try ledger.items(jobID: jobID); return .init(jobID: jobID, status: job.status, discovered: job.discoveredCount, imported: job.importedCount, completed: items.filter { $0.status == .completed }.count, failed: job.failedCount) }

    private func reopenFailedItems(jobID: String, options: NoteImportOptions) throws -> NoteImportJobRecord {
        for item in try ledger.items(jobID: jobID) {
            let reopened: NoteImportItemRecord
            switch item.status {
            case .llmFailed:
                reopened = try ledger.transitionItem(id: item.id, to: .queuedForLLM)
            case .attachmentFailed:
                reopened = try ledger.transitionItem(id: item.id, to: .imported)
            case .sessionFailed:
                reopened = try ledger.transitionItem(id: item.id, to: .ready)
            default:
                continue
            }
            var reset = reopened
            reset.attemptCount = 0
            reset.nextRetryAt = nil
            reset.leaseOwner = nil
            reset.leaseExpiresAt = nil
            reset.errorCode = nil
            reset.errorMessage = nil
            try ledger.saveItem(reset)
        }
        return try ledger.transitionJob(
            id: jobID,
            to: options.llmMode == .automatic ? .processing : .importing
        )
    }

    private func cleanupStaging(jobID: String) {
        let enexRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-enex-resources", isDirectory: true)
            .resolvingSymlinksInPath().standardizedFileURL
        let enexPrefix = enexRoot.path.hasSuffix("/") ? enexRoot.path : enexRoot.path + "/"
        if let items = try? ledger.items(jobID: jobID) {
            for item in items {
                guard let note = try? Self.decodePayload(item, payloadStore: payloadStore) else { continue }
                for attachment in note.attachments {
                    guard let path = attachment.sourcePath else { continue }
                    let url = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
                    guard url.path.hasPrefix(enexPrefix) else { continue }
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
        try? payloadStore?.removeJob(jobID: jobID)
    }

    private static func waitForJobControl(jobID: String, ledger: AppNoteImportRepository) async throws {
        if try ledger.job(id: jobID)?.cancelRequestedAt != nil { throw CancellationError() }
        while let control = try ledger.job(id: jobID), control.pauseRequestedAt != nil {
            if control.cancelRequestedAt != nil { throw CancellationError() }
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(200))
        }
    }

    private static func sleep(_ seconds: TimeInterval) async throws {
        guard seconds > 0 else { await Task.yield(); return }
        try await Task.sleep(nanoseconds: UInt64(min(seconds, 86_400) * 1_000_000_000))
    }

    private static func classify(_ error: Error) -> (retryable: Bool, code: NoteImportErrorCode, retryAfter: TimeInterval?) {
        if let failure = error as? NoteImportProviderFailure {
            let retryAfter: TimeInterval?
            if case .rateLimited(let value) = failure { retryAfter = value } else { retryAfter = nil }
            return (failure.isRetryable, failure.code, retryAfter)
        }
        if error is URLError {
            return (true, .llmUnavailable, nil)
        }
        if let accessError = error as? NoteImportSourceAccessError,
           accessError == .pathEscapesAuthorizedRoot {
            return (false, .unsafePath, nil)
        }
        if let code = error as? NoteImportErrorCode {
            switch code {
            case .unsafePath, .llmContextExceeded, .internalInvariantViolation:
                return (false, code, nil)
            default:
                return (true, code, nil)
            }
        }
        return (true, .llmUnavailable, nil)
    }

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
