import Foundation
import SQLite3

/// 按登录账号隔离 IM 本地缓存（每账号一库）：
/// - 已登录：`im/im-{userId}.sqlite`，各账号互不污染；
/// - 未登录/未知：`im/im.sqlite`（旧共享库，仅未登录态使用）。
///
/// 首次为某账号建库时，若旧共享库存在且其中所有本地消息都只属于该账号，
/// 则把整库迁移为该账号的库（保留单账号用户的历史缓存）；一旦旧库混合了
/// 多个账号的数据就不再迁移，避免把其它账号的历史混进当前账号
/// （各账号的历史仍由服务端按账号提供，刷新即可恢复）。
public enum ImStorageAccountResolver {
    public static func imDirectory(applicationSupportDirectory: URL) -> URL {
        applicationSupportDirectory.appendingPathComponent("im", isDirectory: true)
    }

    public static func sharedDatabaseURL(applicationSupportDirectory: URL) -> URL {
        imDirectory(applicationSupportDirectory: applicationSupportDirectory)
            .appendingPathComponent("im.sqlite")
    }

    public static func accountDatabaseURL(applicationSupportDirectory: URL, userID: Int64) -> URL {
        imDirectory(applicationSupportDirectory: applicationSupportDirectory)
            .appendingPathComponent("im-\(userID).sqlite")
    }

    public static func databaseURL(applicationSupportDirectory: URL, userID: Int64?) -> URL {
        guard let userID else { return sharedDatabaseURL(applicationSupportDirectory: applicationSupportDirectory) }
        return accountDatabaseURL(applicationSupportDirectory: applicationSupportDirectory, userID: userID)
    }

    // MARK: - 当前登录账号解析

    /// 从已保存的令牌对中尽力解析当前用户 id（JWT payload 的 `user_id`），失败返回 nil。
    public static func storedUserID(credentials: AppConnorAccountCredentialStore = .init()) -> Int64? {
        guard let token = (try? credentials.tokens())?.accessToken, !token.isEmpty else { return nil }
        return userID(fromAccessToken: token)
    }

    public static func userID(fromAccessToken token: String) -> Int64? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        guard let data = base64URLDecode(String(parts[1])),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        if let id = json["user_id"] as? NSNumber { return id.int64Value }
        if let id = json["user_id"] as? Int { return Int64(id) }
        if let id = json["user_id"] as? Int64 { return id }
        return nil
    }

    private static func base64URLDecode(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = base64.count % 4
        if padding != 0 { base64 += String(repeating: "=", count: 4 - padding) }
        return Data(base64Encoded: base64)
    }

    // MARK: - 旧共享库迁移

    /// 首次为账号建库时，把旧共享库整体迁移为该账号的库（仅当旧库只属于该账号时）。
    public static func migrateLegacyDatabaseIfNeeded(
        applicationSupportDirectory: URL,
        userID: Int64
    ) throws {
        let legacyURL = sharedDatabaseURL(applicationSupportDirectory: applicationSupportDirectory)
        let accountURL = accountDatabaseURL(applicationSupportDirectory: applicationSupportDirectory, userID: userID)
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: legacyURL.path) else { return }
        guard !fileManager.fileExists(atPath: accountURL.path) else { return }
        guard try soleMessageOwner(databaseURL: legacyURL) == userID else { return }
        try snapshot(databaseURL: legacyURL, into: accountURL)
    }

    /// 旧共享库中所有本地已发送消息的唯一 sender_id（SENDING/SENT/FAILED 均视为本地发送方）。
    /// 只有一个发送方时返回该 id，否则（无消息 / 混合账号）返回 nil。
    public static func soleMessageOwner(databaseURL: URL) throws -> Int64? {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return nil }
        var db: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            return nil
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        defer { if statement != nil { sqlite3_finalize(statement) } }
        let sql = "SELECT sender_id FROM im_messages WHERE status IN ('SENDING','SENT','FAILED') GROUP BY sender_id;"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        var owners: Set<Int64> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            owners.insert(sqlite3_column_int64(statement, 0))
        }
        return owners.count == 1 ? owners.first : nil
    }

    /// `VACUUM INTO` 产出与 WAL 状态一致的整库快照（目标文件必须不存在）。
    private static func snapshot(databaseURL: URL, into targetURL: URL) throws {
        try FileManager.default.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var db: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            throw ImStorageAccountResolverError.sqlite("无法打开旧 IM 库进行迁移")
        }
        defer { sqlite3_close(db) }
        let escaped = targetURL.path.replacingOccurrences(of: "'", with: "''")
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, "VACUUM INTO '\(escaped)';", nil, nil, &errorMessage)
        if result != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "VACUUM INTO 失败"
            sqlite3_free(errorMessage)
            throw ImStorageAccountResolverError.sqlite(message)
        }
    }
}

public enum ImStorageAccountResolverError: Error, LocalizedError {
    case sqlite(String)

    public var errorDescription: String? {
        switch self {
        case .sqlite(let message): message
        }
    }
}
