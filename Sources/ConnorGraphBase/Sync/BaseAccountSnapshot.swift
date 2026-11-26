import Foundation
import CryptoKit

private final class BaseSnapshotLocks: @unchecked Sendable {
    static let shared = BaseSnapshotLocks()
    private let gate = NSLock()
    private var roots: [String: NSRecursiveLock] = [:]
    func lock(_ root: URL) -> NSRecursiveLock {
        gate.lock(); defer { gate.unlock() }
        let key = root.standardizedFileURL.path
        if let existing = roots[key] { return existing }
        let value = NSRecursiveLock(); roots[key] = value; return value
    }
}

/// Whole-app account snapshots. The account transport seals these before upload.
/// An intent and a generation in both SQLite files recover interrupted WAL commits.
extension BaseLibraryStore {
    var accountSnapshotLock: NSRecursiveLock { BaseSnapshotLocks.shared.lock(rootDirectory) }
    private static let snapshotSystemTables: Set<String> = ["base_pkg_state", "schema_migrations", "base_schema_cache", "base_idempotency", "base_record_seq", "base_audit_log", "base_sync_marker"]
    public func ensureAccountSnapshotTables() throws {
        for sql in [
            "CREATE TABLE IF NOT EXISTS base_sync_owners(app_id TEXT PRIMARY KEY,account_id TEXT NOT NULL)",
            "CREATE TABLE IF NOT EXISTS base_sync_journal(app_id TEXT PRIMARY KEY,account_id TEXT NOT NULL,snapshot_json TEXT NOT NULL,generation TEXT NOT NULL)",
            "CREATE TABLE IF NOT EXISTS base_sync_applied(app_id TEXT PRIMARY KEY,generation TEXT NOT NULL)",
            "CREATE TABLE IF NOT EXISTS base_sync_deletions(app_id TEXT PRIMARY KEY,account_id TEXT NOT NULL,deleted_at INTEGER NOT NULL)",
            "CREATE TABLE IF NOT EXISTS base_sync_restores(app_id TEXT PRIMARY KEY,account_id TEXT NOT NULL)"
        ] { try registryExecuteVoid(sql) }
        try ensureKeysTable()
    }
    public static func snapshotFingerprint(_ snapshot: [String: Any]) throws -> String {
        SHA256.hash(data: try JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys, .withoutEscapingSlashes])).map { String(format: "%02x", $0) }.joined()
    }
    public func accountSnapshots(account: String) throws -> [String: [String: Any]] {
        accountSnapshotLock.lock(); defer { accountSnapshotLock.unlock() }
        var result: [String: [String: Any]] = [:]
        for app in try listApps() {
            guard let id = app["appID"] as? String else { continue }
            try registryExecuteVoid("INSERT OR IGNORE INTO base_sync_owners(app_id,account_id) VALUES(?1,?2)", parameters: [id,account])
            if try !registryExecute("SELECT 1 FROM base_sync_owners WHERE app_id=?1 AND account_id=?2", parameters: [id,account]).isEmpty { result[id] = try accountSnapshot(appID: id) }
        }
        return result
    }
    public func accountSnapshot(appID: String) throws -> [String: Any] {
        accountSnapshotLock.lock(); defer { accountSnapshotLock.unlock() }
        guard try appExists(appID) else { throw BaseError.notFound(appID) }
        let store = try openStore(appID: appID); store.close()
        try registryExecuteVoid("ATTACH DATABASE ?1 AS base_sync_target", parameters: [store.dbURL.path])
        defer { try? registryExecuteVoid("DETACH DATABASE base_sync_target") }
        try registryExecuteVoid("BEGIN")
        do {
            let value = try attachedAccountSnapshot(appID)
            try registryExecuteVoid("COMMIT")
            guard try packageVersion(appID: appID) == value["sourcePackageVersion"] as? Int else { throw BaseError.internal("应用包在导出时变化，请重试") }
            return value
        } catch { try? registryExecuteVoid("ROLLBACK"); throw error }
    }
    private func attachedAccountSnapshot(_ id: String) throws -> [String: Any] {
        guard var package = try packageDictionary(appID: id), var manifest = package["manifest"] as? [String: Any], let schema = package["schema"] as? [String: Any] else { throw BaseError.notFound(id) }
        manifest["visibility"] = "private"; manifest.removeValue(forKey: "packageVersion")
        package["manifest"] = manifest; package.removeValue(forKey: "packageVersion")
        var tables: [String: Any] = [:]
        for table in try BaseSchemaValidator.parseSchema(schema, validateRelations: true).tables {
            tables[table.name] = try registryExecute("SELECT * FROM base_sync_target.\"\(table.name)\" ORDER BY id").map { raw in
                var row = raw
                if let meta = row["_meta"] as? String, let bytes = meta.data(using: .utf8) { row["_meta"] = (try? JSONSerialization.jsonObject(with: bytes)) ?? [:] }
                else { row["_meta"] = [String: Any]() }
                for field in table.fields where field.type == "boolean" { if let number = row[field.name] as? NSNumber { row[field.name] = number.boolValue } }
                return row
            }
        }
        let guideVersion = Int(try registryExecute("SELECT guide_version FROM base_apps WHERE app_id=?1", parameters: [id]).first?["guide_version"] as? Int64 ?? 1)
        let keys = try registryExecute("SELECT key_id,kind,app_id,payload_json,created_at FROM base_keys WHERE kind='app' AND app_id=?1 ORDER BY key_id", parameters: [id])
        return ["format":"connor-base-sync-v1","appID":id,"sourcePackageVersion":try packageVersion(appID:id),"guideVersion":guideVersion,"package":package,"data":["tables":tables],"keys":keys]
    }
    public func recoverAccountSnapshots() throws {
        accountSnapshotLock.lock(); defer { accountSnapshotLock.unlock() }
        for row in try registryExecute("SELECT * FROM base_sync_journal") {
            guard let id = row["app_id"] as? String, let account = row["account_id"] as? String, let generation = row["generation"] as? String, let text = row["snapshot_json"] as? String, let data = text.data(using:.utf8), let snapshot = try JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw BaseError.internal("同步恢复日志格式无效") }
            let store = try BaseSubLibraryStore(appID:id,directory:librariesDirectory); defer { store.close() }
            let hasMarker = try !store.execute("SELECT 1 FROM sqlite_master WHERE name='base_sync_marker' AND type='table'").isEmpty
            let local = hasMarker ? try store.execute("SELECT generation FROM base_sync_marker WHERE id=1").first?["generation"] as? String : nil
            let main = try registryExecute("SELECT generation FROM base_sync_applied WHERE app_id=?1",parameters:[id]).first?["generation"] as? String
            if local == generation && main == generation { try registryExecuteVoid("DELETE FROM base_sync_journal WHERE app_id=?1",parameters:[id]) }
            else { try applyAccountSnapshot(snapshot,account:account,expectedFingerprint:nil,recovering:true) }
        }
    }
    public func applyAccountSnapshot(_ snapshot:[String:Any], account:String, expectedFingerprint:String?, recovering:Bool = false) throws {
        accountSnapshotLock.lock(); defer { accountSnapshotLock.unlock() }
        guard snapshot["format"] as? String == "connor-base-sync-v1", let id = snapshot["appID"] as? String, BaseSchemaValidator.isValidAppID(id), !account.isEmpty else { throw BaseError.internal("同步包标识无效") }
        let deleted = snapshot["deleted"] as? Bool == true
        if let bound = try registryExecute("SELECT account_id FROM base_sync_owners WHERE app_id=?1",parameters:[id]).first?["account_id"] as? String, bound != account { throw BaseError.internal("本机同标识应用属于另一账号") }
        if try !recovering && !appExists(id) && FileManager.default.fileExists(atPath:librariesDirectory.appendingPathComponent("base_\(id).db").path) {
            guard try !registryExecute("SELECT 1 FROM base_sync_owners WHERE app_id=?1 AND account_id=?2",parameters:[id,account]).isEmpty,
                  let generation = try registryExecute("SELECT generation FROM base_sync_applied WHERE app_id=?1",parameters:[id]).first?["generation"] as? String else { throw BaseError.internal("同标识数据库尚未登记，已保留本机文件") }
            let retired = try BaseSubLibraryStore(appID:id,directory:librariesDirectory); defer { retired.close() }
            let names = try retired.execute("SELECT name FROM sqlite_master WHERE type='table'").compactMap{$0["name"] as? String}
            guard try retired.userTableNames().isEmpty, names.contains("base_sync_marker"), try retired.execute("SELECT generation FROM base_sync_marker WHERE id=1").first?["generation"] as? String == generation else { throw BaseError.internal("未登记数据库包含未确认的数据，已保留本机文件") }
        }
        let stageURL = rootDirectory.appendingPathComponent(".sync-stage-"+UUID().uuidString,isDirectory:true)
        defer { try? FileManager.default.removeItem(at:stageURL) }
        let staged = try BaseLibraryStore(directory:stageURL)
        defer { staged.close() }
        var keys:[[String:Any]] = []
        if !deleted {
            guard let package = snapshot["package"] as? [String:Any],var manifest = package["manifest"] as? [String:Any],manifest["appID"] as? String == id,
                  let schema = package["schema"] as? [String:Any],let guide = package["guide"] as? [String:Any],let methods = package["methods"] as? [[String:Any]],
                  let data = snapshot["data"] as? [String:Any],let tables = data["tables"] as? [String:[[String:Any]]],let version = snapshot["sourcePackageVersion"] as? Int,version>0,version<9_007_199_254_740_991,
                  let guideVersion = snapshot["guideVersion"] as? Int,guideVersion>0,guideVersion<=version,let incomingKeys = snapshot["keys"] as? [[String:Any]] else { throw BaseError.internal("同步包不完整") }
            manifest["visibility"] = "private"
            for method in methods { _ = try BaseMethodDef(json:method) }
            _ = try staged.createApp(manifest:manifest,schemaObject:schema,guide:guide,methods:methods)
            let tableDefs = try BaseSchemaValidator.parseSchema(schema,validateRelations:true).tables
            var records:[BaseRecordsTable] = []
            for (name,rows) in tables {
                guard let table = tableDefs.first(where:{$0.name == name}) else { throw BaseError.internal("同步数据包含未知表") }
                let allowed = Set(table.fields.map(\.name)).union(["id","_meta"])
                guard rows.allSatisfy({Set($0.keys).isSubset(of:allowed)}) else { throw BaseError.internal("同步数据包含未知字段") }
                records.append(BaseRecordsTable(table:name,rows:rows.map{$0.mapValues{JSONValue(json:$0) ?? .null}}))
            }
            guard Set(tables.keys) == Set(tableDefs.map(\.name)) else { throw BaseError.internal("同步数据缺少表") }
            _ = try staged.applyRecordsExport(BaseRecordsExport(appID:id,packageVersion:1,tables:records))
            try staged.registryExecuteVoid("UPDATE base_apps SET package_version=?1,guide_version=?2 WHERE app_id=?3",parameters:[version,guideVersion,id])
            let sub = try staged.openStore(appID:id); defer { sub.close() }
            try sub.executeVoid("UPDATE base_pkg_state SET package_version=?1 WHERE id=1",parameters:[version])
            keys = incomingKeys
            for key in keys {
                guard key["kind"] as? String == "app",key["app_id"] as? String == id,let keyID = key["key_id"] as? String,!keyID.isEmpty,let material = key["payload_json"] as? String,Data(base64Encoded:material)?.count == 32 else { throw BaseError.internal("同步密钥格式无效") }
                if let existing = try registryExecute("SELECT app_id FROM base_keys WHERE key_id=?1",parameters:[keyID]).first?["app_id"] as? String,existing != id { throw BaseError.internal("密钥标识被其他应用占用") }
            }
        }
        let target = try BaseSubLibraryStore(appID:id,directory:librariesDirectory); target.close()
        try registryExecuteVoid("ATTACH DATABASE ?1 AS base_sync_target",parameters:[target.dbURL.path])
        defer { try? registryExecuteVoid("DETACH DATABASE base_sync_target") }
        if !deleted {
            try registryExecuteVoid("ATTACH DATABASE ?1 AS base_sync_stage",parameters:[staged.librariesDirectory.appendingPathComponent("base_\(id).db").path])
        }
        defer { if !deleted { try? registryExecuteVoid("DETACH DATABASE base_sync_stage") } }
        func checkCurrent() throws {
            if recovering { return }
            if try appExists(id) { guard let expectedFingerprint,try Self.snapshotFingerprint(attachedAccountSnapshot(id)) == expectedFingerprint else { throw BaseError.internal("本机应用已变化，已保留冲突") } }
            else if expectedFingerprint != nil { throw BaseError.internal("本机应用已被删除") }
        }
        try registryExecuteVoid("BEGIN IMMEDIATE")
        do { try checkCurrent();try registryExecuteVoid("ROLLBACK") }catch{try? registryExecuteVoid("ROLLBACK");throw error}
        let generation = UUID().uuidString
        let text = String(decoding:try JSONSerialization.data(withJSONObject:snapshot,options:[.sortedKeys]),as:UTF8.self)
        try registryExecuteVoid("INSERT OR REPLACE INTO base_sync_journal VALUES(?1,?2,?3,?4)",parameters:[id,account,text,generation])
        var committed = false
        do {
            try registryExecuteVoid("BEGIN IMMEDIATE");try checkCurrent()
            for row in try registryExecute("SELECT name FROM base_sync_target.sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'") {
                if let name = row["name"] as? String,!Self.snapshotSystemTables.contains(name) { guard BaseSchemaValidator.isValidName(name) else { throw BaseError.internal("用户表名无效") };try registryExecuteVoid("DROP TABLE base_sync_target.\"\(name)\"") }
            }
            if deleted {
                try registryExecuteVoid("DELETE FROM base_apps WHERE app_id=?1",parameters:[id])
                try registryExecuteVoid("DELETE FROM base_keys WHERE kind='app' AND app_id=?1",parameters:[id])
            }else{
                for row in try registryExecute("SELECT name,sql FROM base_sync_stage.sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'") {
                    guard let name = row["name"] as? String,!Self.snapshotSystemTables.contains(name),let ddl = row["sql"] as? String else { continue }
                    guard BaseSchemaValidator.isValidName(name),let opening = ddl.firstIndex(of:"(") else { throw BaseError.internal("暂存表定义无效") }
                    try registryExecuteVoid("CREATE TABLE base_sync_target.\"\(name)\" "+ddl[opening...])
                    try registryExecuteVoid("INSERT INTO base_sync_target.\"\(name)\" SELECT * FROM base_sync_stage.\"\(name)\"")
                }
                for table in ["base_schema_cache","base_record_seq","base_pkg_state","schema_migrations"] {
                    try registryExecuteVoid("DELETE FROM base_sync_target.\(table)")
                    try registryExecuteVoid("INSERT INTO base_sync_target.\(table) SELECT * FROM base_sync_stage.\(table)")
                }
                try registryExecuteVoid("DELETE FROM base_sync_target.base_idempotency")
                guard let row = try staged.registryExecute("SELECT * FROM base_apps WHERE app_id=?1",parameters:[id]).first else { throw BaseError.internal("暂存注册信息缺失") }
                let columns = row.keys.sorted()
                try registryExecuteVoid("INSERT OR REPLACE INTO base_apps ("+columns.joined(separator:",")+") VALUES ("+columns.indices.map{"?\($0+1)"}.joined(separator:",")+")",parameters:columns.map{row[$0]!})
                try registryExecuteVoid("DELETE FROM base_keys WHERE kind='app' AND app_id=?1",parameters:[id])
                for key in keys { try registryExecuteVoid("INSERT OR REPLACE INTO base_keys VALUES(?1,'app',?2,?3,?4)",parameters:[key["key_id"]!,id,key["payload_json"]!,key["created_at"] ?? BaseTime.isoNow()]) }
            }
            try registryExecuteVoid("DROP TABLE IF EXISTS \"base_pkg_\(id)\"")
            if try !registryExecute("SELECT 1 FROM sqlite_master WHERE name='base_grants' AND type='table'").isEmpty {try registryExecuteVoid("DELETE FROM base_grants WHERE app_id=?1",parameters:[id])}
            try registryExecuteVoid("INSERT OR REPLACE INTO base_sync_owners VALUES(?1,?2)",parameters:[id,account])
            try registryExecuteVoid("DELETE FROM base_sync_deletions WHERE app_id=?1",parameters:[id])
            try registryExecuteVoid("DELETE FROM base_sync_restores WHERE app_id=?1",parameters:[id])
            try registryExecuteVoid("CREATE TABLE IF NOT EXISTS base_sync_target.base_sync_marker(id INTEGER PRIMARY KEY,generation TEXT NOT NULL)")
            try registryExecuteVoid("INSERT OR REPLACE INTO base_sync_target.base_sync_marker VALUES(1,?1)",parameters:[generation])
            try registryExecuteVoid("INSERT OR REPLACE INTO base_sync_applied VALUES(?1,?2)",parameters:[id,generation])
            try registryExecuteVoid("COMMIT");committed = true
            try registryExecuteVoid("DELETE FROM base_sync_journal WHERE app_id=?1",parameters:[id])
        }catch{try? registryExecuteVoid("ROLLBACK");if !committed {try? registryExecuteVoid("DELETE FROM base_sync_journal WHERE app_id=?1",parameters:[id])};throw error}
    }
    public func recordAccountDeletion(_ id:String) throws {
        try registryExecuteVoid("INSERT OR REPLACE INTO base_sync_deletions SELECT app_id,account_id,?2 FROM base_sync_owners WHERE app_id=?1",parameters:[id,Int64(Date().timeIntervalSince1970*1000)])
        try registryExecuteVoid("DELETE FROM base_sync_restores WHERE app_id=?1",parameters:[id])
    }
    public func requestAccountRestore(_ id:String,account:String? = nil) throws {
        if let account { guard try !registryExecute("SELECT 1 FROM base_sync_owners WHERE app_id=?1 AND account_id=?2",parameters:[id,account]).isEmpty else {throw BaseError.internal("应用属于其他账号")} }
        try registryExecuteVoid("INSERT OR REPLACE INTO base_sync_restores SELECT app_id,account_id FROM base_sync_owners WHERE app_id=?1",parameters:[id])
        try registryExecuteVoid("DELETE FROM base_sync_deletions WHERE app_id=?1",parameters:[id])
    }
    public func pendingAccountDeletions(_ account:String) throws -> [String:Int64] {
        Dictionary(uniqueKeysWithValues:try registryExecute("SELECT app_id,deleted_at FROM base_sync_deletions WHERE account_id=?1",parameters:[account]).compactMap{row in guard let id = row["app_id"] as? String,let date = row["deleted_at"] as? Int64 else{return nil};return(id,date)})
    }
    public func isAccountRestore(_ id:String,account:String) throws -> Bool {try !registryExecute("SELECT 1 FROM base_sync_restores WHERE app_id=?1 AND account_id=?2",parameters:[id,account]).isEmpty}
    public func acknowledgeAccountIntent(_ id:String,account:String) throws {
        for table in ["base_sync_deletions","base_sync_restores"] {try registryExecuteVoid("DELETE FROM \(table) WHERE app_id=?1 AND account_id=?2",parameters:[id,account])}
    }
}
