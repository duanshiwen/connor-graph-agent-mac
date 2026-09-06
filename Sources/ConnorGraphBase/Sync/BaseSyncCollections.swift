import Foundation

/// M3-K2 · 四类同步集合落地：不可变包版本记录（`base_pkg_<appID>`）+ 密钥表（`base_keys`）。
///
/// 四类同步集合（v0.12 §3.4.1）：
/// ① `base_apps`（注册库，latest 指针/授权状态，已有）；
/// ② `base_pkg_<appID>`（注册库，不可变包版本记录：四件套全文 + migration 序列 + SHA-256 指纹）；
/// ③ `base_records_<appID>`（子库行数据，M3-K3 确定性导出/导入）；
/// ④ `base_keys`（注册库，E2EE 密钥材料，M3-K4 使用）。
///
/// 版本记录内容不可变（同版本禁止覆写）：结构变更总是产生新版本记录，latest 指针单调前移。
extension BaseLibraryStore {

    // MARK: base_pkg_<appID> 不可变包版本表

    /// 确保某 App 的不可变包版本表存在（appID 已契约校验，表名安全）。
    public func ensurePackageVersionTable(appID: String) throws {
        guard BaseSchemaValidator.isValidAppID(appID) else {
            throw BaseError(code: .validationFailed, message: "appID 不合法", hint: "appID 须匹配 ^[a-z0-9_-]{1,48}$")
        }
        try registryExecuteVoid("""
            CREATE TABLE IF NOT EXISTS "base_pkg_\(appID)" (
                package_version INTEGER PRIMARY KEY,
                manifest_json TEXT NOT NULL,
                schema_json TEXT NOT NULL,
                methods_json TEXT NOT NULL DEFAULT '[]',
                guide_json TEXT NOT NULL DEFAULT '{}',
                migrations_json TEXT NOT NULL DEFAULT '[]',
                fingerprint TEXT NOT NULL,
                created_at TEXT NOT NULL
            )
            """)
    }

    /// 写一条不可变包版本记录（内容寻址）。同版本已存在即抛 `VERSION_MISMATCH`（版本记录不可变，禁止覆写）。
    /// 指纹 = 快照 SHA-256（canonicalData），是 K9 三端对账的字节锚点。
    public func writePackageVersion(appID: String, snapshot: BasePackageSnapshot, migrations: [Int]) throws {
        try ensurePackageVersionTable(appID: appID)
        guard try readPackageVersion(appID: appID, version: snapshot.packageVersion) == nil else {
            throw BaseError(
                code: .versionMismatch,
                message: "包版本已存在（不可变）",
                hint: "base_pkg_\(appID) 已有版本 \(snapshot.packageVersion)；版本记录内容不可变，禁止覆写，须前移版本"
            )
        }
        let fingerprint = try snapshot.digest()
        try registryExecuteVoid("""
            INSERT INTO "base_pkg_\(appID)" (
                package_version, manifest_json, schema_json, methods_json, guide_json,
                migrations_json, fingerprint, created_at
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
            """, parameters: [
                snapshot.packageVersion,
                Self.jsonString(snapshot.manifestObject),
                Self.jsonString(snapshot.schemaObject),
                Self.jsonString(snapshot.methodsObjects),
                Self.jsonString(snapshot.guideObject),
                Self.jsonString(migrations),
                fingerprint,
                BaseTime.isoNow()
            ])
    }

    /// 读取某个不可变包版本（解码为结构化字典；不存在返回 nil）。
    public func readPackageVersion(appID: String, version: Int) throws -> [String: Any]? {
        try ensurePackageVersionTable(appID: appID)
        let rows = try registryExecute("SELECT * FROM \"base_pkg_\(appID)\" WHERE package_version = ?1",
                                       parameters: [version])
        guard let row = rows.first else { return nil }
        return [
            "packageVersion": (row["package_version"] as? Int64).map(Int.init) ?? version,
            "manifest": (try? Self.decodeObject(row["manifest_json"] as? String)) ?? [:],
            "schema": (try? Self.decodeObject(row["schema_json"] as? String)) ?? ["tables": []],
            "methods": (try? Self.decodeArray(row["methods_json"] as? String)) ?? [],
            "guide": (try? Self.decodeObject(row["guide_json"] as? String)) ?? [:],
            "migrations": Self.decodeIntArray(row["migrations_json"] as? String),
            "fingerprint": row["fingerprint"] as? String ?? "",
            "createdAt": row["created_at"] as? String ?? ""
        ]
    }

    /// 全部包版本指纹（version → SHA-256），K9 三端对账 / 分块校验。
    public func allPackageVersionFingerprints(appID: String) throws -> [Int: String] {
        try ensurePackageVersionTable(appID: appID)
        let rows = try registryExecute("SELECT package_version, fingerprint FROM \"base_pkg_\(appID)\" ORDER BY package_version",
                                       parameters: [])
        var out: [Int: String] = [:]
        for row in rows {
            if let v = (row["package_version"] as? Int64).map(Int.init),
               let f = row["fingerprint"] as? String {
                out[v] = f
            }
        }
        return out
    }

    /// 从版本记录重建 BasePackageSnapshot（K5/K8 恢复用）。
    public func packageSnapshot(fromVersionRecord appID: String, version: Int) throws -> BasePackageSnapshot? {
        guard let rec = try readPackageVersion(appID: appID, version: version) else { return nil }
        return BasePackageSnapshot(
            appID: appID,
            packageVersion: version,
            manifest: rec["manifest"] as? [String: Any] ?? [:],
            schema: rec["schema"] as? [String: Any],
            methods: rec["methods"] as? [[String: Any]],
            guide: rec["guide"] as? [String: Any] ?? [:]
        )
    }

    // MARK: base_keys 密钥表（M3-K4 E2EE 通道）

    public func ensureKeysTable() throws {
        try registryExecuteVoid("""
            CREATE TABLE IF NOT EXISTS base_keys (
                key_id TEXT PRIMARY KEY,
                kind TEXT NOT NULL,
                app_id TEXT NOT NULL DEFAULT '',
                payload_json TEXT NOT NULL,
                created_at TEXT NOT NULL
            )
            """)
    }

    /// 保存一条同步密钥（kind: master/app；payload_json 为 key material 的编码载荷）。
    public func saveSyncKey(keyID: String, kind: String, appID: String, payloadJSON: String) throws {
        try ensureKeysTable()
        try registryExecuteVoid("""
            INSERT INTO base_keys (key_id, kind, app_id, payload_json, created_at)
            VALUES (?1, ?2, ?3, ?4, ?5)
            """, parameters: [keyID, kind, appID, payloadJSON, BaseTime.isoNow()])
    }

    /// 全部同步密钥（只读）。
    public func readSyncKeys() throws -> [[String: Any]] {
        try ensureKeysTable()
        return try registryExecute(
            "SELECT key_id, kind, app_id, payload_json, created_at FROM base_keys ORDER BY key_id",
            parameters: [])
    }

    /// 取指定 kind/app 的密钥载荷（master 用 appID=""）。
    public func syncKeyPayload(kind: String, appID: String) throws -> String? {
        try ensureKeysTable()
        let rows = try registryExecute(
            "SELECT payload_json FROM base_keys WHERE kind = ?1 AND app_id = ?2 LIMIT 1",
            parameters: [kind, appID])
        return rows.first?["payload_json"] as? String
    }
}

// MARK: - JSON 辅助（Sync 扩展专用）

extension BaseLibraryStore {
    /// 解码 migration 序列（[Int] 的 JSON 文本）。
    static func decodeIntArray(_ text: String?) -> [Int] {
        guard let text, let data = text.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [NSNumber] else { return [] }
        return arr.map { $0.intValue }
    }
}
