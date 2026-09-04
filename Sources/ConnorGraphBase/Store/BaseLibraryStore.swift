import Foundation
import SQLite3

/// M1-M3/M1-M5：小应用注册表与包存取（应用层内核服务）。
///
/// 职责（施工图 M1-M5「AppPackage 四件套统一存取」+ M1-M3 工具所依赖的服务）：
/// - 应用注册表：一个中心库 `base_registry.db` 记录全部 App 的清单与四件套（manifest/schema/guide/methods）；
/// - 每 App 一个独立子库文件 `libraries/<appID>/base_<appID>.db`（D3 物理隔离）；
/// - 包写：`package_version` 单调前移（乐观并发，M3 同步直接复用为内容源）；
/// - 能力点门禁：manifest 声明 deferred 的 `import`（跨库只读导入，D24）即拒（CAPABILITY_REQUIRED）。
public final class BaseLibraryStore: @unchecked Sendable {

    public let rootDirectory: URL
    public let librariesDirectory: URL

    /// v1 发放的能力点（D24）：跨 App 调用 imports / 网络 network / 附件 asset。
    /// deferred 的 `import`（跨库只读导入）不在其中，声明即被契约校验拒绝。
    public static let grantedCapabilities: Set<String> = ["imports", "network", "asset"]

    private var db: OpaquePointer?

    // MARK: 生命周期

    public init(directory: URL) throws {
        self.rootDirectory = directory
        self.librariesDirectory = directory.appendingPathComponent("libraries", isDirectory: true)
        try FileManager.default.createDirectory(at: librariesDirectory, withIntermediateDirectories: true)
        try openRegistry()
        try ensureRegistryTables()
    }

    deinit { close() }

    public func close() {
        guard let db else { return }
        sqlite3_close_v2(db)
        self.db = nil
    }

    // MARK: 注册库

    private func openRegistry() throws {
        let url = rootDirectory.appendingPathComponent("base_registry.db")
        var handle: OpaquePointer?
        let rc = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard rc == SQLITE_OK, let handle else {
            throw BaseError(code: .internal, message: "无法打开 Base 注册库：\(lastMessage(handle))", hint: "")
        }
        db = handle
        sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA busy_timeout=5000;", nil, nil, nil)
    }

    private func ensureRegistryTables() throws {
        try executeVoid("""
            CREATE TABLE IF NOT EXISTS base_apps (
                app_id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                domain TEXT NOT NULL DEFAULT '',
                visibility TEXT NOT NULL DEFAULT 'private',
                package_version INTEGER NOT NULL DEFAULT 0,
                sdk_version INTEGER NOT NULL DEFAULT 1,
                risk_level TEXT NOT NULL DEFAULT 'low',
                capabilities_json TEXT NOT NULL DEFAULT '[]',
                imports_json TEXT NOT NULL DEFAULT '[]',
                schema_json TEXT NOT NULL DEFAULT '{"tables":[]}',
                guide_json TEXT NOT NULL DEFAULT '{}',
                methods_json TEXT NOT NULL DEFAULT '[]',
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            """)
    }

    // MARK: App 生命周期

    /// 创建正式私有小应用：四件套同批（v0.12 无中间态——需要表就直接建正式 App）。
    /// guide 为 App Guide 十一段结构化对象（契约 base.app.create 的 guide 是 object），创建时同步写。
    @discardableResult
    public func createApp(
        manifest: [String: Any],
        schemaObject: [String: Any],
        guide: [String: Any],
        methods: [[String: Any]] = []
    ) throws -> [String: Any] {
        let appID = manifest["appID"] as? String ?? ""
        guard BaseSchemaValidator.isValidAppID(appID) else {
            throw BaseError(code: .validationFailed, message: "appID 不合法", hint: "appID 须匹配 ^[a-z0-9_-]{1,48}$")
        }
        guard try !appExists(appID) else {
            throw BaseError(code: .validationFailed, message: "App 已存在", hint: "appID \(appID) 已被占用")
        }
        // 能力点门禁（D24）：deferred 的 import 即拒；未知能力点也拒。
        let capabilities = (manifest["requiredCapabilities"] as? [String]) ?? []
        for capability in capabilities {
            guard Self.grantedCapabilities.contains(capability) else {
                throw BaseError(code: .capabilityRequired,
                                message: "能力点不发放",
                                hint: "\(capability) 未发放（v1 仅发放 imports/network/asset；import 跨库只读导入 deferred 不发放，跨库交互仅走属主 exported 方法调用）")
            }
        }
        // 结构期严格校验（relation 目标表必须在 schema 内）。
        _ = try BaseSchemaValidator.parseSchema(schemaObject, validateRelations: true)
        // 指南创建时同步写（v0.6 契约）。
        guard !guide.isEmpty else {
            throw BaseError(code: .validationFailed, message: "指南缺失", hint: "App 创建时须同步写使用指南（App Guide 十一段），不允许空指南")
        }
        let name = manifest["name"] as? String ?? appID
        let domain = manifest["domain"] as? String ?? ""
        let visibility = manifest["visibility"] as? String ?? "private"
        let riskLevel = manifest["riskLevel"] as? String ?? "low"
        let sdkVersion = (manifest["sdkVersion"] as? Int) ?? 1
        let imports = (manifest["imports"] as? [[String: Any]]) ?? []
        let now = BaseTime.isoNow()
        try executeVoid("""
            INSERT INTO base_apps
                (app_id, name, domain, visibility, package_version, sdk_version, risk_level,
                 capabilities_json, imports_json, schema_json, guide_json, methods_json, created_at, updated_at)
            VALUES (?1, ?2, ?3, ?4, 1, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?12)
            """, parameters: [
                appID, name, domain, visibility,
                sdkVersion, riskLevel,
                Self.jsonString(capabilities), Self.jsonString(imports),
                Self.jsonString(schemaObject), Self.jsonString(guide), Self.jsonString(methods),
                now
            ])
        // 建子库 + 按 schema 建物理表（每 App 独立文件）。
        let store = try BaseSubLibraryStore(appID: appID, directory: librariesDirectory)
        defer { store.close() }
        let schema = try BaseSchemaValidator.parseSchema(schemaObject, validateRelations: true)
        for table in schema.tables {
            try store.createTable(table)
        }
        return try appCard(appID: appID) ?? [:]
    }

    /// 删除 App：注册行 + 子库文件（含 WAL/SHM）一并清除（墓碑 v0.8 的本地形态）。
    public func deleteApp(appID: String) throws {
        guard try appExists(appID) else {
            throw BaseError(code: .notFound, message: "App 不存在", hint: "appID \(appID)")
        }
        let store = try BaseSubLibraryStore(appID: appID, directory: librariesDirectory)
        store.close()
        try? FileManager.default.removeItem(at: store.dbURL)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: store.dbURL.path + "-wal"))
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: store.dbURL.path + "-shm"))
        try executeVoid("DELETE FROM base_apps WHERE app_id = ?1", parameters: [appID])
    }

    public func appExists(_ appID: String) throws -> Bool {
        let rows = try execute("SELECT 1 FROM base_apps WHERE app_id = ?1", parameters: [appID])
        return !rows.isEmpty
    }

    public func listApps(scope: String? = nil, query: String? = nil) throws -> [[String: Any]] {
        var sql = "SELECT * FROM base_apps"
        var params: [Any] = []
        var clauses: [String] = []
        if let scope, !scope.isEmpty, scope != "all" {
            clauses.append("visibility = ?")
            params.append(scope)
        }
        if let query, !query.isEmpty {
            clauses.append("(name LIKE ? OR domain LIKE ? OR app_id LIKE ?)")
            let like = "%\(query)%"
            params.append(like); params.append(like); params.append(like)
        }
        if !clauses.isEmpty { sql += " WHERE " + clauses.joined(separator: " AND ") }
        sql += " ORDER BY updated_at DESC"
        let rows = try execute(sql, parameters: params)
        return try rows.map { try card(from: $0) }
    }

    /// App Card：能力搜索面的确定性卡片（无 views 字段，v0.7）。
    public func appCard(appID: String, includeGuide: Bool = false) throws -> [String: Any]? {
        guard let row = try appRow(appID) else { return nil }
        var card = try card(from: row)
        if includeGuide {
            card["guide"] = (try? Self.decodeObject(row["guide_json"] as? String)) ?? [:]
        }
        return card
    }

    /// 完整包（四件套 + 版本）：M3 同步的内容源。
    public func packageDictionary(appID: String) throws -> [String: Any]? {
        guard let row = try appRow(appID) else { return nil }
        let manifest: [String: Any] = [
            "appID": row["app_id"] ?? "",
            "name": row["name"] ?? "",
            "domain": row["domain"] ?? "",
            "visibility": row["visibility"] ?? "private",
            "requiredCapabilities": (try? Self.decodeArray(row["capabilities_json"] as? String)) ?? [],
            "imports": (try? Self.decodeArray(row["imports_json"] as? String)) ?? [],
            "riskLevel": row["risk_level"] ?? "low",
            "sdkVersion": row["sdk_version"] as? Int64 ?? 1
        ]
        return [
            "manifest": manifest,
            "schema": (try? Self.decodeObject(row["schema_json"] as? String)) ?? ["tables": []],
            "guide": (try? Self.decodeObject(row["guide_json"] as? String)) ?? [:],
            "methods": (try? Self.decodeArray(row["methods_json"] as? String)) ?? [],
            "packageVersion": row["package_version"] as? Int64 ?? 0
        ]
    }

    public func packageVersion(appID: String) throws -> Int {
        let rows = try execute("SELECT package_version FROM base_apps WHERE app_id = ?1", parameters: [appID])
        guard let row = rows.first, let v = row["package_version"] as? Int64 else {
            throw BaseError(code: .notFound, message: "App 不存在", hint: "appID \(appID)")
        }
        return Int(v)
    }

    // MARK: 子库访问

    /// 打开 App 子库（物理隔离文件，D3）。调用方负责 close。
    public func openStore(appID: String) throws -> BaseSubLibraryStore {
        guard try appExists(appID) else {
            throw BaseError(code: .notFound, message: "App 不存在", hint: "appID \(appID)")
        }
        return try BaseSubLibraryStore(appID: appID, directory: librariesDirectory)
    }

    public func currentSchemaObject(appID: String) throws -> [String: Any] {
        guard let row = try appRow(appID) else {
            throw BaseError(code: .notFound, message: "App 不存在", hint: "appID \(appID)")
        }
        return (try? Self.decodeObject(row["schema_json"] as? String)) ?? ["tables": []]
    }

    public func currentSchema(appID: String) throws -> BaseAppSchema {
        try BaseSchemaValidator.parseSchema(try currentSchemaObject(appID: appID), validateRelations: false)
    }

    /// 签名级变更（table.create/alter）后回写包 schema 并单调前移 packageVersion。
    /// 结构变更永不自动合并（乐观并发，M3）；本方法只做本地 latest 前移。
    public func updateSchema(appID: String, schemaObject: [String: Any]) throws {
        _ = try BaseSchemaValidator.parseSchema(schemaObject, validateRelations: true)
        let updated = try executeVoid("""
            UPDATE base_apps
            SET schema_json = ?1, package_version = package_version + 1, updated_at = ?2
            WHERE app_id = ?3
            """, parameters: [Self.jsonString(schemaObject), BaseTime.isoNow(), appID])
        guard updated > 0 else {
            throw BaseError(code: .notFound, message: "App 不存在", hint: "appID \(appID)")
        }
    }

    // MARK: 行读取

    private func appRow(_ appID: String) throws -> [String: Any]? {
        let rows = try execute("SELECT * FROM base_apps WHERE app_id = ?1", parameters: [appID])
        return rows.first
    }

    private func card(from row: [String: Any]) throws -> [String: Any] {
        let appID = row["app_id"] as? String ?? ""
        let methods = (try? Self.decodeArray(row["methods_json"] as? String)) ?? []
        let methodSummaries: [[String: Any]] = methods.map { method in
            [
                "name": method["name"] ?? "",
                "description": method["description"] ?? "",
                "readOnly": method["readOnly"] ?? false,
                "exported": method["exports"] ?? false
            ]
        }
        return [
            "appID": appID,
            "name": row["name"] ?? "",
            "domain": row["domain"] ?? "",
            "visibility": row["visibility"] ?? "private",
            "packageVersion": row["package_version"] as? Int64 ?? 0,
            "sdkVersion": row["sdk_version"] as? Int64 ?? 1,
            "riskLevel": row["risk_level"] ?? "low",
            "requiredCapabilities": (try? Self.decodeArray(row["capabilities_json"] as? String)) ?? [],
            "imports": (try? Self.decodeArray(row["imports_json"] as? String)) ?? [],
            "methods": methodSummaries,
            "createdAt": row["created_at"] ?? "",
            "updatedAt": row["updated_at"] ?? ""
        ]
    }

    // MARK: JSON / SQLite 辅助

    static func jsonString<T>(_ value: T) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    static func decodeArray(_ text: String?) -> [[String: Any]]? {
        guard let text, let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        return obj
    }

    static func decodeObject(_ text: String?) -> [String: Any]? {
        guard let text, let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj
    }

    @discardableResult
    private func execute(_ sql: String, parameters: [Any] = []) throws -> [[String: Any]] {
        guard let db else { throw BaseError(code: .internal, message: "Base 注册库未打开", hint: "") }
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let stmt else {
            throw BaseError(code: .internal, message: "SQL 编译失败：\(lastMessage(db))", hint: "")
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
                throw BaseError(code: .internal, message: "SQL 执行失败：\(lastMessage(db))", hint: "")
            }
        }
        return rows
    }

    @discardableResult
    private func executeVoid(_ sql: String, parameters: [Any] = []) throws -> Int {
        guard let db else { throw BaseError(code: .internal, message: "Base 注册库未打开", hint: "") }
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let stmt else {
            throw BaseError(code: .internal, message: "SQL 编译失败：\(lastMessage(db))", hint: "")
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, parameters)
        let step = sqlite3_step(stmt)
        guard step == SQLITE_DONE || step == SQLITE_ROW else {
            throw BaseError(code: .internal, message: "SQL 执行失败：\(lastMessage(db))", hint: "")
        }
        return Int(sqlite3_changes(db))
    }

    private func withTransaction<T>(_ body: () throws -> T) throws -> T {
        guard let db else { throw BaseError(code: .internal, message: "Base 注册库未打开", hint: "") }
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

    private func bind(_ stmt: OpaquePointer, _ parameters: [Any]) {
        for (index, value) in parameters.enumerated() {
            let i = Int32(index + 1)
            switch value {
            case let text as String:
                sqlite3_bind_text(stmt, i, text, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            case let number as Int:
                sqlite3_bind_int64(stmt, i, Int64(number))
            case let number as Int64:
                sqlite3_bind_int64(stmt, i, number)
            case let number as Double:
                sqlite3_bind_double(stmt, i, number)
            case let flag as Bool:
                sqlite3_bind_int(stmt, i, flag ? 1 : 0)
            case is NSNull:
                sqlite3_bind_null(stmt, i)
            default:
                sqlite3_bind_text(stmt, i, "\(value)", -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
        }
    }

    private func row(from stmt: OpaquePointer) -> [String: Any] {
        let count = sqlite3_column_count(stmt)
        var result: [String: Any] = [:]
        for i in 0..<count {
            let name = String(cString: sqlite3_column_name(stmt, i))
            switch sqlite3_column_type(stmt, i) {
            case SQLITE_INTEGER:
                result[name] = sqlite3_column_int64(stmt, i)
            case SQLITE_FLOAT:
                result[name] = sqlite3_column_double(stmt, i)
            case SQLITE_TEXT:
                result[name] = String(cString: sqlite3_column_text(stmt, i))
            case SQLITE_NULL:
                result[name] = NSNull()
            default:
                if let text = sqlite3_column_text(stmt, i) {
                    result[name] = String(cString: text)
                }
            }
        }
        return result
    }

    private func lastMessage(_ db: OpaquePointer?) -> String {
        guard let db, let message = sqlite3_errmsg(db) else { return "unknown" }
        return String(cString: message)
    }
}
