import Foundation
import CryptoKit

/// M3-K3 · 子库行数据确定性导出/空库导入（同步对象 ③ `base_records_<appID>`）。
///
/// 数据写是高频写，字段级 LWW（M3-K5 收口）；行数据随包一体同步，K8 新设备重建的「灌数据」步骤
/// 用本导出在空子库上确定性重建。规范 JSON（sortedKeys）+ SHA-256 指纹：同包同数据必同字节同指纹，
/// 是 golden 三端对账「同方法同结果」的字节锚点。
///
/// 语义：
/// - 导出：子库全部用户表（排除系统表），按表名字典序、行按 id 升序；每行含 id、类型化字段值与 `_meta`（对象）。
/// - 导入：仅空库（目标子库任何用户表有行即拒 VALIDATION_FAILED）+ 包版本门禁（与导出版本一致，否则 VERSION_MISMATCH）
///   + 导出表必须在目标子库存在（schema 一致）；全部插入在单事务内（原子，禁半导入）。
public struct BaseRecordsExport: Sendable, Equatable {
    public let appID: String
    public let packageVersion: Int
    public let tables: [BaseRecordsTable]

    public init(appID: String, packageVersion: Int, tables: [BaseRecordsTable]) {
        self.appID = appID
        self.packageVersion = packageVersion
        self.tables = tables
    }

    /// 载荷字典（appID + packageVersion + tables，不含指纹）。
    public var payload: [String: Any] {
        [
            "appID": appID,
            "packageVersion": packageVersion,
            "tables": tables.map { $0.payload },
        ]
    }

    /// 确定性规范 JSON：键排序（sortedKeys），同数据必同字节。
    public func canonicalData() throws -> Data {
        try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .fragmentsAllowed])
    }

    /// SHA-256 十六进制指纹（行数据对账 / K9 golden 锚点）。
    public func digest() throws -> String {
        let data = try canonicalData()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// 单表行数据（表名 + 行数组；行内字段值 + id + `_meta` 均以 `JSONValue` 存储，Sendable/Equatable）。
public struct BaseRecordsTable: Sendable, Equatable {
    public let table: String
    public let rows: [[String: JSONValue]]

    public init(table: String, rows: [[String: JSONValue]]) {
        self.table = table
        self.rows = rows
    }

    public var payload: [String: Any] {
        [
            "table": table,
            "rows": rows.map { row in
                var d: [String: Any] = [:]
                for (k, v) in row { d[k] = v.jsonObject }
                return d
            },
        ]
    }
}

// MARK: - 行数据导出/导入（BaseLibraryStore 上：包版本取注册库，行数据取子库）

extension BaseLibraryStore {

    /// M3-K3 · 子库行数据确定性导出（含 `_meta`）。包版本 = 注册库 base_apps.package_version（latest，权威版本面）。
    public func exportRecords(appID: String) throws -> BaseRecordsExport {
        guard try appExists(appID) else {
            throw BaseError.notFound("App \(appID) 不存在")
        }
        let version = try packageVersion(appID: appID)
        let store = try openStore(appID: appID)
        defer { store.close() }
        let tables = try store.userTableNames().map { name -> BaseRecordsTable in
            let rows = try store.listRows(in: name).map { row -> [String: JSONValue] in
                var dict: [String: JSONValue] = [:]
                for (k, v) in row { dict[k] = JSONValue(json: v) ?? .null }
                return dict
            }
            return BaseRecordsTable(table: name, rows: rows)
        }
        return BaseRecordsExport(appID: appID, packageVersion: version, tables: tables)
    }

    /// M3-K3 · 空库导入：目标 App 包版本必须与导出版本一致（否则 VERSION_MISMATCH）、
    /// 目标子库必须为空（否则 VALIDATION_FAILED）、导出表必须在目标子库存在（schema 一致）；
    /// 全部插入在单事务内（原子，禁半导入）。返回导入后指纹。
    @discardableResult
    public func applyRecordsExport(_ export: BaseRecordsExport) throws -> String {
        let appID = export.appID
        guard try appExists(appID) else {
            throw BaseError.notFound("App \(appID) 不存在")
        }
        let currentVersion = try packageVersion(appID: appID)
        guard currentVersion == export.packageVersion else {
            throw BaseError(
                code: .versionMismatch,
                message: "数据版本与包版本不符",
                hint: "导出数据为包版本 \(export.packageVersion)，目标 App 当前为 \(currentVersion)；须先恢复对应包版本"
            )
        }
        let store = try openStore(appID: appID)
        defer { store.close() }
        // 空库门禁：任何用户表有行即拒（仅空库导入，K8 重建灌数据场景）。
        let existingTables = try store.userTableNames()
        for name in existingTables {
            guard try store.rowCount(in: name) == 0 else {
                throw BaseError(
                    code: .validationFailed,
                    message: "目标子库非空",
                    hint: "行数据导入仅支持空库（fresh rebuild 场景）；App \(appID) 表 \(name) 已有数据"
                )
            }
        }
        // schema 一致性门禁：导出表必须在目标子库存在。
        for table in export.tables {
            guard try store.tableExists(table.table) else {
                throw BaseError(
                    code: .versionMismatch,
                    message: "目标子库无导出表 \(table.table)",
                    hint: "包版本/迁移与导出数据不一致，须按对应包版本重建子库"
                )
            }
        }
        try store.withTransaction {
            for table in export.tables {
                for row in table.rows {
                    var id = ""
                    var values: [String: JSONValue] = [:]
                    var meta: [String: Any] = [:]
                    for (key, value) in row {
                        switch key {
                        case "id":
                            if case .string(let s) = value { id = s }
                        case "_meta":
                            if case .object(let obj) = value { meta = obj.mapValues { $0.jsonObject } }
                        default:
                            values[key] = value
                        }
                    }
                    guard !id.isEmpty else {
                        throw BaseError(code: .validationFailed, message: "记录缺 id", hint: "导出行必须含 id")
                    }
                    try store.insert(id: id, table: table.table, values: values, meta: meta)
                }
            }
        }
        return try export.digest()
    }
}
