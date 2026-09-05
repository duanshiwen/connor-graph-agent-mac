import Foundation

/// M1-K4：结构化查询编译器——filter 树 → 参数化 SQL。
///
/// 契约约束（base.sdk.v1.json query）：
/// - filter = {and:[filter...]} / {or:[filter...]} / {field, op, value}
/// - 操作符按字段类型收口；永不字符串拼接值；字段名/表名白名单校验后拼接。
public struct BaseQueryCompiler {

    public let table: String
    public let fields: [String: String] // 字段名 -> 字段类型（来自 store 类型缓存）

    public static let maxRowsPerQuery = 5000

    /// 契约定义的按类型收口操作符（base.sdk.v1.json query.filter.operatorsByType）。
    public static let allowedOperators: [String: [String]] = [
        "text": ["eq", "contains", "startsWith", "in"],
        "number": ["eq", "gt", "gte", "lt", "lte", "between"],
        "date": ["on", "before", "after", "range"],
        "enum": ["in"],
        "relation": ["has", "lookup"],
        "boolean": ["eq", "in"],
        "asset": ["eq", "in"]
    ]

    public struct Compiled {
        public let sql: String
        public let parameters: [Any]
        public init(sql: String, parameters: [Any]) {
            self.sql = sql
            self.parameters = parameters
        }
    }

    public init(table: String, fields: [String: String]) {
        self.table = table
        self.fields = fields
    }

    // MARK: SELECT

    public func compileSelect(
        filter: [String: Any]?,
        sort: [[String: Any]]?,
        page: [String: Any]?
    ) throws -> Compiled {
        var params: [Any] = []
        var sql = "SELECT * FROM \"\(table)\""
        if let filter {
            sql += " WHERE \(try compileFilter(filter, params: &params))"
        }
        if let sort, !sort.isEmpty {
            var order: [String] = []
            for item in sort {
                guard let field = item["field"] as? String else {
                    throw BaseError(code: .validationFailed, message: "排序字段缺失", hint: "sort 项须含 field")
                }
                _ = try resolveField(field)
                let direction = (item["direction"] as? String)?.lowercased() == "desc" ? "DESC" : "ASC"
                order.append("\"\(field)\" \(direction)")
            }
            sql += " ORDER BY \(order.joined(separator: ", "))"
        }
        if let page {
            let limit = (page["limit"] as? Int) ?? 100
            let offset = (page["offset"] as? Int) ?? 0
            guard limit >= 0, limit <= Self.maxRowsPerQuery else {
                throw BaseError(code: .quotaExceeded,
                                message: "查询行数超限",
                                hint: "limit 不得超过 \(Self.maxRowsPerQuery)")
            }
            if limit >= 0 {
                sql += " LIMIT ?"
                params.append(limit)
            }
            if offset > 0 {
                sql += " OFFSET ?"
                params.append(offset)
            }
        }
        return Compiled(sql: sql, parameters: params)
    }

    // MARK: AGGREGATE

    public func compileAggregate(
        aggregations: [[String: Any]],
        filter: [String: Any]?,
        groupBy: [String]?,
        timeSeries: [String: Any]?
    ) throws -> Compiled {
        guard !aggregations.isEmpty else {
            throw BaseError(code: .validationFailed, message: "聚合缺失", hint: "aggregations 至少一项")
        }
        var params: [Any] = []
        var selects: [String] = []
        var groupCols: [String] = []

        if let ts = timeSeries {
            let bucket = try timeBucketExpression(ts)
            selects.append("\(bucket) AS \"bucket\"")
            groupCols.append(bucket)
        }

        if let groupBy, !groupBy.isEmpty {
            for field in groupBy {
                _ = try resolveField(field)
                selects.append("\"\(field)\"")
                groupCols.append("\"\(field)\"")
            }
        }

        for agg in aggregations {
            guard let op = agg["op"] as? String else {
                throw BaseError(code: .validationFailed, message: "聚合 op 缺失", hint: "op 须为 sum/avg/count/min/max")
            }
            guard ["sum", "avg", "count", "min", "max"].contains(op) else {
                throw BaseError(code: .validationFailed, message: "聚合 op 不合法", hint: "op 须为 sum/avg/count/min/max")
            }
            let rawAlias = agg["alias"] as? String
            let alias = validAlias(rawAlias) ?? "\(op)_\(agg["field"] ?? "")"
            if op == "count" {
                if let field = agg["field"] as? String {
                    _ = try resolveField(field)
                    selects.append("COUNT(\"\(field)\") AS \"\(alias)\"")
                } else {
                    selects.append("COUNT(*) AS \"\(alias)\"")
                }
            } else {
                guard let field = agg["field"] as? String else {
                    throw BaseError(code: .validationFailed, message: "聚合字段缺失", hint: "\(op) 聚合须指定 field")
                }
                let type = try resolveField(field)
                guard type == "number" || type == "date" else {
                    throw BaseError(code: .validationFailed,
                                    message: "聚合字段类型不合法",
                                    hint: "sum/avg/min/max 仅支持 number/date 字段")
                }
                selects.append("\(op.uppercased())(\"\(field)\") AS \"\(alias)\"")
            }
        }

        var sql = "SELECT \(selects.joined(separator: ", ")) FROM \"\(table)\""
        var whereClauses: [String] = []
        if let filter {
            whereClauses.append(try compileFilter(filter, params: &params))
        }
        if let ts = timeSeries, let field = ts["field"] as? String {
            _ = try resolveField(field)
            if let start = ts["start"] as? String {
                whereClauses.append("\"\(field)\" >= ?")
                params.append(start)
            }
            if let end = ts["end"] as? String {
                whereClauses.append("\"\(field)\" < ?")
                params.append(end)
            }
        }
        if !whereClauses.isEmpty {
            sql += " WHERE \(whereClauses.joined(separator: " AND "))"
        }
        if !groupCols.isEmpty {
            sql += " GROUP BY \(groupCols.joined(separator: ", "))"
        }
        return Compiled(sql: sql, parameters: params)
    }

    // MARK: filter 递归

    private func compileFilter(_ node: [String: Any], params: inout [Any]) throws -> String {
        if let and = node["and"] as? [[String: Any]] {
            guard !and.isEmpty else {
                throw BaseError(code: .validationFailed, message: "and 为空", hint: "and 至少一项")
            }
            let subs = try and.map { try compileFilter($0, params: &params) }
            return "(\(subs.joined(separator: " AND ")))"
        }
        if let or = node["or"] as? [[String: Any]] {
            guard !or.isEmpty else {
                throw BaseError(code: .validationFailed, message: "or 为空", hint: "or 至少一项")
            }
            let subs = try or.map { try compileFilter($0, params: &params) }
            return "(\(subs.joined(separator: " OR ")))"
        }
        guard let field = node["field"] as? String,
              let op = node["op"] as? String else {
            throw BaseError(code: .validationFailed,
                            message: "filter 结构非法",
                            hint: "filter 须为 {and:[...]}/{or:[...]}/{field,op,value}")
        }
        guard node.keys.contains("value") else {
            throw BaseError(code: .validationFailed, message: "filter 缺 value", hint: "{field,op,value} 三要素缺一不可")
        }
        let value = node["value"] as Any
        return try compileCondition(field: field, op: op, value: value, params: &params)
    }

    private func compileCondition(field: String, op: String, value: Any, params: inout [Any]) throws -> String {
        let type = try resolveField(field)
        guard let allowed = Self.allowedOperators[type], allowed.contains(op) else {
            throw BaseError(code: .validationFailed,
                            message: "操作符与字段类型不匹配",
                            hint: "\(type) 字段 \(field) 允许的操作符：\(Self.allowedOperators[type]?.joined(separator: "/") ?? "")")
        }
        let quoted = "\"\(field)\""
        switch op {
        case "eq":
            params.append(value)
            return "\(quoted) = ?"
        case "gt":
            params.append(value)
            return "\(quoted) > ?"
        case "gte":
            params.append(value)
            return "\(quoted) >= ?"
        case "lt":
            params.append(value)
            return "\(quoted) < ?"
        case "lte":
            params.append(value)
            return "\(quoted) <= ?"
        case "on":
            params.append(value)
            return "\(quoted) = ?"
        case "before":
            params.append(value)
            return "\(quoted) < ?"
        case "after":
            params.append(value)
            return "\(quoted) > ?"
        case "contains":
            params.append("%\(Self.escapeLike(stringValue(value)))")
            return "\(quoted) LIKE ? ESCAPE '\\'"
        case "startsWith":
            params.append("\(Self.escapeLike(stringValue(value)))%")
            return "\(quoted) LIKE ? ESCAPE '\\'"
        case "has":
            params.append(value)
            return "\(quoted) = ?"
        case "in":
            let arr = (value as? [Any]) ?? [value]
            guard !arr.isEmpty else {
                throw BaseError(code: .validationFailed, message: "in 值列表为空", hint: "in 至少一个值")
            }
            let placeholders = arr.map { item -> String in
                params.append(item)
                return "?"
            }.joined(separator: ", ")
            return "\(quoted) IN (\(placeholders))"
        case "between", "range":
            let arr = (value as? [Any]) ?? []
            guard arr.count == 2 else {
                throw BaseError(code: .validationFailed, message: "between/range 需两个值", hint: "value 须为 [min, max]")
            }
            params.append(arr[0])
            params.append(arr[1])
            return "\(quoted) BETWEEN ? AND ?"
        case "lookup":
            // lookup 在 select 后处理展开，不产生 SQL 条件；此处过滤关系目标不存在即返回空。
            params.append(value)
            return "\(quoted) = ?"
        default:
            throw BaseError(code: .validationFailed, message: "操作符不合法", hint: "不支持的 op：\(op)")
        }
    }

    // MARK: 辅助

    private func resolveField(_ field: String) throws -> String {
        try BaseNameResolver.resolveField(field, in: table, fields: fields)
    }

    private func timeBucketExpression(_ ts: [String: Any]) throws -> String {
        guard let field = ts["field"] as? String else {
            throw BaseError(code: .validationFailed, message: "timeSeries 缺 field", hint: "timeSeries 须含 field")
        }
        _ = try resolveField(field)
        let granularity = (ts["granularity"] as? String) ?? "month"
        switch granularity {
        case "day":
            return "substr(\"\(field)\", 1, 10)"
        case "week":
            return "strftime('%Y-W%W', \"\(field)\")"
        case "month":
            return "substr(\"\(field)\", 1, 7)"
        default:
            throw BaseError(code: .validationFailed, message: "timeSeries 粒度不合法", hint: "granularity 须为 day/week/month")
        }
    }

    private func validAlias(_ alias: String?) -> String? {
        guard let alias, !alias.isEmpty, BaseSchemaValidator.isValidName(alias) else { return nil }
        return alias
    }

    private func stringValue(_ value: Any) -> String {
        (value as? String) ?? String(describing: value)
    }

    /// LIKE 通配符转义（ESCAPE '\\'）。
    public static func escapeLike(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }
}
