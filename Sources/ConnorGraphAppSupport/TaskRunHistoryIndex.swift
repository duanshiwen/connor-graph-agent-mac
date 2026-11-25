import Foundation
import SQLite3
import Darwin
import ConnorGraphCore

/// JSONL remains the authoritative, complete audit log. This disposable index
/// reads unchanged history without decoding it, and incorporates appends in the
/// same write lock. External replacement, truncation or edits force a rebuild.
final class TaskRunHistoryIndex: @unchecked Sendable {
    private static let registry = Registry()
    private let source: URL
    private var db: OpaquePointer?
    private let lock = NSLock()
    private let decoder: JSONDecoder

    static func forHistory(_ source: URL) throws -> TaskRunHistoryIndex { try registry.index(source) }

    private init(source: URL) throws {
        self.source = source
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        let path = source.appendingPathExtension("index.sqlite").path
        guard sqlite3_open(path, &db) == SQLITE_OK else { throw error() }
        _ = chmod(path, S_IRUSR | S_IWUSR)
        do {
            try execute("""
                PRAGMA busy_timeout=30000;
                PRAGMA journal_mode=WAL;
                PRAGMA synchronous=NORMAL;
                PRAGMA cache_size=-2048;
                CREATE TABLE IF NOT EXISTS history (sequence INTEGER PRIMARY KEY, task_id TEXT NOT NULL, started_at REAL NOT NULL, finished_at REAL NOT NULL, raw_json BLOB NOT NULL);
                CREATE INDEX IF NOT EXISTS history_recent ON history(started_at DESC, finished_at DESC, sequence ASC);
                CREATE INDEX IF NOT EXISTS history_task_recent ON history(task_id, started_at DESC, finished_at DESC, sequence ASC);
                CREATE TABLE IF NOT EXISTS source_state (singleton INTEGER PRIMARY KEY CHECK(singleton=1), signature TEXT NOT NULL);
            """)
        } catch {
            sqlite3_close(db); db = nil; throw error
        }
    }
    deinit { sqlite3_close(db) }

    func load(taskID: String?, limit: Int) throws -> [ConnorTaskRunRecord] {
        guard limit > 0 else { return [] }
        lock.lock(); defer { lock.unlock() }
        return try transaction {
            try synchronize()
            let filter = taskID == nil ? "" : "WHERE task_id=?"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT raw_json FROM history \(filter) ORDER BY started_at DESC, finished_at DESC, sequence ASC LIMIT ?", -1, &statement, nil) == SQLITE_OK else { throw error() }
            defer { sqlite3_finalize(statement) }
            var position: Int32 = 1
            if let taskID { try bind(taskID, at: position, to: statement); position += 1 }
            sqlite3_bind_int64(statement, position, Int64(limit))
            var records: [ConnorTaskRunRecord] = []
            while true {
                switch sqlite3_step(statement) {
                case SQLITE_ROW:
                    let count = Int(sqlite3_column_bytes(statement, 0))
                    if let bytes = sqlite3_column_blob(statement, 0) {
                        records.append(try decoder.decode(ConnorTaskRunRecord.self, from: Data(bytes: bytes, count: count)))
                    }
                case SQLITE_DONE: return records
                default: throw error()
                }
            }
        }
    }

    func append(_ data: Data) throws {
        lock.lock(); defer { lock.unlock() }
        var written = false
        do {
            try transaction {
                try synchronize()
                let before = try signature()
                let addedBytes = try Self.appendAuthoritative(data, to: source)
                written = true
                let after = try signature()
                if before.identity == after.identity && before.size + Int64(addedBytes) == after.size {
                    try insertLines([data])
                    try saveSignature(after.value)
                } else {
                    // A non-indexed writer changed/rotated the source concurrently.
                    try rebuild()
                }
            }
        } catch {
            // A committed JSONL append remains successful if only its disposable
            // index failed. Its changed signature forces recovery on the next read.
            if !written { throw error }
        }
    }

    @discardableResult static func appendAuthoritative(_ data: Data, to source: URL) throws -> Int {
        var payload = data
        if let reader = try? FileHandle(forReadingFrom: source) {
            defer { try? reader.close() }
            let size = try reader.seekToEnd()
            if size > 0 {
                try reader.seek(toOffset: size - 1)
                if try reader.read(upToCount: 1) != Data([10]) { payload.insert(10, at: payload.startIndex) }
            }
        }
        let descriptor = Darwin.open(source.path, O_WRONLY | O_CREAT | O_APPEND, mode_t(0o600))
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        let writer = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? writer.close() }
        try writer.write(contentsOf: payload)
        return payload.count
    }

    private struct Signature {
        var identity: String
        var size: Int64
        var value: String
    }
    private func signature() throws -> Signature {
        guard FileManager.default.fileExists(atPath: source.path) else { return Signature(identity: "missing", size: 0, value: "missing") }
        let handle = try FileHandle(forReadingFrom: source)
        defer { try? handle.close() }
        var attributes = stat()
        guard fstat(handle.fileDescriptor, &attributes) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        let identity = "\(attributes.st_dev):\(attributes.st_ino)"
        let value = "\(identity):\(attributes.st_size):\(attributes.st_mtimespec.tv_sec):\(attributes.st_mtimespec.tv_nsec):\(attributes.st_ctimespec.tv_sec):\(attributes.st_ctimespec.tv_nsec)"
        return Signature(identity: identity, size: attributes.st_size, value: value)
    }
    private func synchronize() throws {
        let current = try signature()
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT signature FROM source_state WHERE singleton=1", -1, &statement, nil) == SQLITE_OK else { throw error() }
        defer { sqlite3_finalize(statement) }
        let step = sqlite3_step(statement)
        if step == SQLITE_ROW, let bytes = sqlite3_column_text(statement, 0), String(cString: bytes) == current.value { return }
        guard step == SQLITE_ROW || step == SQLITE_DONE else { throw error() }
        try rebuild()
    }
    private func rebuild() throws {
        let initial = try signature()
        try execute("DELETE FROM history;")
        if initial.size > 0 {
            let reader = try FileHandle(forReadingFrom: source)
            defer { try? reader.close() }
            var remaining = initial.size
            var pending = Data()
            while remaining > 0 {
                let chunk = try reader.read(upToCount: Int(min(remaining, 256 * 1024))) ?? Data()
                guard !chunk.isEmpty else { break }
                remaining -= Int64(chunk.count)
                pending.append(chunk)
                if let newline = pending.lastIndex(of: 10) {
                    try insertLines(pending[pending.startIndex...newline].split(separator: 10).map { Data($0) })
                    pending = Data(pending[pending.index(after: newline)...])
                }
            }
            if !pending.isEmpty { try insertLines([pending]) }
        }
        // An external write during rebuild is detected on the following access.
        try saveSignature(initial.value)
    }
    private func insertLines(_ lines: [Data]) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO history(task_id,started_at,finished_at,raw_json) VALUES (?,?,?,?)", -1, &statement, nil) == SQLITE_OK else { throw error() }
        defer { sqlite3_finalize(statement) }
        for line in lines where !line.isEmpty {
            guard line.count <= Int(Int32.max) else { throw CocoaError(.fileReadTooLarge) }
            guard String(data: line, encoding: .utf8) != nil else { throw CocoaError(.fileReadInapplicableStringEncoding) }
            guard let record = try? decoder.decode(ConnorTaskRunRecord.self, from: line) else { continue }
            sqlite3_reset(statement); sqlite3_clear_bindings(statement)
            try bind(record.taskID, at: 1, to: statement)
            sqlite3_bind_double(statement, 2, record.startedAt.timeIntervalSince1970)
            sqlite3_bind_double(statement, 3, (record.finishedAt ?? .distantPast).timeIntervalSince1970)
            let result = line.withUnsafeBytes { sqlite3_bind_blob(statement, 4, $0.baseAddress, Int32($0.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            guard result == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else { throw error() }
        }
    }
    private func saveSignature(_ signature: String) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO source_state VALUES (1,?) ON CONFLICT(singleton) DO UPDATE SET signature=excluded.signature", -1, &statement, nil) == SQLITE_OK else { throw error() }
        defer { sqlite3_finalize(statement) }
        try bind(signature, at: 1, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw error() }
    }
    private func bind(_ value: String, at index: Int32, to statement: OpaquePointer?) throws {
        let result = value.withCString { sqlite3_bind_text(statement, index, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        guard result == SQLITE_OK else { throw error() }
    }
    private func transaction<T>(_ operation: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE;")
        do { let value = try operation(); try execute("COMMIT;"); return value }
        catch { try? execute("ROLLBACK;"); throw error }
    }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw error() }
    }
    private func error() -> NSError {
        NSError(domain: "ConnorTaskHistoryIndex", code: Int(sqlite3_errcode(db)), userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))])
    }
    private final class Registry: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [String: TaskRunHistoryIndex] = [:]
        func index(_ source: URL) throws -> TaskRunHistoryIndex {
            lock.lock(); defer { lock.unlock() }
            if let index = entries[source.path] { return index }
            let index = try TaskRunHistoryIndex(source: source)
            if entries.count >= 8, let key = entries.keys.first { entries.removeValue(forKey: key) }
            entries[source.path] = index
            return index
        }
    }
}
