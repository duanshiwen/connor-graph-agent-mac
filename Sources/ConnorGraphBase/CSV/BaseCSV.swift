import Foundation

/// M1-K7：CSV 导入/导出（外部文件通道，与跨库导入无关；v0.12 里程碑 M1）。
///
/// - `importCSV`：列名必须精确匹配 schema 字段（未知列拒绝）；逐行走 mutator
///   （同一条校验/约束/审计路径）；整批单事务原子，失败带行号回滚。
/// - `exportCSV`：查询结果序列化（值引号转义，RFC 4180 风格）。
public enum BaseCSV {

    public struct ImportResult: Encodable, Equatable {
        public let imported: Int
        public let dryRun: Bool
        public let errors: [ImportError]
    }

    public struct ImportError: Encodable, Equatable {
        public let row: Int
        public let message: String
    }

    // MARK: 导入

    public static func importCSV(
        csv: String,
        table: String,
        schema: BaseAppSchema,
        store: BaseSubLibraryStore,
        dryRun: Bool = false
    ) throws -> ImportResult {
        guard let tableDef = schema.table(named: table) else {
            throw BaseError(code: .notFound, message: "表不存在", hint: "schema 无表 \(table)")
        }
        let parsed = try parseCSV(csv)
        guard let header = parsed.first, parsed.count > 1 else {
            return ImportResult(imported: 0, dryRun: dryRun, errors: [])
        }
        let fieldNames = tableDef.fields.map { $0.name }
        let fieldTypes = Dictionary(uniqueKeysWithValues: tableDef.fields.map { ($0.name, $0.type) })
        // 列名精确匹配 schema 字段（未知列拒绝）。
        for column in header {
            guard fieldNames.contains(column) else {
                throw BaseError(code: .validationFailed,
                                message: "CSV 列名与 schema 不匹配",
                                hint: "未知列 \(column)；允许列：\(fieldNames.joined(separator: "/"))")
            }
        }

        let mutator = BaseRecordMutator(store: store, schema: schema)
        var errors: [ImportError] = []
        var imported = 0
        var ops: [[String: Any]] = []

        for (index, row) in parsed.dropFirst().enumerated() {
            let rowNumber = index + 2 // 表头为第 1 行
            guard row.count == header.count else {
                errors.append(ImportError(row: rowNumber, message: "列数不匹配：期望 \(header.count)，实际 \(row.count)"))
                continue
            }
            var record: [String: Any] = [:]
            for (i, column) in header.enumerated() {
                let raw = row[i]
                if raw.isEmpty { continue } // 空串视为未设置
                record[column] = csvValue(raw, fieldType: fieldTypes[column])
            }
            ops.append(["op": "insert", "record": record])
        }

        guard !ops.isEmpty else {
            return ImportResult(imported: 0, dryRun: dryRun, errors: errors)
        }
        if dryRun {
            // dryRun：逐行校验不写入。
            for (index, op) in ops.enumerated() {
                do {
                    _ = try mutator.mutate(appID: "", table: table, ops: [op], dryRun: true)
                    imported += 1
                } catch let e as BaseError {
                    errors.append(ImportError(row: index + 2, message: e.message))
                }
            }
        } else {
            do {
                let result = try mutator.mutate(appID: "", table: table, ops: ops)
                imported = (result["applied"] as? Int) ?? ops.count
            } catch let e as BaseError {
                throw BaseError(code: BaseErrorCode(rawValue: e.code) ?? .validationFailed,
                                message: "CSV 导入失败",
                                hint: e.message)
            }
        }
        return ImportResult(imported: imported, dryRun: dryRun, errors: errors)
    }

    /// CSV 值按目标字段类型还原（CSV 是纯文本，类型由 schema 决定；
    /// 布尔列接受 true/false/1/0/yes/no，数字列转 Double，其余一律按字符串）。
    private static func csvValue(_ raw: String, fieldType: String?) -> Any {
        switch fieldType {
        case "number":
            return Double(raw) ?? raw // 解析失败留给 mutator 报类型错
        case "boolean":
            switch raw.lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: return raw
            }
        default:
            // text/enum/date/relation/asset 一律按字符串
            return raw
        }
    }

    // MARK: 导出

    public static func exportCSV(records: [[String: Any]], fieldOrder: [String]) -> String {
        var lines: [String] = []
        lines.append(fieldOrder.map { escapeField($0) }.joined(separator: ","))
        for record in records {
            let cells = fieldOrder.map { field -> String in
                guard let value = record[field] else { return "" }
                return escapeField(cellValue(value))
            }
            lines.append(cells.joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    private static func cellValue(_ value: Any) -> String {
        switch value {
        case let s as String:
            return s
        case let b as Bool:
            return b ? "true" : "false"
        case let n as Double:
            return n == n.rounded() ? String(Int(n)) : String(n)
        case let n as Int:
            return String(n)
        case let n as Int64:
            return String(n)
        case is NSNull:
            return ""
        default:
            return String(describing: value)
        }
    }

    private static func escapeField(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    // MARK: 解析（RFC 4180：双引号转义、带引号字段可含逗号/换行）

    public static func parseCSV(_ text: String) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        // 按 Unicode 标量迭代：Swift 的 Character 按扩展字素簇切分，CRLF（U+000D U+000A）
        // 是单个字素簇（Unicode TR#29 GB3），会把 \r\n 当成一个字符而漏掉换行。
        let scalars = Array(text.unicodeScalars)
        var i = 0
        while i < scalars.count {
            let ch = scalars[i]
            if inQuotes {
                if ch == "\"" {
                    if i + 1 < scalars.count, scalars[i + 1] == "\"" {
                        field.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(Character(ch))
                }
            } else {
                switch ch {
                case "\"":
                    inQuotes = true
                case ",":
                    row.append(field)
                    field = ""
                case "\n":
                    row.append(field)
                    rows.append(row)
                    row = []
                    field = ""
                case "\r":
                    break // 与 \n 合并（CRLF）
                default:
                    field.append(Character(ch))
                }
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        guard !rows.isEmpty else { return [] }
        // 丢弃空行
        return rows.filter { !($0.count == 1 && $0[0].isEmpty) }
    }
}
