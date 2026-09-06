import Foundation

/// M3-K6 · 迁移随包确定性重放：App 已存在且版本落后时的原地升级。
///
/// v0.12 §3.4.2 包写 + §3.4 应用整体同步：升级只走不可变版本记录链（`base_pkg_<appID>` 1..V），
/// 按版本顺序逐版确定性重放 schema 变更（建缺失表 / 加缺失列）；子库重放在单事务内，任一步失败
/// 整体 ROLLBACK（禁半迁移），`MIGRATION_FAILED` 停留旧版、旧数据可用。
///
/// 前置：同步先拉齐版本记录链（K8「拉包版本」），链缺失即 `MIGRATION_FAILED`（无法确定性重放）。
extension BaseLibraryStore {

    /// 原地升级：把 App 从当前版本确定性重放到 `target.packageVersion`（须落后）。
    /// 成功返回目标版本；失败抛 `MIGRATION_FAILED`，注册库与子库均停留旧版。
    @discardableResult
    public func upgradePackageSnapshot(_ target: BasePackageSnapshot) throws -> Int {
        let appID = target.appID
        guard try appExists(appID) else {
            throw BaseError.notFound("App \(appID) 不存在")
        }
        let current = try packageVersion(appID: appID)
        let targetVersion = target.packageVersion
        guard targetVersion > current else {
            return current // 幂等：不落后即 no-op。
        }
        let store = try openStore(appID: appID)
        defer { store.close() }
        // 子库重放单事务：任一版本失败整体回滚（禁半迁移）。
        do {
            try store.withTransaction {
                for v in (current + 1)...targetVersion {
                    guard let rec = try readPackageVersion(appID: appID, version: v) else {
                        throw BaseError(
                            code: .migrationFailed,
                            message: "版本链缺失",
                            hint: "base_pkg_\(appID) 无版本记录 \(v)，无法确定性重放；须先拉齐版本链"
                        )
                    }
                    // 确定性 schema 同步：按版本 v 的 schema 建缺失表 / 加缺失列。
                    let schema = (rec["schema"] as? [String: Any]) ?? ["tables": []]
                    try replaySchema(schema, into: store)
                    try store.recordMigration(v)
                    try store.advancePackageVersion(to: v)
                }
            }
        } catch let error as BaseError {
            if error.code == BaseErrorCode.migrationFailed.rawValue { throw error }
            throw BaseError(code: .migrationFailed, message: "迁移重放失败", hint: "\(error)")
        } catch {
            throw BaseError(code: .migrationFailed, message: "迁移重放失败", hint: "\(error)")
        }
        // 子库重放全部成功 → 注册库对齐目标包（四件套 + package_version/guide_version）。
        try alignRegistry(to: target)
        return targetVersion
    }

    // MARK: 私有

    /// 确定性 schema 同步：建缺失表 / 加缺失列（由不可变版本记录的 schema 派生，同版本必同结果）。
    private func replaySchema(_ schemaObject: [String: Any], into store: BaseSubLibraryStore) throws {
        let parsed = try BaseSchemaValidator.parseSchema(schemaObject, validateRelations: true)
        for table in parsed.tables {
            if try store.tableExists(table.name) {
                for field in table.fields {
                    if store.columnType(of: field.name, in: table.name) == nil {
                        try store.addColumn(field, to: table.name)
                    }
                }
            } else {
                try store.createTable(table)
            }
        }
    }

    /// 注册库对齐到目标包（四件套全文 + package_version/guide_version，指南随包、不漂移）。
    private func alignRegistry(to target: BasePackageSnapshot) throws {
        let m = target.manifestObject
        try registryExecuteVoid("""
            UPDATE base_apps
            SET name = ?1, domain = ?2, purpose = ?3, visibility = ?4, risk_level = ?5, sdk_version = ?6,
                capabilities_json = ?7, imports_json = ?8,
                schema_json = ?9, guide_json = ?10, methods_json = ?11,
                package_version = ?12, guide_version = ?13, updated_at = ?14
            WHERE app_id = ?15
            """, parameters: [
                m["name"] ?? "", m["domain"] ?? "", m["purpose"] ?? "",
                m["visibility"] ?? "private", m["riskLevel"] ?? "low",
                m["sdkVersion"] ?? 1,
                Self.jsonString(m["requiredCapabilities"] as? [String] ?? []),
                Self.jsonString(m["imports"] as? [[String: Any]] ?? []),
                Self.jsonString(target.schemaObject), Self.jsonString(target.guideObject),
                Self.jsonString(target.methodsObjects),
                target.packageVersion, target.packageVersion, BaseTime.isoNow(), target.appID
            ])
    }
}
