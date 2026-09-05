import Foundation

// MARK: - 字段类型

/// Connor Base 字段类型（v0.5 收口，M0 契约冻结，7 种）。
/// 以 `base.sdk.v1.json` / `app-package.schema.json` 的 fieldDef.type enum 为准。
public enum BaseFieldType: String, Codable, CaseIterable, Sendable {
    case text
    case number
    case boolean
    case date
    case `enum`
    case relation
    case asset

    public static let allRawValues: [String] = BaseFieldType.allCases.map { $0.rawValue }

    public init?(raw: String) {
        self.init(rawValue: raw)
    }
}

// MARK: - 字段定义

/// relation 字段的跨表 lookup 目标。
public struct BaseRelationTarget: Codable, Equatable, Sendable {
    public var table: String
    public var on: String

    public init(table: String, on: String) {
        self.table = table
        self.on = on
    }
}

/// 单个字段定义。
public struct BaseFieldDef: Codable, Equatable, Sendable {
    public var name: String
    public var type: String
    public var required: Bool
    public var unique: Bool
    public var min: Double?
    public var max: Double?
    public var pattern: String?
    public var enumValues: [String]?
    public var defaultValue: JSONValue?
    public var relation: BaseRelationTarget?

    public init(
        name: String,
        type: String,
        required: Bool = false,
        unique: Bool = false,
        min: Double? = nil,
        max: Double? = nil,
        pattern: String? = nil,
        enumValues: [String]? = nil,
        defaultValue: JSONValue? = nil,
        relation: BaseRelationTarget? = nil
    ) {
        self.name = name
        self.type = type
        self.required = required
        self.unique = unique
        self.min = min
        self.max = max
        self.pattern = pattern
        self.enumValues = enumValues
        self.defaultValue = defaultValue
        self.relation = relation
    }
}

// MARK: - 表定义

public struct BaseTableDef: Codable, Equatable, Sendable {
    public var name: String
    public var description: String?
    public var fields: [BaseFieldDef]

    public init(name: String, description: String? = nil, fields: [BaseFieldDef]) {
        self.name = name
        self.description = description
        self.fields = fields
    }
}

// MARK: - App Schema

public struct BaseAppSchema: Codable, Equatable, Sendable {
    public var tables: [BaseTableDef]

    public init(tables: [BaseTableDef]) {
        self.tables = tables
    }

    public func table(named name: String) -> BaseTableDef? {
        tables.first { $0.name == name }
    }

    public func field(_ fieldName: String, in tableName: String) -> BaseFieldDef? {
        table(named: tableName)?.fields.first { $0.name == fieldName }
    }
}

// MARK: - 校验器

public enum BaseSchemaValidator {

    public enum Reason: Equatable, Sendable {
        case invalidTableName(String)
        case fieldMissingType(String)
        case invalidFieldType(String)
        case duplicateField(String)
        case invalidFieldName(String)
        case relationTableNotFound(String, String)
        case relationFieldNotFound(String, String, String)
        case enumNeedsValues(String)
        case invalidRange(String)

        /// 对应用户可读 message（与 golden fixture 逐字对齐）。
        public var message: String {
            switch self {
            case .invalidTableName:
                return "表名不合法"
            case .fieldMissingType:
                return "字段缺少类型"
            case .invalidFieldType:
                return "字段类型不合法"
            case .duplicateField:
                return "字段名重复"
            case .invalidFieldName:
                return "字段名不合法"
            case .relationTableNotFound:
                return "关系字段引用了不存在的表"
            case .relationFieldNotFound:
                return "关系字段引用了不存在的目标字段"
            case .enumNeedsValues:
                return "enum 字段缺少允许值"
            case .invalidRange:
                return "字段范围约束不合法"
            }
        }

        /// 用户可读 hint。
        public var hint: String {
            switch self {
            case .invalidTableName:
                return "表名须匹配 ^[a-z][a-z0-9_]{0,47}$"
            case .fieldMissingType:
                return "字段定义必须包含 type"
            case .invalidFieldType:
                return "字段类型只允许 text/number/boolean/date/enum/relation/asset"
            case .duplicateField:
                return "同一表内字段名须唯一"
            case .invalidFieldName:
                return "字段名须匹配 ^[a-z][a-z0-9_]{0,47}$"
            case .relationTableNotFound(let table, _):
                return "本子库不存在表 \(table)；relation 不允许跨子库引用"
            case .relationFieldNotFound(_, let table, _):
                return "目标表 \(table) 不含被引用字段"
            case .enumNeedsValues:
                return "enum 字段必须声明非空 enum 数组"
            case .invalidRange:
                return "range.min 须不大于 range.max"
            }
        }
    }

    public enum ValidationError: Error, Equatable, Sendable {
        case invalid(Reason)

        public var reason: Reason {
            switch self {
            case .invalid(let r):
                return r
            }
        }
    }

    // MARK: 名称

    /// 表名 / 字段名：^[a-z][a-z0-9_]{0,47}$
    public static func isValidName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 48 else { return false }
        let scalars = Array(name.unicodeScalars)
        guard let first = scalars.first,
              first.value >= 0x61, first.value <= 0x7A else { return false }
        for scalar in scalars {
            let isLower = scalar.value >= 0x61 && scalar.value <= 0x7A
            let isDigit = scalar.value >= 0x30 && scalar.value <= 0x39
            let isUnderscore = scalar == Unicode.Scalar(0x5F) // "_"
            guard isLower || isDigit || isUnderscore else { return false }
        }
        return true
    }

    public static func isValidAppID(_ appID: String) -> Bool {
        guard !appID.isEmpty, appID.count <= 48 else { return false }
        for scalar in appID.unicodeScalars {
            let isLower = scalar.value >= 0x61 && scalar.value <= 0x7A
            let isDigit = scalar.value >= 0x30 && scalar.value <= 0x39
            let isDash = scalar == Unicode.Scalar(0x2D) // "-"
            let isUnderscore = scalar == Unicode.Scalar(0x5F) // "_"
            guard isLower || isDigit || isDash || isUnderscore else { return false }
        }
        return true
    }

    // MARK: 字段

    /// 从 JSON 字典解析单个字段定义（缺 type 即抛 fieldMissingType）。
    public static func parseField(_ object: [String: Any]) throws -> BaseFieldDef {
        guard let name = object["name"] as? String else {
            throw ValidationError.invalid(.invalidFieldName(nameOf(object)))
        }
        guard let type = object["type"] as? String else {
            throw ValidationError.invalid(.fieldMissingType(name))
        }
        guard let _ = BaseFieldType(raw: type) else {
            throw ValidationError.invalid(.invalidFieldType(name))
        }
        guard isValidName(name) else {
            throw ValidationError.invalid(.invalidFieldName(name))
        }

        let rangeObj = object["range"] as? [String: Any]
        let min = (rangeObj?["min"] as? NSNumber)?.doubleValue
        let max = (rangeObj?["max"] as? NSNumber)?.doubleValue
        if let min, let max, min > max {
            throw ValidationError.invalid(.invalidRange(name))
        }

        var relation: BaseRelationTarget? = nil
        if let rel = object["relation"] as? [String: Any] {
            relation = BaseRelationTarget(
                table: rel["table"] as? String ?? "",
                on: rel["on"] as? String ?? ""
            )
        }

        return BaseFieldDef(
            name: name,
            type: type,
            required: (object["required"] as? Bool) ?? false,
            unique: (object["unique"] as? Bool) ?? false,
            min: min,
            max: max,
            pattern: object["pattern"] as? String,
            enumValues: object["enum"] as? [String],
            defaultValue: object["default"].map { JSONValue(json: $0) ?? .null },
            relation: relation
        )
    }

    /// 解析并校验一张表（含跨子库边界校验：relation 目标表必须在本 schema 内）。
    public static func parseTable(_ object: [String: Any], schema: BaseAppSchema? = nil) throws -> BaseTableDef {
        guard let name = object["name"] as? String else {
            throw ValidationError.invalid(.invalidTableName(""))
        }
        guard isValidName(name) else {
            throw ValidationError.invalid(.invalidTableName(name))
        }
        guard let rawFields = object["fields"] as? [[String: Any]] else {
            throw ValidationError.invalid(.fieldMissingType(""))
        }

        var seen = Set<String>()
        var fields: [BaseFieldDef] = []
        for raw in rawFields {
            let field = try parseField(raw)
            if seen.contains(field.name) {
                throw ValidationError.invalid(.duplicateField(field.name))
            }
            seen.insert(field.name)

            // relation：目标表必须在同一 schema 内（link 不跨子库校验）。
            // schema 为 nil（单表创建场景）时不在此校验，由上层按已知表集合校验。
            if field.type == "relation", let rel = field.relation, let tables = schema?.tables {
                guard !tables.isEmpty else {
                    throw ValidationError.invalid(.relationTableNotFound(name, rel.table))
                }
                guard let target = schema?.table(named: rel.table) else {
                    throw ValidationError.invalid(.relationTableNotFound(name, rel.table))
                }
                guard target.fields.contains(where: { $0.name == rel.on }) || rel.on == "id" else {
                    throw ValidationError.invalid(.relationFieldNotFound(name, rel.table, rel.on))
                }
            }
            fields.append(field)
        }

        return BaseTableDef(name: name, description: object["description"] as? String, fields: fields)
    }

    /// 解析并校验一个完整 App schema（多表）。
    /// 两遍：先解析全部表，再统一校验 relation 引用（目标表必须在同一子库）。
    public static func parseSchema(_ object: [String: Any], validateRelations: Bool = true) throws -> BaseAppSchema {
        guard let rawTables = object["tables"] as? [[String: Any]] else {
            throw ValidationError.invalid(.invalidTableName(""))
        }
        var tables: [BaseTableDef] = []
        var seen = Set<String>()
        for raw in rawTables {
            let table = try parseTable(raw)
            if seen.contains(table.name) {
                throw ValidationError.invalid(.duplicateField(table.name))
            }
            seen.insert(table.name)
            tables.append(table)
        }
        let schema = BaseAppSchema(tables: tables)
        // 第二遍：relation 目标表与目标字段必须在同一 schema 内（结构期不变量；
        // 读/写执行期传 validateRelations:false 不复校验，允许查询所需的局部 schema 快照）。
        if validateRelations {
            for table in tables {
                for field in table.fields where field.type == "relation" {
                    guard let rel = field.relation else { continue }
                    guard let target = schema.table(named: rel.table) else {
                        throw ValidationError.invalid(.relationTableNotFound(table.name, rel.table))
                    }
                    guard target.fields.contains(where: { $0.name == rel.on }) || rel.on == "id" else {
                        throw ValidationError.invalid(.relationFieldNotFound(table.name, rel.table, rel.on))
                    }
                }
            }
        }
        return schema
    }

    private static func nameOf(_ object: [String: Any]) -> String {
        (object["name"] as? String) ?? ""
    }
}
