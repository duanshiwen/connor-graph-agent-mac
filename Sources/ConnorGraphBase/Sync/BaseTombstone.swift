import Foundation
import CryptoKit

/// M3-K7 · 墓碑一体传播：删 App = 包 + 版本 + 数据 + 安装注册一起墓碑传播。
///
/// 契约（app-package.schema.json §tombstone）：对端删库文件、移出能力搜索，不留「数据没了壳还在」。
/// `BaseTombstone` 为不可变墓碑（appID + 被删时 latest 包版本 + 指纹 + 删除时间），
/// 确定性 JSON（sortedKeys）+ SHA-256 指纹，与包快照/记录导出同一序列化协议。
///
/// 同步语义：sender `deleteApp` 产墓碑同步记录并一体清除本地（注册行/子库文件/版本链表）；
/// receiver `applyTombstone` 持久化墓碑并对本地已装 App 一体删除（幂等可重入）。
/// 能力搜索为派生查 `base_apps`（base.sdk.v1.json 列出可用 App），删注册行即移出搜索面。
public struct BaseTombstone: Sendable, Equatable {
    public let appID: String
    public let packageVersion: Int
    public let fingerprint: String
    public let deletedAt: String

    public init(appID: String, packageVersion: Int, fingerprint: String, deletedAt: String) {
        self.appID = appID
        self.packageVersion = packageVersion
        self.fingerprint = fingerprint
        self.deletedAt = deletedAt
    }

    /// 载荷字典。
    public var payload: [String: Any] {
        ["appID": appID, "packageVersion": packageVersion, "fingerprint": fingerprint, "deletedAt": deletedAt]
    }

    /// 确定性规范 JSON（sortedKeys），同墓碑必同字节。
    public func canonicalData() throws -> Data {
        try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .fragmentsAllowed])
    }

    /// SHA-256 十六进制指纹。
    public func digest() throws -> String {
        let data = try canonicalData()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - 墓碑同步集合（注册库 base_tombstones）

extension BaseLibraryStore {

    /// 确保墓碑表存在（同步集合：appID 主键、被删时 latest 包版本、指纹、删除时间）。
    public func ensureTombstonesTable() throws {
        try registryExecuteVoid("""
            CREATE TABLE IF NOT EXISTS base_tombstones (
                app_id TEXT PRIMARY KEY,
                package_version INTEGER NOT NULL,
                fingerprint TEXT NOT NULL,
                deleted_at TEXT NOT NULL
            )
            """)
    }

    /// 写一条墓碑记录（幂等：同 appID 保留最新）。
    public func recordTombstone(appID: String, packageVersion: Int, fingerprint: String, deletedAt: String) throws {
        guard BaseSchemaValidator.isValidAppID(appID) else {
            throw BaseError(code: .validationFailed, message: "appID 不合法", hint: "appID 须匹配 ^[a-z0-9_-]{1,48}$")
        }
        try ensureTombstonesTable()
        try registryExecuteVoid("""
            INSERT OR REPLACE INTO base_tombstones (app_id, package_version, fingerprint, deleted_at)
            VALUES (?1, ?2, ?3, ?4)
            """, parameters: [appID, packageVersion, fingerprint, deletedAt])
    }

    /// 读取某 App 墓碑（不存在返回 nil）。
    public func tombstone(appID: String) throws -> BaseTombstone? {
        try ensureTombstonesTable()
        let rows = try registryExecute("SELECT * FROM base_tombstones WHERE app_id = ?1", parameters: [appID])
        guard let row = rows.first,
              let version = (row["package_version"] as? Int64).map(Int.init) else { return nil }
        return BaseTombstone(
            appID: appID,
            packageVersion: version,
            fingerprint: row["fingerprint"] as? String ?? "",
            deletedAt: row["deleted_at"] as? String ?? ""
        )
    }

    /// 全部墓碑（同步枚举，按 appID 字典序）。
    public func allTombstones() throws -> [BaseTombstone] {
        try ensureTombstonesTable()
        let rows = try registryExecute(
            "SELECT app_id, package_version, fingerprint, deleted_at FROM base_tombstones ORDER BY app_id",
            parameters: [])
        return rows.compactMap { row in
            guard let appID = row["app_id"] as? String,
                  let version = (row["package_version"] as? Int64).map(Int.init) else { return nil }
            return BaseTombstone(
                appID: appID,
                packageVersion: version,
                fingerprint: row["fingerprint"] as? String ?? "",
                deletedAt: row["deleted_at"] as? String ?? ""
            )
        }
    }

    /// 一体清除某 App 的本地痕迹：子库文件（含 WAL/SHM）+ 注册行 + 包版本链表。
    private func purgeAppLocally(_ appID: String) throws {
        let store = try BaseSubLibraryStore(appID: appID, directory: librariesDirectory)
        store.close()
        try? FileManager.default.removeItem(at: store.dbURL)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: store.dbURL.path + "-wal"))
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: store.dbURL.path + "-shm"))
        try registryExecuteVoid("DELETE FROM base_apps WHERE app_id = ?1", parameters: [appID])
        try registryExecuteVoid("DROP TABLE IF EXISTS \"base_pkg_\(appID)\"", parameters: [])
    }

    /// 应用墓碑（对端）：持久化墓碑并一体删除本地已装 App。返回是否实际删除（幂等：已删则 false）。
    @discardableResult
    public func applyTombstone(_ tombstone: BaseTombstone) throws -> Bool {
        try recordTombstone(
            appID: tombstone.appID,
            packageVersion: tombstone.packageVersion,
            fingerprint: tombstone.fingerprint,
            deletedAt: tombstone.deletedAt
        )
        guard try appExists(tombstone.appID) else { return false }
        try purgeAppLocally(tombstone.appID)
        return true
    }
}
