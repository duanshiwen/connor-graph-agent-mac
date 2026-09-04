import Foundation
import SQLite3

/// M1-K2：每 App 独立 SQLite 子库（D3：`base_<appID>.db`，App Support 目录）。
///
/// 职责：
/// - 连接按 App 上下文打开（每子库一个独立文件，物理隔离）；
/// - 系统表：`base_pkg_state`（包版本 latest，M3 同步复用为内容源）、
///   `schema_migrations`（迁移记录，M3 随包重放依赖）、`base_schema_cache`（列类型映射）；
/// - 用户表：`id TEXT PRIMARY KEY` + 字段列 + `_meta` JSON 列；
/// - CRUD / DDL 全部参数绑定或白名单校验（永不字符串拼接值）。
public final class BaseSubLibraryStore: @unchecked Sendable {

    public let appID: String
    public let dbURL: URL

    private var db: OpaquePointer?
    private var typeCache: [String: [String: String]] = [:] // table -> column -> type

    // MARK: 生命周期

    public init(appID: String, directory: URL) throws {
        guard BaseSchemaValidator.isValidAppID(appID) else {
            throw BaseError(code: .validationFailed, message: "appID 不合法", hint: "appID 须匹配 ^[a-z0-9_-]{1,48}$")
        }
        self.appID = appID
        self.dbURL = directory.appendingPathComponent("base_\(appID).db")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try open()
        try ensureSystemTables()
        try loadTypeCache()
    }

    deinit {
        close()
    }

    public func close() {
        guard let db else { return }
        sqlite3_close_v2(db)
        self.db = nil
    }

    // MARK: 打开 / 初始化

    private func open() throws {
        var handle: OpaquePointer?
        let rc = sqlite3_open_v2(dbURL.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard rc == SQLITE_OK, let handle else {
            throw BaseError.internal("无法打开子库 \(appID)：\(lastMessage(handle))")
        }
        db = handle
        execVoidNoThrow("PRAGMA journal_mode=WAL;")
        execVoidNoThrow("PRAGMA foreign_keys=ON;")
        execVoidNoThrow("PRAGMA busy_timeout=5000;")
    }

    private func ensureSystemTables() throws {
        // 包版本表：单行 latest（包写乐观并发，M3 同步复用）。
        try executeVoid("""
            CREATE TABLE IF NOT EXISTS base_pkg_state (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                package_version INTEGER NOT NULL DEFAULT 0,
                updated_at TEXT NOT NULL
            );
            """)
        try executeVoid("INSERT OR IGNORE INTO base_pkg_state (id, package_version, updated_at) VALUES (1, 0, ?1);",
                        parameters: [BaseTime.isoNow()])
        // 迁移记录表（M3 随包确定性重放依赖）。
        try executeVoid("""
            CREATE TABLE IF NOT EXISTS schema_migrations (
                version INTEGER PRIMARY KEY,
                applied_at TEXT NOT NULL
            );
            """)
        // 列类型缓存：区分 boolean 与 number（SQLite 动态类型）。
        try executeVoid("""
            CREATE TABLE IF NOT EXISTS base_schema_cache (
                table_name TEXT NOT NULL,
                column_name TEXT NOT NULL,
                column_type TEXT NOT NULL,
                PRIMARY KEY (table_name, column_name)
            );
            """)
        // 幂等表（M1-K5）：本地去重，不同步。
        try executeVoid("""
            CREATE TABLE IF NOT EXISTS base_idempotency (
                idempotency_key TEXT PRIMARY KEY,
                response_json TEXT NOT NULL,
                created_at TEXT NOT NULL
            );
            """)
        // 记录顺序表（M1-K5 修正）：子库级确定性顺序 ID（rec_N，与 golden 契约一致），单行自增。
        try executeVoid("""
            CREATE TABLE IF NOT EXISTS base_record_seq (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                seq INTEGER NOT NULL
            );
            """)
        try executeVoid("INSERT OR IGNORE INTO base_record_seq (id, seq) VALUES (1, 0);")
        // 审计日志表（M1-M7）：端侧、按子库分域、不参与同步对象（不同步）。
        try executeVoid("""
            CREATE TABLE IF NOT EXISTS base_audit_log (
                seq INTEGER PRIMARY KEY AUTOINCREMENT,
                operation TEXT NOT NULL,
                detail TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL
            );
            """)
    }

    private func loadTypeCache() throws {
        typeCache = [:]
        let rows = try execute("SELECT table_name, column_name, column_type FROM base_schema_cache")
        for row in rows {
            guard let t = row["table_name"] as? String,
                  let c = row["column_name"] as? String,
                  let ty = row["column_type"] as? String else { continue }
            typeCache[t, default: [:]][c] = ty
        }
    }

    // MARK: 审计（M1-M7）

    /// 写入一条审计记录（best-effort：日志失败不影响主流程，端侧、不同步）。
    public func recordAudit(operation: String, detail: String) {
        try? executeVoid(
            "INSERT INTO base_audit_log (operation, detail, created_at) VALUES (?1, ?2, ?3);",
            parameters: [operation, detail, BaseTime.isoNow()]
        )
    }

    /// 读取审计记录（只读、端侧；base.audit.read 读取面在 M2 开放）。
    public func readAudit(limit: Int = 100) -> [[String: Any]] {
        let rows = (try? execute("SELECT seq, operation, detail, created_at FROM base_audit_log ORDER BY seq DESC LIMIT ?1", parameters: [limit])) ?? []
        return rows
    }

    // MARK: 包版本（M3 同步直接复用）

    public func latestPackageVersion() throws -> Int {
        let rows = try execute("SELECT package_version FROM base_pkg_state WHERE id = 1")
        guard let row = rows.first, let v = row["package_version"] as? Int64 else { return 0 }
        return Int(v)
    }

    /// 单调前移 latest（包写乐观并发，永不回退）。
    public func advancePackageVersion(to version: Int) throws {
        let current = try latestPackageVersion()
        guard version > current else {
            throw BaseError(code: .versionMismatch,
                            message: "包版本过期",
                            hint: "当前 latest 为 \(current)，拒绝回退到 \(version)；拉最新包 rebase 后重提")
        }
        try executeVoid("UPDATE base_pkg_state SET package_version = ?1, updated_at = ?2 WHERE id = 1",
                        parameters: [version, BaseTime.isoNow()])
    }

    // MARK: 迁移记录

    public func appliedMigrations() throws -> [Int] {
        let rows = try execute("SELECT version FROM schema_migrations ORDER BY version")
        return rows.compactMap { ($0["version"] as? Int64).map(Int.init) }
    }

    public func recordMigration(_ version: Int) throws {
        try executeVoid("INSERT INTO schema_migrations (version, applied_at) VALUES (?1, ?2)",
                        parameters: [version, BaseTime.isoNow()])
    }

    // MARK: 幂等（M1-K5）

    public func idempotencyResponse(for key: String) throws -> [String: Any]? {
        let rows = try execute("SELECT response_json FROM base_idempotency WHERE idempotency_key = ?1",
                               parameters: [key])
        guard let raw = rows.first?["response_json"] as? String,
              let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj
    }

    public func saveIdempotency(key: String, response: [String: Any]) throws {
        let raw = (try? JSONSerialization.data(withJSONObject: response))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        try executeVoid("""
            INSERT OR REPLACE INTO base_idempotency (idempotency_key, response_json, created_at)
            VALUES (?1, ?2, ?3)
            """, parameters: [key, raw, BaseTime.isoNow()])
    }

    // MARK: 记录顺序 ID（确定性 rec_N，非 UUID——golden 契约要求）

    /// 返回子库级顺序记录 ID（rec_1、rec_2、…），单调递增、事务内串行。
    public func nextRecordID() throws -> String {
        let rows = try execute("SELECT seq FROM base_record_seq WHERE id = 1")
        let next: Int64 = (rows.first?["seq"] as? Int64).map { $0 + 1 } ?? 1
        try executeVoid("""
            INSERT INTO base_record_seq (id, seq) VALUES (1, ?1)
            ON CONFLICT(id) DO UPDATE SET seq = excluded.seq
            """, parameters: [next])
        return "rec_\(next)"
    }

    // MARK: DDL（表名/列名经白名单校验后拼接，值永不拼接）

    public func tableExists(_ table: String) throws -> Bool {
        let rows = try execute("SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?1",
                               parameters: [table])
        return !rows.isEmpty
    }

    public func createTable(_ table: BaseTableDef) throws {
        guard BaseSchemaValidator.isValidName(table.name) else {
            throw BaseError.validation(.invalidTableName(table.name))
        }
        var columns: [String] = ["id TEXT PRIMARY KEY"]
        for field in table.fields {
            guard BaseSchemaValidator.isValidName(field.name) else {
                throw BaseError.validation(.invalidFieldName(field.name))
            }
            var col = "\"\(field.name)\" \(sqlColumnType(field.type))"
            if field.unique { col += " UNIQUE" }
            columns.append(col)
        }
        columns.append("_meta TEXT")
        let ddl = "CREATE TABLE IF NOT EXISTS \"\(table.name)\" (\n  \(columns.joined(separator: ",\n  "))\n)"
        try withTransaction {
            try executeVoid(ddl)
            for field in table.fields {
                try executeVoid(
                    "INSERT INTO base_schema_cache (table_name, column_name, column_type) VALUES (?1, ?2, ?3)",
                    parameters: [table.name, field.name, field.type]
                )
            }
        }
        typeCache[table.name] = Dictionary(uniqueKeysWithValues: table.fields.map { ($0.name, $0.type) })
    }

    /// M1 表变更：向既有表追加一列（ALTER TABLE ADD COLUMN + schema cache 同步）。
    /// 由 base.table.alter 的 addField 变更走，属于签名级变更（包版本由外层前移）。
    public func addColumn(_ field: BaseFieldDef, to table: String) throws {
        guard try tableExists(table) else {
            throw BaseError(code: .notFound, message: "表不存在", hint: "子库无表 \(table)")
        }
        guard BaseSchemaValidator.isValidName(field.name) else {
            throw BaseError.validation(.invalidFieldName(field.name))
        }
        guard columnType(of: field.name, in: table) == nil else {
            throw BaseError.validation(.duplicateField(field.name))
        }
        var ddl = "ALTER TABLE \"\(table)\" ADD COLUMN \"\(field.name)\" \(sqlColumnType(field.type))"
        if field.unique { ddl += " UNIQUE" }
        try withTransaction {
            try executeVoid(ddl)
            try executeVoid(
                "INSERT INTO base_schema_cache (table_name, column_name, column_type) VALUES (?1, ?2, ?3)",
                parameters: [table, field.name, field.type]
            )
        }
        var cache = typeCache[table] ?? [:]
        cache[field.name] = field.type
        typeCache[table] = cache
    }

    public func fields(of table: String) -> [String: String] {
        typeCache[table] ?? [:]
    }

    public func columnType(of column: String, in table: String) -> String? {
        typeCache[table]?[column]
    }

    // MARK: CRUD（参数绑定）

    public func insert(id: String, table: String, values: [String: JSONValue], meta: [String: Any] = [:]) throws {
        guard BaseSchemaValidator.isValidName(table) else {
            throw BaseError.validation(.invalidTableName(table))
        }
        var columns = ["id"]
        var params: [Any] = [id]
        for (key, value) in values {
            guard BaseSchemaValidator.isValidName(key) else {
                throw BaseError.validation(.invalidFieldName(key))
            }
            columns.append(key)
            params.append(sqlValue(value))
        }
        columns.append("_meta")
        params.append(metaJSON(meta))
        let placeholders = Array(repeating: "?", count: columns.count).joined(separator: ", ")
        let sql = "INSERT INTO \"\(table)\" (\(columns.map { "\"\($0)\"" }.joined(separator: ", ")))" +
            " VALUES (\(placeholders))"
        try executeVoid(sql, parameters: params)
    }

    public func update(id: String, table: String, values: [String: JSONValue], meta: [String: Any] = [:]) throws {
        guard BaseSchemaValidator.isValidName(table) else {
            throw BaseError.validation(.invalidTableName(table))
        }
        var sets: [String] = []
        var params: [Any] = []
        for (key, value) in values {
            guard BaseSchemaValidator.isValidName(key) else {
                throw BaseError.validation(.invalidFieldName(key))
            }
            sets.append("\"\(key)\" = ?")
            params.append(sqlValue(value))
        }
        params.append(metaJSON(meta))
        params.append(id)
        let sql = "UPDATE \"\(table)\" SET \(sets.joined(separator: ", ")), _meta = ? WHERE id = ?"
        try executeVoid(sql, parameters: params)
    }

    public func delete(id: String, table: String) throws {
        guard BaseSchemaValidator.isValidName(table) else {
            throw BaseError.validation(.invalidTableName(table))
        }
        try executeVoid("DELETE FROM \"\(table)\" WHERE id = ?1", parameters: [id])
    }

    public func fetch(id: String, table: String) throws -> [String: JSONValue]? {
        guard BaseSchemaValidator.isValidName(table) else {
            throw BaseError.validation(.invalidTableName(table))
        }
        let rows = try execute("SELECT * FROM \"\(table)\" WHERE id = ?1", parameters: [id])
        guard let row = rows.first else { return nil }
        return decodeRow(row, table: table)
    }

    // MARK: 通用执行（K4 编译器产出参数化 SQL 后调用）

    @discardableResult
    public func execute(_ sql: String, parameters: [Any] = []) throws -> [[String: Any]] {
        guard let db else { throw BaseError.internal("子库未打开") }
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let stmt else {
            throw BaseError.internal("SQL 编译失败：\(lastMessage(db))")
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, parameters)
        var rows: [[String: Any]] = []
        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_ROW {
                rows.append(row(from: stmt))
            } else if step == SQLITE_DONE {
                break
            } else {
                throw BaseError.internal("SQL 执行失败：\(lastMessage(db))") 
            }
        }
        return rows
    }

    @discardableResult
    public func executeVoid(_ sql: String, parameters: [Any] = []) throws -> Int {
        guard let db else { throw BaseError.internal("子库未打开") }
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let stmt else {
            throw BaseError.internal("SQL 编译失败：\(lastMessage(db))")
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, parameters)
        let step = sqlite3_step(stmt)
        guard step == SQLITE_DONE || step == SQLITE_ROW else {
            throw BaseError.internal("SQL 执行失败：\(lastMessage(db))")
        }
        return Int(sqlite3_changes(db))
    }

    public func withTransaction<T>(_ body: () throws -> T) throws -> T {
        guard let db else { throw BaseError.internal("子库未打开") }
        sqlite3_exec(db, "BEGIN IMMEDIATE;", nil, nil, nil)
        do {
            let result = try body()
            sqlite3_exec(db, "COMMIT;", nil, nil, nil)
            return result
        } catch {
            sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
            throw error
        }
    }

    // MARK: 编码 / 解码

    private func sqlColumnType(_ type: String) -> String {
        switch BaseFieldType(raw: type) {
        case .number: return "REAL"
        case .boolean: return "INTEGER"
        default: return "TEXT"
        }
    }

    private func sqlValue(_ value: JSONValue) -> Any {
        switch value {
        case .null:
            return NSNull()
        case .string(let s):
            return s
        case .number(let n):
            return n
        case .bool(let b):
            return b ? 1 : 0
        case .object, .array:
            // 基础字段类型不存对象/数组；防御性落 JSON 字符串。
            let data = try? JSONEncoder().encode(value)
            return data.flatMap { String(data: $0, encoding: .utf8) } ?? NSNull()
        }
    }

    private func decodeRow(_ row: [String: Any], table: String) -> [String: JSONValue] {
        var out: [String: JSONValue] = [:]
        for (key, value) in row {
            guard key != "id" else { continue }
            let type = typeCache[table]?[key]
            out[key] = jsonValue(from: value, type: type)
        }
        return out
    }

    private func jsonValue(from value: Any, type: String?) -> JSONValue {
        switch value {
        case let s as String:
            return .string(s)
        case let n as Int64:
            if type == "boolean" { return .bool(n != 0) }
            return .number(Double(n))
        case let n as Double:
            return .number(n)
        case let n as Int:
            if type == "boolean" { return .bool(n != 0) }
            return .number(Double(n))
        case is NSNull:
            return .null
        case let data as Data:
            return .string(String(data: data, encoding: .utf8) ?? "")
        default:
            return .null
        }
    }

    private func metaJSON(_ meta: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: meta) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    // MARK: sqlite3 辅助

    private func row(from stmt: OpaquePointer) -> [String: Any] {
        let count = sqlite3_column_count(stmt)
        var row: [String: Any] = [:]
        for i in 0..<count {
            let name = String(cString: sqlite3_column_name(stmt, i))
            switch sqlite3_column_type(stmt, i) {
            case SQLITE_TEXT:
                row[name] = String(cString: sqlite3_column_text(stmt, i))
            case SQLITE_INTEGER:
                row[name] = sqlite3_column_int64(stmt, i)
            case SQLITE_FLOAT:
                row[name] = sqlite3_column_double(stmt, i)
            case SQLITE_BLOB:
                if let blob = sqlite3_column_blob(stmt, i) {
                    let length = Int(sqlite3_column_bytes(stmt, i))
                    row[name] = Data(bytes: blob, count: length)
                }
            default:
                row[name] = NSNull()
            }
        }
        return row
    }

    private func bind(_ stmt: OpaquePointer, _ parameters: [Any]) {
        for (i, p) in parameters.enumerated() {
            let idx = Int32(i + 1)
            switch p {
            case let s as String:
                sqlite3_bind_text(stmt, idx, s, -1, sqliteTransient)
            case let n as Double:
                sqlite3_bind_double(stmt, idx, n)
            case let n as Int:
                sqlite3_bind_int64(stmt, idx, Int64(n))
            case let n as Int64:
                sqlite3_bind_int64(stmt, idx, n)
            case let b as Bool:
                sqlite3_bind_int(stmt, idx, b ? 1 : 0)
            case let data as Data:
                _ = data.withUnsafeBytes { buffer in
                    sqlite3_bind_blob(stmt, idx, buffer.baseAddress, Int32(buffer.count), sqliteTransient)
                }
            default:
                sqlite3_bind_null(stmt, idx)
            }
        }
    }

    private func lastMessage(_ handle: OpaquePointer?) -> String {
        guard let handle else { return "sqlite error" }
        return String(cString: sqlite3_errmsg(handle))
    }

    private func execVoidNoThrow(_ sql: String) {
        guard let db else { return }
        sqlite3_exec(db, sql, nil, nil, nil)
    }
}

/// M1-K2：统一 ISO8601 时间（UTC）工具。
public enum BaseTime {
    public static func isoNow() -> String {
        isoFormatter.string(from: Date())
    }

    public static func iso(from date: Date) -> String {
        isoFormatter.string(from: date)
    }

    nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

/// SQLite C 宏 SQLITE_TRANSIENT 在 Swift 中不可见，等价于 (sqlite3_destructor_type)-1。
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
