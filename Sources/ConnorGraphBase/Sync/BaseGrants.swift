import Foundation

/// M4-K1 · 权限能力位 grant：shared 态授权/回收（ACL 内核）。
///
/// 契约 `base.app.grant`（milestone M4, permission baseManageApps）：
/// shared 态授权/回收；服务端 ACL 权威；授权/信任状态随包状态 E2EE 同步，新设备免重新授权。
///
/// 端侧落地：注册库 `base_grants` 表（app_id, peer, granted, updated_at，主键 (app_id, peer)），
/// grant/revoke 幂等；仅 `visibility == shared` 可授权（private 拒绝 PERMISSION_DENIED，public 全公开无需授权）；
/// 授权状态作为包快照「可选段」（M4-K2，非空才输出）随包版本提交（M3-K5）同步，载荷经 M3-K4 整体加密；
/// 新设备重建（M3-K8）随包恢复，免重新授权。
extension BaseLibraryStore {

    /// 建表 `base_grants`（幂等）。
    public func ensureGrantsTable() throws {
        try registryExecuteVoid("""
            CREATE TABLE IF NOT EXISTS base_grants (
                app_id TEXT NOT NULL,
                peer TEXT NOT NULL,
                granted INTEGER NOT NULL DEFAULT 0,
                updated_at TEXT NOT NULL,
                PRIMARY KEY (app_id, peer)
            )
            """)
    }

    /// 当前 visibility（private/shared/public）。
    private func visibilityOf(_ appID: String) throws -> String {
        guard let pkg = try packageDictionary(appID: appID) else {
            throw BaseError.notFound("App \(appID) 不存在")
        }
        let manifest = pkg["manifest"] as? [String: Any] ?? [:]
        return manifest["visibility"] as? String ?? "private"
    }

    /// shared 态授权/回收（幂等）：grant=true 授权，grant=false 回收。
    ///
    /// 门控：仅 `visibility == shared` 可操作；peer 必填。
    /// 授权状态随包同步：写 `base_grants` 后走包版本提交（M3-K5），
    /// 新不可变版本记录含 ACL 段（M4-K2），latest 单调前移。返回新包版本号。
    @discardableResult
    public func grantAccess(appID: String, peer: String, grant: Bool) throws -> Int {
        guard try appExists(appID) else {
            throw BaseError.notFound("App \(appID) 不存在")
        }
        let trimmed = peer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw BaseError(code: .validationFailed, message: "peer 不能为空", hint: "被授权好友标识必填")
        }
        let visibility = try visibilityOf(appID)
        guard visibility == "shared" else {
            throw BaseError(
                code: .permissionDenied,
                message: "仅 shared 可见性应用可授权/回收",
                hint: "当前 visibility=\(visibility)，请先发布为 shared 后再授权"
            )
        }
        let now = BaseTime.isoNow()
        try ensureGrantsTable()
        let updated = try registryExecuteVoid("""
            INSERT INTO base_grants (app_id, peer, granted, updated_at)
            VALUES (?1, ?2, ?3, ?4)
            ON CONFLICT(app_id, peer) DO UPDATE SET granted = excluded.granted, updated_at = excluded.updated_at
            """, parameters: [appID, trimmed, grant ? 1 : 0, now])
        _ = updated
        // 授权状态随包同步：新版本记录（含 ACL 段）+ latest 单调前移。
        let current = try packageVersion(appID: appID)
        return try commitPackageVersion(appID: appID, basePackageVersion: current, alignGuide: false)
    }

    /// 读 App 全部授权记录（按 peer 升序）。
    public func grants(appID: String) throws -> [[String: Any]] {
        try ensureGrantsTable()
        let rows = try registryExecute(
            "SELECT peer, granted, updated_at FROM base_grants WHERE app_id = ?1 ORDER BY peer",
            parameters: [appID]
        )
        return rows.map { row in
            [
                "peer": row["peer"] ?? "",
                "granted": (row["granted"] as? Int64) ?? 0,
                "updatedAt": row["updated_at"] ?? "",
            ]
        }
    }

    /// 恢复授权记录（随包同步/新设备重建调用；幂等 upsert）。
    public func restoreGrants(appID: String, acls: [[String: Any]]) throws {
        guard !acls.isEmpty else { return }
        try ensureGrantsTable()
        for acl in acls {
            let peer = acl["peer"] as? String ?? ""
            guard !peer.isEmpty else { continue }
            let granted: Bool
            if let b = acl["granted"] as? Bool {
                granted = b
            } else if let n = acl["granted"] as? Int64 {
                granted = n != 0
            } else {
                granted = (acl["granted"] as? Int ?? 0) != 0
            }
            let updatedAt = acl["updatedAt"] as? String ?? BaseTime.isoNow()
            try registryExecuteVoid("""
                INSERT INTO base_grants (app_id, peer, granted, updated_at)
                VALUES (?1, ?2, ?3, ?4)
                ON CONFLICT(app_id, peer) DO UPDATE SET granted = excluded.granted, updated_at = excluded.updated_at
                """, parameters: [appID, peer, granted ? 1 : 0, updatedAt])
        }
    }
}
