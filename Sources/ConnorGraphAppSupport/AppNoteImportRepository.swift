import Foundation
import SQLite3
import ConnorGraphCore

public enum AppNoteImportRepositoryError: Error, Equatable, CustomStringConvertible {
    case openFailed(String)
    case sqliteFailed(String)
    case decodeFailed(String)
    case sourceNotFound(String)
    case jobNotFound(String)
    case itemNotFound(String)
    case jobControlUnavailable(String)

    public var description: String {
        switch self {
        case .openFailed(let value): "openFailed: \(value)"
        case .sqliteFailed(let value): "sqliteFailed: \(value)"
        case .decodeFailed(let value): "decodeFailed: \(value)"
        case .sourceNotFound(let id): "sourceNotFound: \(id)"
        case .jobNotFound(let id): "jobNotFound: \(id)"
        case .itemNotFound(let id): "itemNotFound: \(id)"
        case .jobControlUnavailable(let message): "jobControlUnavailable: \(message)"
        }
    }
}

public final class AppNoteImportRepository: @unchecked Sendable {
    public static let schemaVersion = 2

    private var db: OpaquePointer?
    private let lock = NSRecursiveLock()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(databasePath: String) throws {
        encoder = JSONEncoder(); decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601; decoder.dateDecodingStrategy = .iso8601
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databasePath, &db, flags, nil) == SQLITE_OK else {
            throw AppNoteImportRepositoryError.openFailed(Self.message(db))
        }
        guard sqlite3_busy_timeout(db, 5_000) == SQLITE_OK else {
            throw AppNoteImportRepositoryError.openFailed(Self.message(db))
        }
        try execute("PRAGMA foreign_keys = ON;")
        try execute("PRAGMA journal_mode = WAL;")
        try migrate()
    }

    deinit { lock.withLock { sqlite3_close(db); db = nil } }

    public func migrate() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS note_import_schema_migrations (
            version INTEGER PRIMARY KEY,
            applied_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS note_import_sources (
            id TEXT PRIMARY KEY,
            source_kind TEXT NOT NULL,
            display_name TEXT NOT NULL,
            location_bookmark BLOB,
            created_at TEXT NOT NULL,
            metadata_json TEXT NOT NULL DEFAULT '{}'
        );
        CREATE TABLE IF NOT EXISTS note_import_jobs (
            id TEXT PRIMARY KEY,
            source_id TEXT NOT NULL,
            status TEXT NOT NULL,
            options_json TEXT NOT NULL,
            discovered_count INTEGER NOT NULL DEFAULT 0,
            imported_count INTEGER NOT NULL DEFAULT 0,
            duplicate_count INTEGER NOT NULL DEFAULT 0,
            failed_count INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            started_at TEXT,
            completed_at TEXT,
            error_code TEXT,
            error_message TEXT,
            FOREIGN KEY(source_id) REFERENCES note_import_sources(id)
        );
        CREATE TABLE IF NOT EXISTS note_import_items (
            id TEXT PRIMARY KEY,
            job_id TEXT NOT NULL,
            source_id TEXT NOT NULL,
            source_identity TEXT NOT NULL,
            external_id TEXT,
            relative_path TEXT,
            title TEXT NOT NULL,
            status TEXT NOT NULL,
            session_id TEXT,
            raw_byte_hash TEXT NOT NULL,
            normalized_text_hash TEXT NOT NULL,
            source_encoding TEXT,
            encoding_confidence REAL,
            decoder_version TEXT,
            attempt_count INTEGER NOT NULL DEFAULT 0,
            error_code TEXT,
            error_message TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            metadata_json TEXT NOT NULL DEFAULT '{}',
            FOREIGN KEY(job_id) REFERENCES note_import_jobs(id),
            FOREIGN KEY(source_id) REFERENCES note_import_sources(id),
            FOREIGN KEY(session_id) REFERENCES agent_sessions(id)
        );
        CREATE TABLE IF NOT EXISTS note_import_item_attempts (
            id TEXT PRIMARY KEY,
            item_id TEXT NOT NULL,
            phase TEXT NOT NULL,
            status TEXT NOT NULL,
            started_at TEXT NOT NULL,
            finished_at TEXT,
            error_code TEXT,
            error_message TEXT,
            metadata_json TEXT NOT NULL DEFAULT '{}',
            FOREIGN KEY(item_id) REFERENCES note_import_items(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS note_import_links (
            id TEXT PRIMARY KEY,
            item_id TEXT NOT NULL,
            link_kind TEXT NOT NULL,
            raw_target TEXT NOT NULL,
            resolved_source_identity TEXT,
            resolved_session_id TEXT,
            metadata_json TEXT NOT NULL DEFAULT '{}',
            FOREIGN KEY(item_id) REFERENCES note_import_items(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS note_import_attachments (
            id TEXT PRIMARY KEY,
            item_id TEXT NOT NULL,
            source_path TEXT,
            display_name TEXT NOT NULL,
            mime_type TEXT,
            byte_count INTEGER,
            content_hash TEXT,
            imported_attachment_id TEXT,
            status TEXT NOT NULL,
            error_message TEXT,
            metadata_json TEXT NOT NULL DEFAULT '{}',
            FOREIGN KEY(item_id) REFERENCES note_import_items(id) ON DELETE CASCADE
        );
        CREATE UNIQUE INDEX IF NOT EXISTS idx_note_import_items_job_identity ON note_import_items(job_id, source_identity);
        CREATE INDEX IF NOT EXISTS idx_note_import_items_source_identity ON note_import_items(source_id, source_identity, updated_at DESC);
        CREATE INDEX IF NOT EXISTS idx_note_import_items_status ON note_import_items(job_id, status, updated_at);
        CREATE INDEX IF NOT EXISTS idx_note_import_jobs_status ON note_import_jobs(status, updated_at);
        CREATE INDEX IF NOT EXISTS idx_note_import_attempts_item ON note_import_item_attempts(item_id, started_at DESC);
        INSERT OR IGNORE INTO note_import_schema_migrations(version, applied_at) VALUES (1, datetime('now'));
        """)
        try addColumnIfNeeded(table: "note_import_jobs", name: "pause_requested_at", definition: "TEXT")
        try addColumnIfNeeded(table: "note_import_jobs", name: "cancel_requested_at", definition: "TEXT")
        try addColumnIfNeeded(table: "note_import_jobs", name: "last_heartbeat_at", definition: "TEXT")
        try addColumnIfNeeded(table: "note_import_jobs", name: "resumed_at", definition: "TEXT")
        try addColumnIfNeeded(table: "note_import_jobs", name: "scheduler_version", definition: "TEXT")
        try addColumnIfNeeded(table: "note_import_items", name: "next_retry_at", definition: "TEXT")
        try addColumnIfNeeded(table: "note_import_items", name: "last_attempt_at", definition: "TEXT")
        try addColumnIfNeeded(table: "note_import_items", name: "lease_owner", definition: "TEXT")
        try addColumnIfNeeded(table: "note_import_items", name: "lease_expires_at", definition: "TEXT")
        try addColumnIfNeeded(table: "note_import_items", name: "source_revision", definition: "TEXT")
        try execute("INSERT OR IGNORE INTO note_import_schema_migrations(version, applied_at) VALUES (2, datetime('now'));")
    }

    public func saveSource(_ source: NoteImportSourceRecord) throws {
        let sql = """
        INSERT INTO note_import_sources(id, source_kind, display_name, location_bookmark, created_at, metadata_json)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET source_kind=excluded.source_kind, display_name=excluded.display_name,
          location_bookmark=excluded.location_bookmark, metadata_json=excluded.metadata_json;
        """
        try run(sql, bindings: [.text(source.id), .text(source.kind.rawValue), .text(source.displayName), .blob(source.locationBookmark), .text(iso(source.createdAt)), .text(try json(source.metadata))])
    }

    public func source(id: String) throws -> NoteImportSourceRecord? {
        try rows("SELECT id, source_kind, display_name, location_bookmark, created_at, metadata_json FROM note_import_sources WHERE id = ?", bindings: [.text(id)]).first.map(decodeSource)
    }

    public func sources() throws -> [NoteImportSourceRecord] {
        try rows("SELECT id, source_kind, display_name, location_bookmark, created_at, metadata_json FROM note_import_sources ORDER BY created_at DESC").map(decodeSource)
    }

    public func saveJob(_ job: NoteImportJobRecord) throws {
        guard try source(id: job.sourceID) != nil else { throw AppNoteImportRepositoryError.sourceNotFound(job.sourceID) }
        let sql = """
        INSERT INTO note_import_jobs(id, source_id, status, options_json, discovered_count, imported_count, duplicate_count, failed_count, created_at, updated_at, started_at, completed_at, error_code, error_message, pause_requested_at, cancel_requested_at, last_heartbeat_at, resumed_at, scheduler_version)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET status=excluded.status, options_json=excluded.options_json,
          discovered_count=excluded.discovered_count, imported_count=excluded.imported_count,
          duplicate_count=excluded.duplicate_count, failed_count=excluded.failed_count,
          updated_at=excluded.updated_at, started_at=excluded.started_at, completed_at=excluded.completed_at,
          error_code=excluded.error_code, error_message=excluded.error_message,
          pause_requested_at=excluded.pause_requested_at, cancel_requested_at=excluded.cancel_requested_at,
          last_heartbeat_at=excluded.last_heartbeat_at, resumed_at=excluded.resumed_at,
          scheduler_version=excluded.scheduler_version;
        """
        try run(sql, bindings: [.text(job.id), .text(job.sourceID), .text(job.status.rawValue), .text(try json(job.options)), .int(job.discoveredCount), .int(job.importedCount), .int(job.duplicateCount), .int(job.failedCount), .text(iso(job.createdAt)), .text(iso(job.updatedAt)), .text(job.startedAt.map(iso)), .text(job.completedAt.map(iso)), .text(job.errorCode?.rawValue), .text(job.errorMessage), .text(job.pauseRequestedAt.map(iso)), .text(job.cancelRequestedAt.map(iso)), .text(job.lastHeartbeatAt.map(iso)), .text(job.resumedAt.map(iso)), .text(job.schedulerVersion)])
    }

    public func job(id: String) throws -> NoteImportJobRecord? {
        try rows(Self.jobSelect + " WHERE id = ?", bindings: [.text(id)]).first.map(decodeJob)
    }

    public func jobs(limit: Int = 200) throws -> [NoteImportJobRecord] {
        try rows(Self.jobSelect + " ORDER BY updated_at DESC LIMIT ?", bindings: [.int(max(1, limit))]).map(decodeJob)
    }

    public func recoverableJobs() throws -> [NoteImportJobRecord] {
        let terminal = NoteImportJobStatus.allCases.filter(\.isTerminal).map { "'\($0.rawValue)'" }.joined(separator: ",")
        return try rows(Self.jobSelect + " WHERE status NOT IN (\(terminal)) ORDER BY updated_at ASC").map(decodeJob)
    }

    public func transitionJob(id: String, to status: NoteImportJobStatus, now: Date = Date()) throws -> NoteImportJobRecord {
        guard var job = try job(id: id) else { throw AppNoteImportRepositoryError.jobNotFound(id) }
        try NoteImportStateMachine().validate(jobFrom: job.status, to: status)
        job.status = status; job.updatedAt = now
        if status == .scanning && job.startedAt == nil { job.startedAt = now }
        if status.isTerminal { job.completedAt = now }
        try saveJob(job)
        return job
    }

    public func saveItem(_ item: NoteImportItemRecord) throws {
        guard try job(id: item.jobID) != nil else { throw AppNoteImportRepositoryError.jobNotFound(item.jobID) }
        try saveItemUnchecked(item)
    }

    /// Persists a bounded scan batch in one short transaction and updates the
    /// job counters atomically. Duplicate source identities are counted without
    /// aborting the remaining items in the batch.
    @discardableResult
    public func appendScannedItems(jobID: String, items: [NoteImportItemRecord], now: Date = Date()) throws -> (inserted: Int, duplicates: Int) {
        guard !items.isEmpty else { return (0, 0) }
        return try lock.withLock {
            guard try job(id: jobID) != nil else { throw AppNoteImportRepositoryError.jobNotFound(jobID) }
            try execute("BEGIN IMMEDIATE TRANSACTION;")
            var inserted = 0
            var duplicates = 0
            do {
                for item in items {
                    do {
                        try saveItemUnchecked(item)
                        inserted += 1
                    } catch AppNoteImportRepositoryError.sqliteFailed(let message)
                        where message.localizedCaseInsensitiveContains("unique") {
                        duplicates += 1
                    }
                }
                try run(
                    """
                    UPDATE note_import_jobs
                    SET discovered_count = discovered_count + ?, duplicate_count = duplicate_count + ?, updated_at = ?
                    WHERE id = ?
                    """,
                    bindings: [.int(inserted), .int(duplicates), .text(iso(now)), .text(jobID)]
                )
                try execute("COMMIT;")
                return (inserted, duplicates)
            } catch {
                try? execute("ROLLBACK;")
                throw error
            }
        }
    }

    private func saveItemUnchecked(_ item: NoteImportItemRecord) throws {
        let sql = """
        INSERT INTO note_import_items(id, job_id, source_id, source_identity, external_id, relative_path, title, status, session_id, raw_byte_hash, normalized_text_hash, source_encoding, encoding_confidence, decoder_version, attempt_count, next_retry_at, last_attempt_at, lease_owner, lease_expires_at, source_revision, error_code, error_message, created_at, updated_at, metadata_json)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET external_id=excluded.external_id, relative_path=excluded.relative_path,
          title=excluded.title, status=excluded.status, session_id=excluded.session_id,
          raw_byte_hash=excluded.raw_byte_hash, normalized_text_hash=excluded.normalized_text_hash,
          source_encoding=excluded.source_encoding, encoding_confidence=excluded.encoding_confidence,
          decoder_version=excluded.decoder_version, attempt_count=excluded.attempt_count,
          next_retry_at=excluded.next_retry_at, last_attempt_at=excluded.last_attempt_at,
          lease_owner=excluded.lease_owner, lease_expires_at=excluded.lease_expires_at,
          source_revision=excluded.source_revision, error_code=excluded.error_code,
          error_message=excluded.error_message, updated_at=excluded.updated_at, metadata_json=excluded.metadata_json;
        """
        try run(sql, bindings: [.text(item.id), .text(item.jobID), .text(item.sourceID), .text(item.sourceIdentity), .text(item.externalID), .text(item.relativePath), .text(item.title), .text(item.status.rawValue), .text(item.sessionID), .text(item.rawByteHash), .text(item.normalizedTextHash), .text(item.sourceEncoding), .double(item.encodingConfidence), .text(item.decoderVersion), .int(item.attemptCount), .text(item.nextRetryAt.map(iso)), .text(item.lastAttemptAt.map(iso)), .text(item.leaseOwner), .text(item.leaseExpiresAt.map(iso)), .text(item.sourceRevision), .text(item.errorCode?.rawValue), .text(item.errorMessage), .text(iso(item.createdAt)), .text(iso(item.updatedAt)), .text(try json(item.metadata))])
    }

    public func item(id: String) throws -> NoteImportItemRecord? {
        try rows(Self.itemSelect + " WHERE id = ?", bindings: [.text(id)]).first.map(decodeItem)
    }

    public func latestItem(sourceID: String, sourceIdentity: String) throws -> NoteImportItemRecord? {
        try rows(Self.itemSelect + " WHERE source_id = ? AND source_identity = ? ORDER BY updated_at DESC LIMIT 1", bindings: [.text(sourceID), .text(sourceIdentity)]).first.map(decodeItem)
    }

    public func items(jobID: String, statuses: Set<NoteImportItemStatus>? = nil) throws -> [NoteImportItemRecord] {
        var sql = Self.itemSelect + " WHERE job_id = ?"
        if let statuses, !statuses.isEmpty {
            sql += " AND status IN (" + statuses.map { "'\($0.rawValue)'" }.joined(separator: ",") + ")"
        }
        sql += " ORDER BY created_at ASC"
        return try rows(sql, bindings: [.text(jobID)]).map(decodeItem)
    }

    public func transitionItem(id: String, to status: NoteImportItemStatus, now: Date = Date()) throws -> NoteImportItemRecord {
        guard var item = try item(id: id) else { throw AppNoteImportRepositoryError.itemNotFound(id) }
        try NoteImportStateMachine().validate(itemFrom: item.status, to: status)
        item.status = status; item.updatedAt = now
        try saveItem(item)
        return item
    }

    public func requestPause(jobID: String, now: Date = Date()) throws -> NoteImportJobRecord {
        try lock.withLock {
            guard let currentJob = try job(id: jobID) else { throw AppNoteImportRepositoryError.jobNotFound(jobID) }
            guard [.scanning, .importing, .processing].contains(currentJob.status), currentJob.cancelRequestedAt == nil else {
                throw AppNoteImportRepositoryError.jobControlUnavailable("Task cannot be paused from \(currentJob.status.rawValue)")
            }
            try run(
                "UPDATE note_import_jobs SET pause_requested_at = ?, updated_at = ? WHERE id = ?",
                bindings: [.text(iso(now)), .text(iso(now)), .text(jobID)]
            )
            guard let updated = try job(id: jobID) else { throw AppNoteImportRepositoryError.jobNotFound(jobID) }
            return updated
        }
    }

    public func resumeJob(jobID: String, now: Date = Date()) throws -> NoteImportJobRecord {
        try lock.withLock {
            guard let currentJob = try job(id: jobID) else { throw AppNoteImportRepositoryError.jobNotFound(jobID) }
            guard !currentJob.status.isTerminal, currentJob.cancelRequestedAt == nil,
                  currentJob.pauseRequestedAt != nil || currentJob.status == .paused else {
                throw AppNoteImportRepositoryError.jobControlUnavailable("Task is not paused")
            }

            let resumedStatus: NoteImportJobStatus
            if currentJob.status == .paused {
                resumedStatus = try legacyResumeStatus(jobID: jobID)
                try NoteImportStateMachine().validate(jobFrom: .paused, to: resumedStatus)
            } else {
                resumedStatus = currentJob.status
            }
            try run(
                "UPDATE note_import_jobs SET status = ?, pause_requested_at = NULL, resumed_at = ?, updated_at = ? WHERE id = ?",
                bindings: [.text(resumedStatus.rawValue), .text(iso(now)), .text(iso(now)), .text(jobID)]
            )
            guard let updated = try job(id: jobID) else { throw AppNoteImportRepositoryError.jobNotFound(jobID) }
            return updated
        }
    }

    private func legacyResumeStatus(jobID: String) throws -> NoteImportJobStatus {
        let itemStatuses = Set(try items(jobID: jobID).map(\.status))
        if !itemStatuses.isDisjoint(with: [.queuedForLLM, .runningLLM, .llmFailed]) {
            return .processing
        }
        if !itemStatuses.isEmpty {
            return .importing
        }
        return .scanning
    }

    public func requestCancel(jobID: String, now: Date = Date()) throws -> NoteImportJobRecord {
        guard var job = try job(id: jobID) else { throw AppNoteImportRepositoryError.jobNotFound(jobID) }
        job.cancelRequestedAt = now; job.updatedAt = now
        try saveJob(job); return job
    }

    public func heartbeat(jobID: String, schedulerVersion: String, now: Date = Date()) throws -> NoteImportJobRecord {
        guard var job = try job(id: jobID) else { throw AppNoteImportRepositoryError.jobNotFound(jobID) }
        job.lastHeartbeatAt = now; job.schedulerVersion = schedulerVersion; job.updatedAt = now
        try saveJob(job); return job
    }

    public func claimItem(id: String, owner: String, leaseDuration: TimeInterval, now: Date = Date()) throws -> NoteImportItemRecord? {
        guard var item = try item(id: id) else { throw AppNoteImportRepositoryError.itemNotFound(id) }
        if let expiry = item.leaseExpiresAt, expiry > now, item.leaseOwner != owner { return nil }
        item.leaseOwner = owner; item.leaseExpiresAt = now.addingTimeInterval(leaseDuration); item.lastAttemptAt = now; item.attemptCount += 1; item.updatedAt = now
        try saveItem(item); return item
    }

    public func releaseItemLease(id: String, nextRetryAt: Date? = nil, now: Date = Date()) throws -> NoteImportItemRecord {
        guard var item = try item(id: id) else { throw AppNoteImportRepositoryError.itemNotFound(id) }
        item.leaseOwner = nil; item.leaseExpiresAt = nil; item.nextRetryAt = nextRetryAt; item.updatedAt = now
        try saveItem(item); return item
    }

    @discardableResult
    public func reconcileInterruptedItems(jobID: String, now: Date = Date()) throws -> [NoteImportItemRecord] {
        var reconciled: [NoteImportItemRecord] = []
        for var item in try items(jobID: jobID) {
            switch item.status {
            case .creatingSession where item.sessionID != nil:
                item.status = .imported
            case .creatingSession:
                item.status = .ready
            case .runningLLM:
                item.status = .queuedForLLM
            default:
                continue
            }
            item.leaseOwner = nil; item.leaseExpiresAt = nil; item.updatedAt = now
            try saveItem(item); reconciled.append(item)
        }
        return reconciled
    }

    private static let jobSelect = "SELECT id, source_id, status, options_json, discovered_count, imported_count, duplicate_count, failed_count, created_at, updated_at, started_at, completed_at, error_code, error_message, pause_requested_at, cancel_requested_at, last_heartbeat_at, resumed_at, scheduler_version FROM note_import_jobs"
    private static let itemSelect = "SELECT id, job_id, source_id, source_identity, external_id, relative_path, title, status, session_id, raw_byte_hash, normalized_text_hash, source_encoding, encoding_confidence, decoder_version, attempt_count, next_retry_at, last_attempt_at, lease_owner, lease_expires_at, source_revision, error_code, error_message, created_at, updated_at, metadata_json FROM note_import_items"

    private func decodeSource(_ row: [SQLiteValue]) throws -> NoteImportSourceRecord {
        NoteImportSourceRecord(id: row[0].string, kind: NoteImportSourceKind(rawValue: row[1].string) ?? .markdownFolder, displayName: row[2].string, locationBookmark: row[3].data, createdAt: try date(row[4].string), metadata: try decode([String: String].self, row[5].string))
    }

    private func decodeJob(_ row: [SQLiteValue]) throws -> NoteImportJobRecord {
        NoteImportJobRecord(id: row[0].string, sourceID: row[1].string, status: NoteImportJobStatus(rawValue: row[2].string) ?? .failed, options: try decode(NoteImportOptions.self, row[3].string), discoveredCount: row[4].integer, importedCount: row[5].integer, duplicateCount: row[6].integer, failedCount: row[7].integer, createdAt: try date(row[8].string), updatedAt: try date(row[9].string), startedAt: try optionalDate(row[10].optionalString), completedAt: try optionalDate(row[11].optionalString), errorCode: row[12].optionalString.flatMap(NoteImportErrorCode.init(rawValue:)), errorMessage: row[13].optionalString, pauseRequestedAt: try optionalDate(row[14].optionalString), cancelRequestedAt: try optionalDate(row[15].optionalString), lastHeartbeatAt: try optionalDate(row[16].optionalString), resumedAt: try optionalDate(row[17].optionalString), schedulerVersion: row[18].optionalString)
    }

    private func decodeItem(_ row: [SQLiteValue]) throws -> NoteImportItemRecord {
        NoteImportItemRecord(id: row[0].string, jobID: row[1].string, sourceID: row[2].string, sourceIdentity: row[3].string, externalID: row[4].optionalString, relativePath: row[5].optionalString, title: row[6].string, status: NoteImportItemStatus(rawValue: row[7].string) ?? .parseFailed, sessionID: row[8].optionalString, rawByteHash: row[9].string, normalizedTextHash: row[10].string, sourceEncoding: row[11].optionalString, encodingConfidence: row[12].optionalDouble, decoderVersion: row[13].optionalString, attemptCount: row[14].integer, nextRetryAt: try optionalDate(row[15].optionalString), lastAttemptAt: try optionalDate(row[16].optionalString), leaseOwner: row[17].optionalString, leaseExpiresAt: try optionalDate(row[18].optionalString), sourceRevision: row[19].optionalString, errorCode: row[20].optionalString.flatMap(NoteImportErrorCode.init(rawValue:)), errorMessage: row[21].optionalString, createdAt: try date(row[22].string), updatedAt: try date(row[23].string), metadata: try decode([String: String].self, row[24].string))
    }

    private enum Binding { case text(String?), int(Int), double(Double?), blob(Data?) }
    private struct SQLiteValue {
        var string: String; var data: Data?; var isNull: Bool
        var optionalString: String? { isNull ? nil : string }
        var integer: Int { Int(string) ?? 0 }
        var optionalDouble: Double? { isNull ? nil : Double(string) }
    }

    private func addColumnIfNeeded(table: String, name: String, definition: String) throws {
        let columns = try rows("PRAGMA table_info(\(table))")
        guard !columns.contains(where: { $0[1].string == name }) else { return }
        try execute("ALTER TABLE \(table) ADD COLUMN \(name) \(definition);")
    }

    private func execute(_ sql: String) throws {
        let clock = ContinuousClock()
        let started = clock.now
        defer { NoteImportPerformanceLog.slowDatabaseOperation("execute", elapsed: started.duration(to: clock.now)) }
        try lock.withLock {
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
                throw AppNoteImportRepositoryError.sqliteFailed(Self.message(db))
            }
        }
    }

    private func run(_ sql: String, bindings: [Binding]) throws {
        let clock = ContinuousClock()
        let started = clock.now
        defer { NoteImportPerformanceLog.slowDatabaseOperation("write", elapsed: started.duration(to: clock.now), rowCount: 1) }
        try lock.withLock {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw AppNoteImportRepositoryError.sqliteFailed(Self.message(db)) }
            defer { sqlite3_finalize(statement) }
            try bind(bindings, to: statement)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw AppNoteImportRepositoryError.sqliteFailed(Self.message(db)) }
        }
    }

    private func rows(_ sql: String, bindings: [Binding] = []) throws -> [[SQLiteValue]] {
        let clock = ContinuousClock()
        let started = clock.now
        var rowCount = 0
        defer { NoteImportPerformanceLog.slowDatabaseOperation("read", elapsed: started.duration(to: clock.now), rowCount: rowCount) }
        return try lock.withLock {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw AppNoteImportRepositoryError.sqliteFailed(Self.message(db)) }
            defer { sqlite3_finalize(statement) }
            try bind(bindings, to: statement)
            var result: [[SQLiteValue]] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                result.append((0..<sqlite3_column_count(statement)).map { index in
                    let isNull = sqlite3_column_type(statement, index) == SQLITE_NULL
                    let string = sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""
                    let data: Data? = sqlite3_column_blob(statement, index).map { Data(bytes: $0, count: Int(sqlite3_column_bytes(statement, index))) }
                    return SQLiteValue(string: string, data: isNull ? nil : data, isNull: isNull)
                })
            }
            let code = sqlite3_errcode(db)
            guard code == SQLITE_OK || code == SQLITE_DONE else { throw AppNoteImportRepositoryError.sqliteFailed(Self.message(db)) }
            rowCount = result.count
            return result
        }
    }

    private func bind(_ bindings: [Binding], to statement: OpaquePointer?) throws {
        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1); let code: Int32
            switch binding {
            case .text(let value): code = value.map { sqlite3_bind_text(statement, index, $0, -1, SQLITE_TRANSIENT) } ?? sqlite3_bind_null(statement, index)
            case .int(let value): code = sqlite3_bind_int64(statement, index, sqlite3_int64(value))
            case .double(let value): code = value.map { sqlite3_bind_double(statement, index, $0) } ?? sqlite3_bind_null(statement, index)
            case .blob(let value): code = value.map { data in data.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(data.count), SQLITE_TRANSIENT) } } ?? sqlite3_bind_null(statement, index)
            }
            guard code == SQLITE_OK else { throw AppNoteImportRepositoryError.sqliteFailed(Self.message(db)) }
        }
    }

    private func json<T: Encodable>(_ value: T) throws -> String { String(decoding: try encoder.encode(value), as: UTF8.self) }
    private func decode<T: Decodable>(_ type: T.Type, _ value: String) throws -> T { do { return try decoder.decode(type, from: Data(value.utf8)) } catch { throw AppNoteImportRepositoryError.decodeFailed(String(describing: error)) } }
    private func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func date(_ value: String) throws -> Date {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) { return date }
        if let date = ISO8601DateFormatter().date(from: value) { return date }
        throw AppNoteImportRepositoryError.decodeFailed("Invalid date: \(value)")
    }

    private func optionalDate(_ value: String?) throws -> Date? { try value.map(date) }
    private static func message(_ db: OpaquePointer?) -> String { db.flatMap(sqlite3_errmsg).map(String.init(cString:)) ?? "Unknown SQLite error" }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private extension NSRecursiveLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T { lock(); defer { unlock() }; return try body() }
}
