import Foundation

/// User-selected offline recovery. A fresh private branch never restores cloud grants.
public enum BaseRecoveryArchive {
    public static let format = "connor-base-recovery-v1"
    public static func export(library: BaseLibraryStore, appID: String) throws -> Data {
        return try library.withLocalOperation {
        guard let package = try library.packageDictionary(appID: appID) else { throw BaseError.notFound(appID) }
        let records = try library.exportRecords(appID: appID)
        var tables: [String: Any] = [:]
        for table in records.tables { tables[table.table] = table.rows.map { $0.mapValues { $0.jsonObject } } }
        return try JSONSerialization.data(withJSONObject: ["format": format, "appID": appID, "sourcePackageVersion": records.packageVersion, "package": package, "data": ["tables": tables]], options: [.sortedKeys])
        }
    }
    public static func restore(_ data: Data, library: BaseLibraryStore) throws -> String {
        return try library.withLocalOperation {
        guard data.count <= 64_000_000, let archive = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              archive["format"] as? String == format, let id = archive["appID"] as? String,
              let package = archive["package"] as? [String: Any], var manifest = package["manifest"] as? [String: Any],
              manifest["appID"] as? String == id, let schema = package["schema"] as? [String: Any],
              let guide = package["guide"] as? [String: Any], let methods = package["methods"] as? [[String: Any]],
              let payload = archive["data"] as? [String: Any], let rows = payload["tables"] as? [String: [[String: Any]]] else {
            throw BaseError(code: .validationFailed, message: "备份格式无效或超过 64 MB", hint: "选择完整的小程序恢复文件")
        }
        guard try !library.appExists(id) else { throw BaseError(code: .versionMismatch, message: "本机已有同标识小程序", hint: "恢复不会覆盖现有数据") }
        manifest["visibility"] = "private"
        _ = try library.createApp(manifest: manifest, schemaObject: schema, guide: guide, methods: methods)
        do {
            var tables: [BaseRecordsTable] = []
            for (name, records) in rows {
                var values: [[String: JSONValue]] = []
                for record in records {
                    guard case .object(let row) = JSONValue(json: record) else { throw BaseError(code: .validationFailed, message: "记录格式无效", hint: name) }
                    values.append(row)
                }
                tables.append(BaseRecordsTable(table: name, rows: values))
            }
            _ = try library.applyRecordsExport(BaseRecordsExport(appID: id, packageVersion: try library.packageVersion(appID: id), tables: tables))
            return id
        } catch { try? library.deleteApp(appID: id); throw error }
        }
    }
}
