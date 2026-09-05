import Foundation

/// M1-K4：查询执行器——绑定子库 store，运行编译后的参数化 SQL，做 lookup 展开与类型还原。
public struct BaseQueryExecutor {

    public let store: BaseSubLibraryStore
    public let table: String
    public let schema: BaseAppSchema

    public init(store: BaseSubLibraryStore, table: String, schema: BaseAppSchema) {
        self.store = store
        self.table = table
        self.schema = schema
    }

    // MARK: SELECT

    public func select(
        filter: [String: Any]? = nil,
        sort: [[String: Any]]? = nil,
        page: [String: Any]? = nil,
        lookup: [String]? = nil
    ) throws -> [[String: Any]] {
        guard try store.tableExists(table) else {
            throw BaseError(code: .notFound, message: "表不存在", hint: "子库无表 \(table)")
        }
        let compiler = BaseQueryCompiler(table: table, fields: store.fields(of: table))
        let compiled = try compiler.compileSelect(filter: filter, sort: sort, page: page)
        let rows = try store.execute(compiled.sql, parameters: compiled.parameters)
        var records: [[String: Any]] = try rows.map { try decode($0) }
        if let lookup, !lookup.isEmpty {
            records = try expandLookup(records, fields: lookup)
        }
        return records
    }

    // MARK: AGGREGATE

    public func aggregate(
        aggregations: [[String: Any]],
        filter: [String: Any]? = nil,
        groupBy: [String]? = nil,
        timeSeries: [String: Any]? = nil
    ) throws -> [[String: JSONValue]] {
        guard try store.tableExists(table) else {
            throw BaseError(code: .notFound, message: "表不存在", hint: "子库无表 \(table)")
        }
        let compiler = BaseQueryCompiler(table: table, fields: store.fields(of: table))
        let compiled = try compiler.compileAggregate(
            aggregations: aggregations, filter: filter, groupBy: groupBy, timeSeries: timeSeries
        )
        let rows = try store.execute(compiled.sql, parameters: compiled.parameters)
        var out: [[String: JSONValue]] = []
        for row in rows {
            var item: [String: JSONValue] = [:]
            for (key, value) in row {
                switch value {
                case let s as String:
                    item[key] = .string(s)
                case let n as Double:
                    item[key] = .number(n)
                case let n as Int64:
                    item[key] = .number(Double(n))
                case let n as Int:
                    item[key] = .number(Double(n))
                default:
                    item[key] = .null
                }
            }
            out.append(item)
        }
        return out
    }

    // MARK: 解码 / lookup

    private func decode(_ row: [String: Any]) throws -> [String: Any] {
        guard let id = row["id"] as? String else {
            throw BaseError(code: .internal, message: "记录缺 id", hint: "查询结果缺少主键")
        }
        var record: [String: Any] = ["id": id]
        for (key, value) in row where key != "id" && key != "_meta" {
            let type = store.columnType(of: key, in: table)
            record[key] = jsonValue(value, type: type).jsonObject
        }
        if let metaRaw = row["_meta"] as? String,
           let meta = try? JSONSerialization.jsonObject(with: Data(metaRaw.utf8)) as? [String: Any] {
            record["_meta"] = meta
        }
        return record
    }

    private func jsonValue(_ value: Any, type: String?) -> JSONValue {
        switch value {
        case let s as String:
            return .string(s)
        case let n as Int64:
            return type == "boolean" ? .bool(n != 0) : .number(Double(n))
        case let n as Int:
            return type == "boolean" ? .bool(n != 0) : .number(Double(n))
        case let n as Double:
            return .number(n)
        case is NSNull:
            return .null
        default:
            return .null
        }
    }

    /// lookup：relation 字段展开为 {id, 目标表值}。
    private func expandLookup(_ records: [[String: Any]], fields: [String]) throws -> [[String: Any]] {
        guard let tableDef = schema.table(named: table) else { return records }
        var updated = records
        for (index, record) in records.enumerated() {
            var next = record
            for fieldName in fields {
                guard let field = tableDef.fields.first(where: { $0.name == fieldName }),
                      field.type == "relation",
                      let rel = field.relation else { continue }
                guard let raw = record[fieldName] as? String, !raw.isEmpty else { continue }
                let targetTable = rel.table
                guard let targetDef = schema.table(named: targetTable) else { continue }
                let rows = try store.execute(
                    "SELECT * FROM \"\(targetTable)\" WHERE id = ?1", parameters: [raw]
                )
                if let targetRow = rows.first {
                    var obj: [String: Any] = ["id": raw]
                    for (k, v) in targetRow where k != "id" && k != "_meta" {
                        let t = store.columnType(of: k, in: targetTable)
                        obj[k] = jsonValue(v, type: t).jsonObject
                    }
                    next[fieldName] = obj
                }
            }
            updated[index] = next
        }
        return updated
    }
}
