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

    // MARK: 审计（M1-M7）

    /// 写入一条审计记录到指定 App 子库（best-effort：子库不存在或失败即忽略）。
    public func recordAudit(appID: String, operation: String, detail: String) {
        guard let store = try? openStore(appID: appID) else { return }
        store.recordAudit(operation: operation, detail: detail)
        store.close()
    }

    /// 读取指定 App 子库的审计记录（只读、端侧）。
    public func readAudit(appID: String, limit: Int = 100) -> [[String: Any]] {
        guard let store = try? openStore(appID: appID) else { return [] }
        let rows = store.readAudit(limit: limit)
        store.close()
        return rows
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
                purpose TEXT NOT NULL DEFAULT '',
                visibility TEXT NOT NULL DEFAULT 'private',
                package_version INTEGER NOT NULL DEFAULT 0,
                sdk_version INTEGER NOT NULL DEFAULT 1,
                risk_level TEXT NOT NULL DEFAULT 'low',
                capabilities_json TEXT NOT NULL DEFAULT '[]',
                imports_json TEXT NOT NULL DEFAULT '[]',
                schema_json TEXT NOT NULL DEFAULT '{"tables":[]}',
                guide_json TEXT NOT NULL DEFAULT '{}',
                guide_version INTEGER NOT NULL DEFAULT 0,
                methods_json TEXT NOT NULL DEFAULT '[]',
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            """)
        // 迁移：旧库补 purpose 列（M2-M3 catalog 检索字段，dev 演进）。
        let columns = try execute("PRAGMA table_info(base_apps)")
        if !columns.contains(where: { ($0["name"] as? String) == "purpose" }) {
            try executeVoid("ALTER TABLE base_apps ADD COLUMN purpose TEXT NOT NULL DEFAULT ''", parameters: [])
        }
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
        let purpose = manifest["purpose"] as? String ?? ""
        let visibility = manifest["visibility"] as? String ?? "private"
        let riskLevel = manifest["riskLevel"] as? String ?? "low"
        let sdkVersion = (manifest["sdkVersion"] as? Int) ?? 1
        let imports = (manifest["imports"] as? [[String: Any]]) ?? []
        let now = BaseTime.isoNow()
        try executeVoid("""
            INSERT INTO base_apps
                (app_id, name, domain, purpose, visibility, package_version, sdk_version, risk_level,
                 capabilities_json, imports_json, schema_json, guide_json, guide_version, methods_json, created_at, updated_at)
            VALUES (?1, ?2, ?3, ?4, ?5, 1, ?6, ?7, ?8, ?9, ?10, ?11, 1, ?12, ?13, ?13)
            """, parameters: [
                appID, name, domain, purpose, visibility,
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
        // M3-K2：包版本链——写 v1 不可变版本记录（应用整体同步的版本面，latest=1）。
        let pkgSnapshot = try packageSnapshot(appID: appID)
        try ensurePackageVersionTable(appID: appID)
        try writePackageVersion(appID: appID, snapshot: pkgSnapshot, migrations: [])
        return try appCard(appID: appID) ?? [:]
    }

    /// 删除 App：包 + 版本 + 数据 + 安装注册一起墓碑传播（v0.12 §3.4 / M3-K7）。
    /// 产墓碑同步记录（被删时 latest 包版本 + 指纹）→ 删子库文件（含 WAL/SHM）→ 删注册行 →
    /// 删包版本链表（不留「数据没了壳还在」）；能力搜索为派生查 base_apps，删注册行即移出搜索面。
    public func deleteApp(appID: String) throws {
        guard try appExists(appID) else {
            throw BaseError(code: .notFound, message: "App 不存在", hint: "appID \(appID)")
        }
        // M3-K7 一体墓碑：捕获被删时 latest 包版本与指纹（版本链表删除前先取）。
        let fingerprints = try allPackageVersionFingerprints(appID: appID)
        let latest = fingerprints.keys.max() ?? 1
        try recordTombstone(appID: appID, packageVersion: latest,
                            fingerprint: fingerprints[latest] ?? "", deletedAt: BaseTime.isoNow())
        let store = try BaseSubLibraryStore(appID: appID, directory: librariesDirectory)
        store.close()
        try? FileManager.default.removeItem(at: store.dbURL)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: store.dbURL.path + "-wal"))
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: store.dbURL.path + "-shm"))
        try executeVoid("DELETE FROM base_apps WHERE app_id = ?1", parameters: [appID])
        try registryExecuteVoid("DROP TABLE IF EXISTS \"base_pkg_\(appID)\"", parameters: [])
    }

    public func appExists(_ appID: String) throws -> Bool {
        let rows = try execute("SELECT 1 FROM base_apps WHERE app_id = ?1", parameters: [appID])
        return !rows.isEmpty
    }

    /// 能力搜索 catalog（§6.6/§6.7）：scope 过滤 + 关键词检索。
    /// 检索字段：名称/领域/appID/一句话用途/方法名——「解锁你不知道自己有的应用」与「解锁你没用过的方法」。
    /// v1 端侧来源均为本人创建（source=private）；shared/installed 随 M4 服务端加入。
    public func listApps(scope: String? = nil, query: String? = nil) throws -> [[String: Any]] {
        var sql = "SELECT * FROM base_apps"
        var params: [Any] = []
        var clauses: [String] = []
        if let scope, !scope.isEmpty, scope != "all" {
            clauses.append("visibility = ?")
            params.append(scope)
        }
        if !clauses.isEmpty { sql += " WHERE " + clauses.joined(separator: " AND ") }
        sql += " ORDER BY updated_at DESC"
        let rows = try execute(sql, parameters: params)
        guard let query, !query.isEmpty else {
            return try rows.map { try card(from: $0) }
        }
        let needle = query.lowercased()
        var matched: [[String: Any]] = []
        for row in rows {
            let card = try card(from: row)
            let methods = (try? Self.decodeArray(row["methods_json"] as? String)) ?? []
            let methodNames = methods.compactMap { $0["name"] as? String }.joined(separator: " ")
            let haystack = [
                row["name"] as? String ?? "",
                row["domain"] as? String ?? "",
                row["app_id"] as? String ?? "",
                row["purpose"] as? String ?? "",
                methodNames
            ].joined(separator: " ").lowercased()
            if haystack.contains(needle) {
                matched.append(card)
            }
        }
        return matched
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
            "purpose": row["purpose"] ?? "",
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

    // MARK: 包版本对齐（M3-K1 · 快照恢复专用）

    /// 将 base_apps 行的 package_version/guide_version 对齐到目标版本（latest 单调，不倒退）。
    /// fresh restore 后 createApp 置 1，这里把 latest 对齐到快照版本（应用整体同步的版本面）。
    public func alignPackageVersion(appID: String, to version: Int) throws {
        let updated = try executeVoid("""
            UPDATE base_apps
            SET package_version = ?, guide_version = ?, updated_at = ?
            WHERE app_id = ?
            """, parameters: [version, version, BaseTime.isoNow(), appID])
        guard updated > 0 else {
            throw BaseError(code: .notFound, message: "App 不存在", hint: "appID \(appID)")
        }
    }

    // MARK: 指南同步与漂移检测（M2-M2）

    /// 指南是否漂移：签名级变更（schema/methods）后未同批改指南 → guide_version < package_version。
    public func isGuideOutOfSync(appID: String) throws -> Bool {
        let rows = try execute("SELECT package_version, guide_version FROM base_apps WHERE app_id = ?1", parameters: [appID])
        guard let row = rows.first else {
            throw BaseError(code: .notFound, message: "App 不存在", hint: "appID \(appID)")
        }
        let pkg = (row["package_version"] as? Int64) ?? 0
        let guide = (row["guide_version"] as? Int64) ?? 0
        return pkg > guide
    }

    /// 显式同步指南：写入新版 guide 并把 guide_version 对齐当前 package_version（消除漂移）。
    public func syncGuide(appID: String, guide: [String: Any]) throws {
        guard try appExists(appID) else {
            throw BaseError(code: .notFound, message: "App 不存在", hint: "appID \(appID)")
        }
        guard !guide.isEmpty else {
            throw BaseError(code: .validationFailed, message: "指南不能为空", hint: "App Guide 为十一段结构化对象")
        }
        let updated = try executeVoid("""
            UPDATE base_apps
            SET guide_json = ?1, guide_version = package_version, updated_at = ?2
            WHERE app_id = ?3
            """, parameters: [Self.jsonString(guide), BaseTime.isoNow(), appID])
        guard updated > 0 else {
            throw BaseError(code: .notFound, message: "App 不存在", hint: "appID \(appID)")
        }
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
    /// M3-K5 收口：结构变更永不自动合并，统一走「不可变版本记录 + 单调 latest」（commitPackageVersion）。
    /// basePackageVersion 提供时须等于当前 latest，否则 VERSION_MISMATCH（拉最新包 rebase 后重提）；
    /// 缺省 nil 取当前 latest（无 token 调用面兼容）。
    public func updateSchema(appID: String, schemaObject: [String: Any], basePackageVersion: Int? = nil) throws {
        _ = try BaseSchemaValidator.parseSchema(schemaObject, validateRelations: true)
        let current = try packageVersion(appID: appID)
        // 乐观并发前置校验：过期提交零副作用（不写 schema_json、不建版本记录）。
        if let base = basePackageVersion, base != current {
            throw BaseError(
                code: .versionMismatch,
                message: "包版本过期",
                hint: "当前版本 \(current)，提交基于 \(base)，请拉最新包 rebase 后重提"
            )
        }
        let updated = try executeVoid("""
            UPDATE base_apps
            SET schema_json = ?1, updated_at = ?2
            WHERE app_id = ?3
            """, parameters: [Self.jsonString(schemaObject), BaseTime.isoNow(), appID])
        guard updated > 0 else {
            throw BaseError(code: .notFound, message: "App 不存在", hint: "appID \(appID)")
        }
        // M3-K5：不可变版本记录 + 单调 latest（结构变更保留指南漂移位）。
        _ = try commitPackageVersion(appID: appID, basePackageVersion: basePackageVersion ?? current, alignGuide: false)
    }

    // MARK: 方法定义与调用解析（M2-M1 / M2-K2）

    /// 包内方法清单（契约 methodDef 数组同构）。
    public func methods(appID: String) throws -> [[String: Any]] {
        guard let row = try appRow(appID) else {
            throw BaseError(code: .notFound, message: "App 不存在", hint: "appID \(appID)")
        }
        return (try? Self.decodeArray(row["methods_json"] as? String)) ?? []
    }

    /// 读取单个方法定义（解析为 BaseMethodDef）。
    public func methodDef(appID: String, name: String) throws -> BaseMethodDef? {
        let list = try methods(appID: appID)
        guard let json = list.first(where: { ($0["name"] as? String) == name }) else {
            return nil
        }
        return try BaseMethodDef(json: json)
    }

    /// 定义/更新方法（base.method.define）：签名级变更 → 单调前移 packageVersion。
    public func defineMethod(appID: String, method: [String: Any]) throws {
        // 先解析校验（步骤类型/配额/只读推导），失败即拒。
        let def = try BaseMethodDef(json: method)
        guard try appExists(appID) else {
            throw BaseError(code: .notFound, message: "App 不存在", hint: "appID \(appID)")
        }
        var list = try methods(appID: appID)
        if let idx = list.firstIndex(where: { ($0["name"] as? String) == def.name }) {
            list[idx] = method
        } else {
            list.append(method)
        }
        try updatePackageMethods(appID: appID, methods: list)
    }

    /// 移除方法（base.method.remove）：签名级变更 → 单调前移 packageVersion。
    public func removeMethod(appID: String, name: String) throws {
        guard try appExists(appID) else {
            throw BaseError(code: .notFound, message: "App 不存在", hint: "appID \(appID)")
        }
        var list = try methods(appID: appID)
        let before = list.count
        list.removeAll { ($0["name"] as? String) == name }
        guard list.count < before else {
            throw BaseError(code: .notFound, message: "方法不存在", hint: name)
        }
        try updatePackageMethods(appID: appID, methods: list)
    }

    private func updatePackageMethods(appID: String, methods: [[String: Any]]) throws {
        let current = try packageVersion(appID: appID)
        let updated = try executeVoid("""
            UPDATE base_apps
            SET methods_json = ?1, updated_at = ?2
            WHERE app_id = ?3
            """, parameters: [Self.jsonString(methods), BaseTime.isoNow(), appID])
        guard updated > 0 else {
            throw BaseError(code: .notFound, message: "App 不存在", hint: "appID \(appID)")
        }
        // M3-K5：不可变版本记录 + 单调 latest（方法签名级变更，保留指南漂移位）。
        _ = try commitPackageVersion(appID: appID, basePackageVersion: current, alignGuide: false)
    }

    /// 解析方法调用目标（base.method.invoke / 解释器 call 步骤用）。
    /// reference 形如 `methodName`（同 App）或 `appID.methodName`（跨 App）。
    /// 解析优先级：先在 callingAppID 内按完整 reference 找同名方法（方法名本身可含点，如 summary.monthly）；
    /// 找不到再按 `appID.methodName` 切分做跨 App 解析。
    /// 跨 App：调用方 manifest imports 须声明目标 appID（v0.12 §2.3/§5.3），且目标方法须 exported。
    /// 返回的目标 store 由调用方负责 close。
    public func methodTarget(callingAppID: String, reference: String) throws -> BaseMethodTarget? {
        // 1) 同 App 优先：方法名本身可含点，先在当前 App 内找完整 reference。
        if let localDef = try methodDef(appID: callingAppID, name: reference) {
            let store = try openStore(appID: callingAppID)
            let schema = try currentSchema(appID: callingAppID)
            return BaseMethodTarget(appID: callingAppID, store: store, schema: schema, method: localDef)
        }
        // 2) 跨 App：按 `appID.methodName` 切分。
        let parts = reference.split(separator: ".").map(String.init)
        let targetAppID: String
        let methodName: String
        if parts.count >= 2 {
            targetAppID = parts[0]
            methodName = parts[1...].joined(separator: ".")
        } else {
            targetAppID = callingAppID
            methodName = reference
        }
        guard try appExists(targetAppID) else {
            throw BaseError(code: .notFound, message: "目标 App 不存在", hint: targetAppID)
        }
        guard let def = try methodDef(appID: targetAppID, name: methodName) else {
            return nil
        }
        if targetAppID != callingAppID {
            // imports 校验：调用方 manifest imports 须声明目标 appID。
            guard let callerRow = try appRow(callingAppID),
                  let callerImports = (try? Self.decodeArray(callerRow["imports_json"] as? String)) as [[String: Any]]?,
                  callerImports.contains(where: { ($0["appID"] as? String) == targetAppID }) else {
                throw BaseError(code: .permissionDenied, message: "未声明跨 App 依赖", hint: "在调用方 manifest imports 中声明 \(targetAppID)")
            }
            // exported 门禁（解释器跨上下文也会再校验一次）。
            guard def.exports else {
                throw BaseError(code: .permissionDenied, message: "方法 \(methodName) 未导出，无法被跨 App 调用", hint: "请属主设置 exports=true")
            }
        }
        let store = try openStore(appID: targetAppID)
        let schema = try currentSchema(appID: targetAppID)
        return BaseMethodTarget(appID: targetAppID, store: store, schema: schema, method: def)
    }

    /// 更新 App 元数据（base.app.update）：乐观并发 + 可选指南同步。
    /// 携带 basePackageVersion 时，过期提交返 VERSION_MISMATCH（结构写串行化，v0.8）。
    public func updateApp(
        appID: String,
        manifest: [String: Any],
        guide: [String: Any]?,
        basePackageVersion: Int?
    ) throws -> [String: Any] {
        guard var row = try appRow(appID) else {
            throw BaseError(code: .notFound, message: "App 不存在", hint: "appID \(appID)")
        }
        if let baseVersion = basePackageVersion {
            let current = (row["package_version"] as? Int64).map(Int.init) ?? 0
            guard current == baseVersion else {
                throw BaseError(
                    code: .versionMismatch,
                    message: "包版本过期",
                    hint: "当前版本 \(current)，提交基于 \(baseVersion)，请拉最新包 rebase 后重提"
                )
            }
        }
        let name = manifest["name"] as? String ?? (row["name"] as? String ?? appID)
        let domain = manifest["domain"] as? String ?? (row["domain"] as? String ?? "")
        let purpose = manifest["purpose"] as? String ?? (row["purpose"] as? String ?? "")
        let visibility = manifest["visibility"] as? String ?? (row["visibility"] as? String ?? "private")
        let riskLevel = manifest["riskLevel"] as? String ?? (row["risk_level"] as? String ?? "low")
        let sdkVersion = (manifest["sdkVersion"] as? Int) ?? (row["sdk_version"] as? Int ?? 1)
        // 能力点重新门禁：仅当显式提供 requiredCapabilities 时校验并更新。
        if let capabilities = manifest["requiredCapabilities"] as? [String] {
            for capability in capabilities {
                guard Self.grantedCapabilities.contains(capability) else {
                    throw BaseError(code: .capabilityRequired, message: "能力点不发放", hint: "\(capability) 未发放")
                }
            }
            row["capabilities_json"] = Self.jsonString(capabilities)
        }
        // imports 显式提供则更新。
        if let imports = manifest["imports"] as? [[String: Any]] {
            row["imports_json"] = Self.jsonString(imports)
        }
        // 指南显式提供则同步更新（防止漂移）。
        var guideJSON: String = row["guide_json"] as? String ?? ""
        if let guide, !guide.isEmpty {
            guideJSON = Self.jsonString(guide)
        }
        let updated = try executeVoid("""
            UPDATE base_apps
            SET name = ?1, domain = ?2, purpose = ?3, visibility = ?4, risk_level = ?5, sdk_version = ?6,
                capabilities_json = ?7, imports_json = ?8, guide_json = ?9, updated_at = ?10
            WHERE app_id = ?11
            """, parameters: [
                name, domain, purpose, visibility, riskLevel, sdkVersion,
                row["capabilities_json"] as? String ?? "[]",
                row["imports_json"] as? String ?? "[]",
                guideJSON,
                BaseTime.isoNow(), appID
            ])
        guard updated > 0 else {
            throw BaseError(code: .notFound, message: "App 不存在", hint: "appID \(appID)")
        }
        // M3-K5：不可变版本记录 + 单调 latest；指南随签名级变更同步（guide 提供时 guide_version 对齐防漂移）。
        let current = (row["package_version"] as? Int64).map(Int.init) ?? 0
        _ = try commitPackageVersion(
            appID: appID,
            basePackageVersion: current,
            alignGuide: (guide?.isEmpty == false)
        )
        return try appCard(appID: appID) ?? [:]
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
            "purpose": row["purpose"] ?? "",
            "visibility": row["visibility"] ?? "private",
            "source": "private",
            "packageVersion": row["package_version"] as? Int64 ?? 0,
            "compatible": (row["sdk_version"] as? Int64 ?? 1) <= 1,
            "guideOutOfSync": ((row["package_version"] as? Int64) ?? 0) > ((row["guide_version"] as? Int64) ?? 0),
            "sdkVersion": row["sdk_version"] as? Int64 ?? 1,
            "riskLevel": row["risk_level"] ?? "low",
            "requiredCapabilities": (try? Self.decodeArray(row["capabilities_json"] as? String)) ?? [],
            "imports": (try? Self.decodeArray(row["imports_json"] as? String)) ?? [],
            "methods": methodSummaries,
            "createdAt": row["created_at"] ?? "",
            "updatedAt": row["updated_at"] ?? ""
        ]
    }

    // MARK: 同步集合 SQL 访问（M3-K2）

    /// 注册库只读查询透传（M3 同步集合实现用；与子库 public execute 对齐）。
    @discardableResult
    public func registryExecute(_ sql: String, parameters: [Any] = []) throws -> [[String: Any]] {
        try execute(sql, parameters: parameters)
    }

    /// 注册库写透传（M3 同步集合实现用）。
    @discardableResult
    public func registryExecuteVoid(_ sql: String, parameters: [Any] = []) throws -> Int {
        try executeVoid(sql, parameters: parameters)
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
