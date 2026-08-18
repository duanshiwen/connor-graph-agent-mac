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
        retryPolicy: NoteImportRetryPolicy = .init(maxAttempts: 20),
        onSessionImported: @escaping @Sendable (AgentSession) -> Void = { _ in }
    ) {
        self.ledger = ledger
        self.sessionService = sessionService
        self.attachmentImporter = attachmentImporter
        self.payloadStore = payloadStore
        self.sourceAccessService = sourceAccessService
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
        // preserveHierarchy 按用户选择保留（Notion 树形结构/文件夹层级导入整棵树）；
        // LLM 与网络工具在导入流程中固定关闭，避免不可控的外部副作用。
        flattenedOptions.llmMode = .disabled
        flattenedOptions.llmConcurrency = 1
        flattenedOptions.allowNetworkReadTools = false
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

        do {
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
            metadata["imported_note_tags"] = try Self.encodeMetadata(note.tags)
            metadata["imported_note_hierarchy"] = try Self.encodeMetadata(note.hierarchy)
            metadata["imported_note_links"] = try Self.encodeMetadata(note.links)
            metadata["imported_note_source_metadata"] = try Self.encodeMetadata(note.sourceMetadata)
            var previousSessionID: String?
            if status == .ready, request.options.duplicatePolicy != .createCopy,
               let previous = try ledger.latestItem(sourceID: request.sourceID, sourceIdentity: note.sourceIdentity) {
                previousSessionID = previous.sessionID ?? previous.metadata["previous_session_id"]
                metadata["previous_item_id"] = previous.id
                if let previousSessionID { metadata["previous_session_id"] = previousSessionID }
                // 只有上一次扫描真正建立了笔记会话（sessionID 非空）才算“已导入”。
                // 此前任务被取消、尚未建会话的项只是扫描过，重导时必须真正导入，
                // 否则会全部被跳过，用户看到“导入完成”却没有新增任何笔记。
                if previousSessionID != nil, previous.normalizedTextHash == note.normalizedTextHash {
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
        } catch {
            if let current = try? requireJob(jobID), current.status == .scanning {
                _ = try? ledger.transitionJob(id: jobID, to: .failed)
            }
            throw error
        }
    }

    public func execute(jobID: String) async throws -> NoteImportJobRecord {
        let interval = NoteImportPerformanceLog.begin("Import Execute", jobID: jobID)
        defer { NoteImportPerformanceLog.end(interval, jobID: jobID) }
        var job = try requireJob(jobID)
        if job.status == .completedWithIssues {
            job = try reopenFailedItems(jobID: jobID)
        }
        _ = try ledger.reconcileInterruptedItems(jobID: jobID)
        job = try ledger.recalculateJobCounts(jobID: jobID)
        _ = try ledger.heartbeat(jobID: jobID, schedulerVersion: schedulerVersion)
        if job.cancelRequestedAt != nil { return try finalizeCancellationAndCleanup(jobID: jobID) }
        if job.pauseRequestedAt != nil || job.status == .paused { return job }
        if job.status == .awaitingReview { job = try ledger.transitionJob(id: jobID, to: .ready) }
        if job.status == .ready { job = try ledger.transitionJob(id: jobID, to: .importing) }

        let source = try ledger.source(id: job.sourceID)
        let sourceLease = try source.flatMap { source in
            source.locationBookmark == nil ? nil : try sourceAccessService.access(source: source)
        }
        defer { sourceLease?.release() }
        let enexLease = NoteImportSourceAccessLease(
            rootURL: FileManager.default.temporaryDirectory.appendingPathComponent("connor-enex-resources", isDirectory: true),
            didStart: false
        )

        let scheduler = NoteImportExecutionScheduler(configuration: .init(concurrency: 1))
        activeSchedulers[jobID] = scheduler
        defer { activeSchedulers.removeValue(forKey: jobID) }
        let pending = try ledger.items(
            jobID: jobID,
            statuses: [.ready, .duplicateChanged, .imported, .queuedForLLM, .runningLLM]
        )
        let options = job.options
        let sourceKind = source?.kind.rawValue
        let payloadStore = self.payloadStore
        let retryPolicy = self.retryPolicy
        _ = await scheduler.run(elements: pending) { [ledger, sessionService, attachmentImporter, payloadStore, options, sourceKind, sourceLease, enexLease, retryPolicy, onSessionImported] item in
            let itemInterval = NoteImportPerformanceLog.begin("Import Item", jobID: jobID, itemCount: 1)
            defer { NoteImportPerformanceLog.end(itemInterval, jobID: jobID, itemCount: 1) }
            let owner = "\(jobID):\(UUID().uuidString)"
            while true {
                try await Self.waitForJobControl(jobID: jobID, ledger: ledger)
                guard var current = try ledger.item(id: item.id) else { return false }
                if let retryAt = current.nextRetryAt, retryAt > Date() {
                    try await Self.sleep(retryAt.timeIntervalSinceNow, jobID: jobID, ledger: ledger)
                }
                guard let claimed = try ledger.claimItem(id: current.id, owner: owner, leaseDuration: 300) else { return false }
                current = claimed
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
                        await sessionService.associateImportedNote(sessionID: sessionID, metadata: NoteImportProjectionMetadata(
                            itemID: current.id, sourceID: current.sourceID,
                            sourceKind: sourceKind ?? note.sourceKind.rawValue, sourceIdentity: current.sourceIdentity,
                            externalID: current.externalID, relativePath: current.relativePath, sourceCreatedAt: note.createdAt,
                            hierarchy: note.hierarchy,
                            parentSourceIdentity: note.hierarchyParent
                        ))
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
                    if [.imported, .queuedForLLM, .runningLLM].contains(current.status) {
                        var attachmentResults: [NoteImportAttachmentImportResult] = []
                        if options.importAttachments, let attachmentImporter, !note.attachments.isEmpty {
                            // .enex 与新版 .notes 的资源都落在 connor-enex-resources 暂存目录，
                            // 统一走受控租约，防止附件导入越权访问其它临时文件。
                            let authorizedRoot = [.evernoteENEX, .yinxiangNotes].contains(note.sourceKind) ? enexLease : sourceLease
                            attachmentResults = try await attachmentImporter.importAttachments(
                                note.attachments,
                                sessionID: boundSessionID,
                                authorizedRoot: authorizedRoot
                            )
                        }
                        let renderedContent = Self.rewritingImageReferences(in: note.markdownContent, results: attachmentResults)
                        let importedSession = try await sessionService.upsertImportedNoteMessage(
                            sessionID: boundSessionID,
                            messageID: messageID,
                            content: renderedContent,
                            attachments: attachmentResults.map(\.messageRef),
                            createdAt: note.createdAt ?? current.createdAt
                        )
                        onSessionImported(importedSession)
                        await sessionService.associateImportedNote(sessionID: boundSessionID, metadata: NoteImportProjectionMetadata(
                            itemID: current.id, sourceID: current.sourceID,
                            sourceKind: sourceKind ?? note.sourceKind.rawValue, sourceIdentity: current.sourceIdentity,
                            externalID: current.externalID, relativePath: current.relativePath, sourceCreatedAt: note.createdAt,
                            hierarchy: note.hierarchy,
                            parentSourceIdentity: note.hierarchyParent
                        ))
                        current.status = .completed
                        current.errorCode = nil
                        current.errorMessage = nil
                        current.updatedAt = Date()
                        try ledger.saveItem(current)
                    }
                    _ = try ledger.releaseItemLease(id: current.id)
                    return true
                } catch {
                    if error is CancellationError {
                        _ = try? ledger.releaseItemLease(id: current.id)
                        throw error
                    }
                    guard var failed = try ledger.item(id: current.id) else { throw error }
                    let failure = Self.classify(error)
                    if failure.retryable && failed.attemptCount < retryPolicy.maxAttempts {
                        if failed.sessionID == nil {
                            failed.status = .ready
                        } else {
                            failed.status = .imported
                        }
                        failed.errorCode = failure.code
                        failed.errorMessage = String(describing: error)
                        failed.updatedAt = Date()
                        try ledger.saveItem(failed)
                        let delay = retryPolicy.delay(attempt: failed.attemptCount, retryAfter: failure.retryAfter)
                        _ = try ledger.releaseItemLease(id: failed.id, nextRetryAt: Date().addingTimeInterval(delay))
                        try await Self.sleep(delay, jobID: jobID, ledger: ledger)
                        continue
                    }
                    if failed.sessionID == nil {
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
    public func failInterruptedPreparation(jobID: String) throws {
        let job = try requireJob(jobID)
        guard [.created, .scanning].contains(job.status) else { return }
        _ = try ledger.transitionJob(id: jobID, to: .failed)
    }
    public func delete(jobID: String) throws {
        guard try requireJob(jobID).status.isTerminal else {
            throw AppNoteImportRepositoryError.jobControlUnavailable("Active import tasks cannot be deleted")
        }
        cleanupStaging(jobID: jobID)
        try ledger.deleteJob(id: jobID)
    }
    public func progress(jobID: String) throws -> NoteImportProgress { let job = try requireJob(jobID); let items = try ledger.items(jobID: jobID); return .init(jobID: jobID, status: job.status, discovered: job.discoveredCount, imported: job.importedCount, completed: items.filter { $0.status == .completed }.count, failed: job.failedCount) }

    private func reopenFailedItems(jobID: String) throws -> NoteImportJobRecord {
        for item in try ledger.items(jobID: jobID) {
            let reopened: NoteImportItemRecord
            switch item.status {
            case .llmFailed:
                reopened = try ledger.transitionItem(id: item.id, to: .imported)
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
        return try ledger.transitionJob(id: jobID, to: .importing)
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

    private static func sleep(_ seconds: TimeInterval, jobID: String, ledger: AppNoteImportRepository) async throws {
        var remaining = min(max(seconds, 0), 86_400)
        guard remaining > 0 else { await Task.yield(); return }
        while remaining > 0 {
            try await waitForJobControl(jobID: jobID, ledger: ledger)
            let interval = min(remaining, 0.25)
            try await Task.sleep(for: .seconds(interval))
            remaining -= interval
        }
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
        if error is AppSessionAttachmentImportError || error is NoteImportAttachmentImporterError {
            // 附件被策略拒绝（超限/不支持）、源文件缺失或校验失败都是永久性错误：
            // 重试不会成功，直接判定失败并继续导入后续笔记，避免整批导入被退避重试卡住。
            return (false, .attachmentMissing, nil)
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

    /// 将笔记 Markdown 中的本地图片引用改写为已导入会话附件存储中的 file:// URL，
    /// 使 AgentMarkdownPreviewText 能按会话附件根目录安全加载并显示图片。
    /// - Notion / Markdown 文件夹：`![alt](相对路径)` → `![alt](file://…/原始文件)`
    /// - Evernote：`attachment:<md5>` 占位符 → file URL
    /// - Obsidian：`![[嵌入表达式]]` → 标准图片语法
    static func rewritingImageReferences(in content: String, results: [NoteImportAttachmentImportResult]) -> String {
        var output = content
        for result in results {
            let attachment = result.attachment
            let storedURL = result.storedFileURL.absoluteString
            if let md5 = attachment.metadata["enex_md5"] {
                output = output.replacingOccurrences(of: "attachment:\(md5)", with: storedURL)
                continue
            }
            if let embed = attachment.metadata["obsidian_embed"], embed.hasPrefix("![[") {
                output = output.replacingOccurrences(of: embed, with: "![\(attachment.displayName)](\(storedURL))")
                continue
            }
            guard let originalTarget = attachment.metadata["notion_target"] ?? attachment.metadata["markdown_target"] else { continue }
            output = replacingMarkdownImageTarget(in: output, expected: normalizedReference(originalTarget), storedURL: storedURL)
        }
        return output
    }

    private static func normalizedReference(_ value: String) -> String {
        var normalized = value.components(separatedBy: "#")[0]
        normalized = normalized.removingPercentEncoding ?? normalized
        normalized = normalized.replacingOccurrences(of: "\\", with: "/")
        while normalized.hasPrefix("./") { normalized = String(normalized.dropFirst(2)) }
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func replacingMarkdownImageTarget(in content: String, expected: String, storedURL: String) -> String {
        let pattern = #"!\[([^\]]*)\]\(\s*([^()\n]*?)(?:\s+["'][^"']*["'])?\s*\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return content }
        let ns = content as NSString
        var replacements: [(range: NSRange, alt: String)] = []
        for match in regex.matches(in: content, range: NSRange(location: 0, length: ns.length)) {
            let target = ns.substring(with: match.range(at: 2))
            guard normalizedReference(target) == expected else { continue }
            replacements.append((match.range, ns.substring(with: match.range(at: 1))))
        }
        guard !replacements.isEmpty else { return content }
        let mutable = NSMutableString(string: content)
        for replacement in replacements.reversed() {
            mutable.replaceCharacters(in: replacement.range, with: "![\(replacement.alt)](\(storedURL))")
        }
        return mutable as String
    }

    private static func encodePayload(_ note: ImportedNote) throws -> String {
        let interval = NoteImportPerformanceLog.begin("Payload Encode", jobID: "preview")
        defer { NoteImportPerformanceLog.end(interval, jobID: "preview") }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(note).base64EncodedString()
    }

    private static func encodeMetadata<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
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
