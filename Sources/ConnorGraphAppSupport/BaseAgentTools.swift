import Foundation
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphBase

/// Connor Base 工具运行时（M1-M3 薄封装）。
///
/// 13 个 M1 工具（施工图 M1-M3/D4，与契约 base.sdk.v1.json 的 inputSchema 两端一致）：
/// guide / app.create / app.delete / app.list / app.get /
/// table.create / table.alter / record.get / query.select / query.aggregate /
/// record.mutate / import.csv / export.csv
///
/// 每个操作返回统一返回信封（§3.3）：成功 data 为内核结果，失败携带错误码 taxonomy。
public actor BaseToolRuntime {

    private let library: BaseLibraryStore

    /// 产品入口：根目录为 artifactsDirectory/base。
    public init(storagePaths: AppStoragePaths) throws {
        let root = storagePaths.artifactsDirectory.appendingPathComponent("base", isDirectory: true)
        self.library = try BaseLibraryStore(directory: root)
    }

    /// 测试入口：指定根目录。
    public init(directory: URL) throws {
        self.library = try BaseLibraryStore(directory: directory)
    }

    public func close() {
        library.close()
    }

    // MARK: - 审计（M1-M7）

    /// 写入一条审计记录到目标 App 子库（best-effort：子库不存在或失败即忽略；端侧、不同步）。
    public func recordAudit(appID: String, operation: String, detail: String) {
        library.recordAudit(appID: appID, operation: operation, detail: detail)
    }

    /// 读取指定 App 子库的审计记录（只读、端侧；base.audit.read 读取面在 M2 开放）。
    public func readAudit(appID: String) -> [[String: String]] {
        library.readAudit(appID: appID).map { row in
            [
                "seq": row["seq"] .map { String(describing: $0) } ?? "",
                "operation": row["operation"] as? String ?? "",
                "detail": row["detail"] as? String ?? "",
                "created_at": row["created_at"] as? String ?? ""
            ]
        }
    }

    // MARK: - 契约

    /// base.guide：返回平台契约全文或指定章节。
    public func guideEnvelope(section: String?) -> BaseEnvelope {
        do {
            if let section, !section.isEmpty {
                let contract = try SDKContractLoader.load(.sdk)
                guard let value = contract[section] else {
                    throw BaseError(code: .notFound, message: "契约章节不存在",
                                    hint: "可用章节：\(contract.keys.sorted().joined(separator: "/"))")
                }
                return .success(data: ["section": section, "content": value])
            }
            let text = try SDKContractLoader.guideContractText()
            return .success(data: ["content": text])
        } catch let error as BaseError {
            return .failure(error)
        } catch {
            return .failure(BaseError(code: .internal, message: "契约读取失败", hint: "\(error)"))
        }
    }

    // MARK: - App 生命周期

    public func createAppEnvelope(manifest: [String: Any], schema: [String: Any], guide: [String: Any], methods: [[String: Any]]) -> BaseEnvelope {
        do {
            let card = try library.createApp(manifest: manifest, schemaObject: schema, guide: guide, methods: methods)
            return .success(data: card)
        } catch let error as BaseError {
            return .failure(error)
        } catch {
            return .failure(BaseError(code: .internal, message: "创建 App 失败", hint: "\(error)"))
        }
    }

    public func deleteAppEnvelope(appID: String) -> BaseEnvelope {
        do {
            try library.deleteApp(appID: appID)
            return .success(data: ["deleted": appID])
        } catch let error as BaseError {
            return .failure(error)
        } catch {
            return .failure(BaseError(code: .internal, message: "删除 App 失败", hint: "\(error)"))
        }
    }

    public func listAppsEnvelope(scope: String?, query: String?) -> BaseEnvelope {
        do {
            let apps = try library.listApps(scope: scope, query: query)
            return .success(data: ["apps": apps, "count": apps.count])
        } catch let error as BaseError {
            return .failure(error)
        } catch {
            return .failure(BaseError(code: .internal, message: "列出 App 失败", hint: "\(error)"))
        }
    }

    public func appCardEnvelope(appID: String, includeGuide: Bool) -> BaseEnvelope {
        do {
            guard let card = try library.appCard(appID: appID, includeGuide: includeGuide) else {
                throw BaseError(code: .notFound, message: "App 不存在", hint: "appID \(appID)")
            }
            return .success(data: card)
        } catch let error as BaseError {
            return .failure(error)
        } catch {
            return .failure(BaseError(code: .internal, message: "读取 App Card 失败", hint: "\(error)"))
        }
    }

    // MARK: - 结构

    public func tableCreateEnvelope(appID: String, table: [String: Any]) -> BaseEnvelope {
        do {
            let store = try library.openStore(appID: appID)
            defer { store.close() }
            let tableDef = try BaseSchemaValidator.parseTable(table, schema: nil)
            try store.createTable(tableDef)
            // 签名级变更：回写包 schema 并单调前移 packageVersion。
            var schemaObject = try library.currentSchemaObject(appID: appID)
            var tables = (schemaObject["tables"] as? [[String: Any]]) ?? []
            tables.append(table)
            schemaObject["tables"] = tables
            try library.updateSchema(appID: appID, schemaObject: schemaObject)
            return .success(data: [
                "appID": appID,
                "table": tableDef.name,
                "packageVersion": try library.packageVersion(appID: appID)
            ])
        } catch let error as BaseError {
            return .failure(error)
        } catch {
            return .failure(BaseError(code: .internal, message: "建表失败", hint: "\(error)"))
        }
    }

    public func tableAlterEnvelope(appID: String, tableName: String, changes: [String: Any]) -> BaseEnvelope {
        do {
            let store = try library.openStore(appID: appID)
            defer { store.close() }
            let schema = try library.currentSchema(appID: appID)
            guard let tableDef = schema.table(named: tableName) else {
                throw BaseError(code: .notFound, message: "表不存在于 schema", hint: "schema 无表 \(tableName)")
            }
            // M1 仅支持 addField：追加字段（其余 changes 形态 M2 的声明式方法演进）。
            if let addField = changes["addField"] as? [String: Any] {
                let fieldDef = try BaseSchemaValidator.parseField(addField)
                guard tableDef.fields.allSatisfy({ $0.name != fieldDef.name }) else {
                    throw BaseError(code: .validationFailed, message: "字段已存在", hint: "字段 \(fieldDef.name) 已在表 \(tableName) 中")
                }
                try store.addColumn(fieldDef, to: tableName)
                // 回写 schema：更新目标表字段。
                var schemaObject = try library.currentSchemaObject(appID: appID)
                var tables = (schemaObject["tables"] as? [[String: Any]]) ?? []
                if let index = tables.firstIndex(where: { ($0["name"] as? String) == tableName }) {
                    var fields = (tables[index]["fields"] as? [[String: Any]]) ?? []
                    fields.append(addField)
                    tables[index]["fields"] = fields
                    schemaObject["tables"] = tables
                    try library.updateSchema(appID: appID, schemaObject: schemaObject)
                }
                return .success(data: [
                    "appID": appID,
                    "table": tableName,
                    "addField": fieldDef.name,
                    "packageVersion": try library.packageVersion(appID: appID)
                ])
            }
            throw BaseError(code: .validationFailed, message: "不支持的变更", hint: "M1 仅支持 addField，如 addField: {name: amount, type: number}")
        } catch let error as BaseError {
            return .failure(error)
        } catch {
            return .failure(BaseError(code: .internal, message: "改表失败", hint: "\(error)"))
        }
    }

    // MARK: - 数据读写

    public func recordGetEnvelope(appID: String, table: String, id: String) -> BaseEnvelope {
        do {
            let store = try library.openStore(appID: appID)
            defer { store.close() }
            guard try store.tableExists(table) else {
                throw BaseError(code: .notFound,
                                message: "TABLE_NOT_IN_SCOPE：表 \(table) 不在 App \(appID) 作用域内",
                                hint: "核对表名与 App schema")
            }
            guard let record = try store.fetch(id: id, table: table) else {
                throw BaseError(code: .notFound, message: "记录不存在", hint: "\(table)/\(id)")
            }
            var dict: [String: Any] = ["id": id]
            for (key, value) in record {
                dict[key] = value.jsonObject
            }
            return .success(data: dict)
        } catch let error as BaseError {
            return .failure(error)
        } catch {
            return .failure(BaseError(code: .internal, message: "读取记录失败", hint: "\(error)"))
        }
    }

    public func querySelectEnvelope(appID: String, table: String, filter: [String: Any]?, sort: [[String: Any]]?, page: [String: Any]?, lookup: [String]?) -> BaseEnvelope {
        do {
            let store = try library.openStore(appID: appID)
            defer { store.close() }
            let schema = try library.currentSchema(appID: appID)
            let executor = BaseQueryExecutor(store: store, table: table, schema: schema)
            let rows = try executor.select(filter: filter, sort: sort, page: page, lookup: lookup)
            return .success(data: ["rows": rows])
        } catch let error as BaseError {
            return .failure(error)
        } catch {
            return .failure(BaseError(code: .internal, message: "查询失败", hint: "\(error)"))
        }
    }

    public func queryAggregateEnvelope(appID: String, table: String, aggregations: [[String: Any]], filter: [String: Any]?, groupBy: [String]?, timeSeries: [String: Any]?) -> BaseEnvelope {
        do {
            let store = try library.openStore(appID: appID)
            defer { store.close() }
            let schema = try library.currentSchema(appID: appID)
            let executor = BaseQueryExecutor(store: store, table: table, schema: schema)
            let rows = try executor.aggregate(aggregations: aggregations, filter: filter, groupBy: groupBy, timeSeries: timeSeries)
            return .success(data: ["rows": rows.map { row in row.mapValues { $0.jsonObject } }])
        } catch let error as BaseError {
            return .failure(error)
        } catch {
            return .failure(BaseError(code: .internal, message: "聚合失败", hint: "\(error)"))
        }
    }

    public func recordMutateEnvelope(appID: String, table: String, ops: [[String: Any]], dryRun: Bool, idempotencyKey: String?) -> BaseEnvelope {
        do {
            let store = try library.openStore(appID: appID)
            defer { store.close() }
            let schema = try library.currentSchema(appID: appID)
            let mutator = BaseRecordMutator(store: store, schema: schema)
            let result = try mutator.mutate(appID: appID, table: table, ops: ops, dryRun: dryRun, idempotencyKey: idempotencyKey)
            return .success(data: result)
        } catch let error as BaseError {
            return .failure(error)
        } catch {
            return .failure(BaseError(code: .internal, message: "写入失败", hint: "\(error)"))
        }
    }

    // MARK: - CSV 外部文件通道

    public func importCSVEnvelope(appID: String, table: String, rows: [[String: Any]], dryRun: Bool) -> BaseEnvelope {
        do {
            let store = try library.openStore(appID: appID)
            defer { store.close() }
            let schema = try library.currentSchema(appID: appID)
            guard let tableDef = schema.table(named: table) else {
                throw BaseError(code: .notFound, message: "表不存在", hint: "schema 无表 \(table)")
            }
            // rows（结构化对象数组）→ CSV 文本 → 走 mutate 同一条校验/审计路径（类型由 schema 决定）。
            let fieldNames = tableDef.fields.map { $0.name }
            let csvText = Self.rowsToCSV(rows: rows, fieldNames: fieldNames)
            let result = try BaseCSV.importCSV(csv: csvText, table: table, schema: schema, store: store, dryRun: dryRun)
            return .success(data: [
                "imported": result.imported,
                "dryRun": result.dryRun,
                "errors": result.errors.map { ["row": $0.row, "message": $0.message] }
            ])
        } catch let error as BaseError {
            return .failure(error)
        } catch {
            return .failure(BaseError(code: .internal, message: "导入失败", hint: "\(error)"))
        }
    }

    public func exportCSVEnvelope(appID: String, table: String, filter: [String: Any]?) -> BaseEnvelope {
        do {
            let store = try library.openStore(appID: appID)
            defer { store.close() }
            let schema = try library.currentSchema(appID: appID)
            guard let tableDef = schema.table(named: table) else {
                throw BaseError(code: .notFound, message: "表不存在", hint: "schema 无表 \(table)")
            }
            let executor = BaseQueryExecutor(store: store, table: table, schema: schema)
            let rows = try executor.select(filter: filter, sort: nil, page: nil, lookup: nil)
            let fieldNames = tableDef.fields.map { $0.name }
            let csv = BaseCSV.exportCSV(records: rows, fieldOrder: fieldNames)
            return .success(data: ["csv": csv, "rowCount": rows.count])
        } catch let error as BaseError {
            return .failure(error)
        } catch {
            return .failure(BaseError(code: .internal, message: "导出失败", hint: "\(error)"))
        }
    }

    // MARK: - 辅助

    private static func rowsToCSV(rows: [[String: Any]], fieldNames: [String]) -> String {
        var lines = [fieldNames.joined(separator: ",")]
        for row in rows {
            var cells: [String] = []
            for field in fieldNames {
                cells.append(csvCell(row[field]))
            }
            lines.append(cells.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private static func csvCell(_ value: Any?) -> String {
        guard let value else { return "" }
        let text: String
        if let string = value as? String {
            text = string
        } else if let number = value as? Double {
            text = number.rounded(.towardZero) == number ? String(Int(number)) : String(number)
        } else if let number = value as? Int {
            text = String(number)
        } else if let flag = value as? Bool {
            text = flag ? "true" : "false"
        } else {
            text = "\(value)"
        }
        if text.contains(",") || text.contains("\"") || text.contains("\n") {
            return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return text
    }
}

/// Connor Base 工具（M1-M3 薄封装，13 个）。
/// 每个工具返回统一返回信封（envelope 的 JSON 形态），错误码 taxonomy 见契约。
public struct BaseAgentTool: AgentTool {

    public enum Operation: String, Sendable, CaseIterable {
        case guide = "base.guide"
        case appCreate = "base.app.create"
        case appDelete = "base.app.delete"
        case appList = "base.app.list"
        case appGet = "base.app.get"
        case tableCreate = "base.table.create"
        case tableAlter = "base.table.alter"
        case recordGet = "base.record.get"
        case querySelect = "base.query.select"
        case queryAggregate = "base.query.aggregate"
        case recordMutate = "base.record.mutate"
        case importCSV = "base.import.csv"
        case exportCSV = "base.export.csv"
    }

    public let operation: Operation
    public let runtime: BaseToolRuntime

    public init(operation: Operation, runtime: BaseToolRuntime) {
        self.operation = operation
        self.runtime = runtime
    }

    public var name: String { operation.rawValue }

    public var permission: AgentPermissionCapability {
        switch operation {
        case .guide, .appList, .appGet, .recordGet, .querySelect, .queryAggregate, .exportCSV:
            .baseRead
        case .recordMutate, .importCSV:
            .baseWrite
        case .tableCreate, .tableAlter:
            .baseManageSchema
        case .appCreate, .appDelete:
            .baseManageApps
        }
    }

    public var description: String {
        switch operation {
        case .guide:
            "base.guide：返回 Connor Base 平台契约（工具目录 25 个、统一返回信封与错误码、结构化查询对象、方法 DAG 语义、权限四步、应用取舍决策段、交互富集规范段、同步语义、配额、能力搜索入口）。创建或修改小应用之前必须先调用本工具读取契约。"
        case .appCreate:
            "base.app.create：创建正式小应用（AppPackage 四件套同批：manifest + schema + guide + methods）。不设工作台/散表/转正中间态——需要表（会重复写入、要按数值时间统计、数字错了有代价）就经用户确认后直接建正式私有小应用（私有态起步、结构可 app.update 演进、日后可切 shared/public）。创建前先读 base.guide 契约。"
        case .appDelete:
            "base.app.delete：删除小应用（注册行 + 独立子库文件一并清除，不留数据残壳）。"
        case .appList:
            "base.app.list：列出当前可用的小应用（私有 + 共享 + 已安装公开），按 scope 过滤、按名称/领域/ID 检索。能力搜索的第一步。"
        case .appGet:
            "base.app.get：读取 App Card（appID/名称/领域/三态/packageVersion/方法摘要/requiredCapabilities/imports/riskLevel/sdkVersion），可选附指南全文。搜索命中后先读 Card 再调用。"
        case .tableCreate:
            "base.table.create：在 App 子库内新建表（字段类型收口 text/number/boolean/date/enum/relation/asset）。签名级变更：触发包 schema 回写与 packageVersion 单调前移。"
        case .tableAlter:
            "base.table.alter：修改表结构。M1 支持 addField（追加字段），其余变更形态随 M2 声明式方法演进。签名级变更，包版本前移。"
        case .recordGet:
            "base.record.get：按 id 读取单条记录。"
        case .querySelect:
            "base.query.select：结构化查询（filter 树 / sort / 分页 / lookup），返回行数组。数字永远出自内核，不心算。"
        case .queryAggregate:
            "base.query.aggregate：聚合查询（sum/avg/count/min/max/分组/时间序列），返回聚合行。供交互富集取域状态快照。"
        case .recordMutate:
            "base.record.mutate：写操作单入口（insert/update/delete 三动词，乐观并发、dryRun、幂等键）。"
        case .importCSV:
            "base.import.csv：导入 CSV 行数据到 App 表（rows 数组，走 mutate 同一条校验路径，dryRun 可预览）。属外部 CSV 文件通道，与跨库导入无关。"
        case .exportCSV:
            "base.export.csv：把表数据导出为 CSV 文本。属外部 CSV 文件通道。"
        }
    }

    public var inputSchema: AgentToolInputSchema {
        let fieldDefSchema = AgentToolInputSchema.object(properties: [
            "name": .string(description: "字段名"),
            "type": .stringEnumeration(values: ["text", "number", "boolean", "date", "enum", "relation", "asset"], description: "字段类型（契约冻结 7 种）"),
            "required": .boolean(description: "是否必填"),
            "unique": .boolean(description: "是否唯一"),
            "options": .array(items: .string(description: "enum 允许值"), description: "enum 字段的允许值"),
            "default": .string(description: "默认值"),
            "refTable": .string(description: "relation 目标表"),
            "refField": .string(description: "relation 目标字段")
        ], required: ["name", "type"])
        let tableDefSchema = AgentToolInputSchema.object(properties: [
            "name": .string(description: "表名"),
            "description": .string(description: "表说明"),
            "fields": .array(items: fieldDefSchema, description: "字段定义数组"),
            "relations": .array(items: .string(description: "关系字段名"), description: "关系字段")
        ], required: ["name", "fields"])
        switch operation {
        case .guide:
            return .closedObject(properties: [
                "section": .string(description: "可选：只返回契约的指定章节（如 tools/query/errorCodes/quotas/appDecision/enrichment）")
            ], required: [])
        case .appCreate:
            return .object(properties: [
                "manifest": .object(properties: [
                    "appID": .string(description: "小写 appID，匹配 ^[a-z0-9_-]{1,48}$"),
                    "name": .string(description: "App 名称"),
                    "domain": .string(description: "领域（如 记账/项目进度/库存）"),
                    "visibility": .stringEnumeration(values: ["private", "shared", "public"], description: "三态：private 私有 / shared 好友可见 / public 全员公开"),
                    "requiredCapabilities": .array(items: .string(description: "能力点"), description: "v1 仅发放 imports/network/asset；import 跨库只读导入不发放"),
                    "imports": .array(items: .object(properties: ["appID": .string(description: "目标 App"), "method": .string(description: "exported 方法全限定名")], required: ["appID", "method"]), description: "跨 App 依赖（仅 exported 方法调用，v1 唯一跨库通路）"),
                    "riskLevel": .stringEnumeration(values: ["low", "medium", "high"], description: "风险等级"),
                    "sdkVersion": .integer(description: "sdk 版本")
                ], required: ["appID", "name", "domain", "visibility"]),
                "schema": .object(properties: [
                    "tables": .array(items: tableDefSchema, description: "表定义数组")
                ], required: ["tables"]),
                "guide": .object(properties: [
                    "whenToUse": .string(description: "什么时候用（用户真实触发语气场景句）"),
                    "whenNotToUse": .string(description: "什么时候不用（路由判据）"),
                    "sections": .array(items: .object(properties: ["title": .string(description: "章节标题"), "body": .string(description: "章节正文")], required: ["title", "body"]), description: "App Guide 十一段正文"),
                    "writeMethods": .array(items: .string(description: "写方法名"), description: "写方法列表（含伴随读取声明）"),
                    "readMethods": .array(items: .string(description: "只读方法名"), description: "只读方法列表")
                ], required: ["whenToUse", "whenNotToUse"]),
                "methods": .array(items: .object(properties: [
                    "name": .string(description: "方法名"),
                    "description": .string(description: "方法说明"),
                    "readOnly": .boolean(description: "是否只读方法"),
                    "steps": .array(items: .object(properties: [
                        "type": .stringEnumeration(values: ["query", "aggregate", "mutate", "assert", "call", "reply"], description: "步骤类型"),
                        "label": .string(description: "步骤标签"),
                        "tool": .string(description: "调用的工具名"),
                        "args": .object(properties: [:], required: [])
                    ], required: ["type"]), description: "方法 DAG 步骤")
                ], required: ["name"]), description: "方法定义数组")
            ], required: ["manifest", "schema", "guide"])
        case .appDelete:
            return .closedObject(properties: ["appID": .string(description: "要删除的 appID")], required: ["appID"])
        case .appList:
            return .closedObject(properties: [
                "scope": .stringEnumeration(values: ["all", "private", "shared", "public"], description: "按三态过滤，默认 all"),
                "query": .string(description: "按名称/领域/appID 检索")
            ], required: [])
        case .appGet:
            return .closedObject(properties: [
                "appID": .string(description: "目标 appID"),
                "includeGuide": .boolean(description: "是否附指南全文，默认 true")
            ], required: ["appID"])
        case .tableCreate:
            return .closedObject(properties: [
                "appID": .string(description: "目标 appID"),
                "table": tableDefSchema
            ], required: ["appID", "table"])
        case .tableAlter:
            return .closedObject(properties: [
                "appID": .string(description: "目标 appID"),
                "tableName": .string(description: "要修改的表名"),
                "changes": .object(properties: [
                    "addField": fieldDefSchema
                ], required: [])
            ], required: ["appID", "tableName", "changes"])
        case .recordGet:
            return .closedObject(properties: [
                "appID": .string(description: "目标 appID"),
                "table": .string(description: "表名"),
                "id": .string(description: "记录 id")
            ], required: ["appID", "table", "id"])
        case .querySelect:
            return .object(properties: [
                "appID": .string(description: "目标 appID"),
                "table": .string(description: "表名"),
                "filter": .object(properties: [
                    "and": .array(items: .object(properties: ["field": .string(description: "字段"), "op": .string(description: "操作符"), "value": .string(description: "值")], required: ["field", "op"]), description: "and 条件"),
                    "or": .array(items: .object(properties: ["field": .string(description: "字段"), "op": .string(description: "操作符"), "value": .string(description: "值")], required: ["field", "op"]), description: "or 条件")
                ], required: []),
                "sort": .array(items: .object(properties: ["field": .string(description: "排序字段"), "direction": .stringEnumeration(values: ["asc", "desc"], description: "方向")], required: ["field"]), description: "排序"),
                "page": .object(properties: ["offset": .integer(description: "偏移"), "limit": .integer(description: "数量")], required: []),
                "lookup": .array(items: .string(description: "relation 字段名"), description: "lookup 展开")
            ], required: ["appID", "table"])
        case .queryAggregate:
            return .object(properties: [
                "appID": .string(description: "目标 appID"),
                "table": .string(description: "表名"),
                "aggregations": .array(items: .object(properties: [
                    "op": .stringEnumeration(values: ["sum", "avg", "count", "min", "max"], description: "聚合算子"),
                    "field": .string(description: "聚合字段"),
                    "alias": .string(description: "结果别名")
                ], required: ["op"]), description: "聚合列表"),
                "filter": .object(properties: [:], required: []),
                "groupBy": .array(items: .string(description: "分组字段"), description: "分组字段列表"),
                "timeSeries": .object(properties: ["field": .string(description: "时间字段"), "bucket": .stringEnumeration(values: ["day", "week", "month"], description: "时间桶")], required: ["field", "bucket"])
            ], required: ["appID", "table", "aggregations"])
        case .recordMutate:
            return .object(properties: [
                "appID": .string(description: "目标 appID"),
                "table": .string(description: "表名"),
                "ops": .array(items: .object(properties: [
                    "op": .stringEnumeration(values: ["insert", "update", "delete"], description: "写操作动词"),
                    "id": .string(description: "记录 id（update/delete 必填；insert 省略时自动生成 rec_N 顺序 id）"),
                    "record": .object(properties: [:], required: []),
                    "expectedVersion": .integer(description: "乐观并发版本（update 用）")
                ], required: ["op"]), description: "写操作列表"),
                "dryRun": .boolean(description: "预览模式，不落库"),
                "idempotencyKey": .string(description: "幂等键")
            ], required: ["appID", "table", "ops"])
        case .importCSV:
            return .object(properties: [
                "appID": .string(description: "目标 appID"),
                "table": .string(description: "表名"),
                "rows": .array(items: .object(properties: [:], required: []), description: "行对象数组（键为 schema 字段名）"),
                "dryRun": .boolean(description: "预览模式")
            ], required: ["appID", "table", "rows"])
        case .exportCSV:
            return .object(properties: [
                "appID": .string(description: "目标 appID"),
                "table": .string(description: "表名"),
                "filter": .object(properties: [:], required: [])
            ], required: ["appID", "table"])
        }
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        // M1-M7 审计（best-effort）：记录工具调用轨迹到目标 App 子库；端侧、不同步、不进返回信封。
        var auditAppID = arguments.string("appID")
        if operation == .appCreate {
            // app.create 的 appID 嵌在 manifest 里。
            if case .object(let manifest)? = arguments.values["manifest"],
               case .string(let id)? = manifest["appID"] {
                auditAppID = id
            }
        }
        let auditOperation = operation.rawValue
        let auditDetail = arguments.compactSummary()
        defer {
            if let appID = auditAppID {
                Task { await runtime.recordAudit(appID: appID, operation: auditOperation, detail: auditDetail) }
            }
        }
        switch operation {
        case .guide:
            let envelope = await runtime.guideEnvelope(section: arguments.string("section"))
            return makeResult(envelope, text: "Connor Base 平台契约已返回。", context: context)
        case .appCreate:
            let envelope = await runtime.createAppEnvelope(
                manifest: try object("manifest", arguments),
                schema: try object("schema", arguments),
                guide: try object("guide", arguments),
                methods: try optionalArray("methods", arguments) ?? []
            )
            return makeResult(envelope, text: "App 已创建（四件套同批、私有态起步，无工作台/转正中间态）。", context: context)
        case .appDelete:
            let envelope = await runtime.deleteAppEnvelope(appID: try requiredString("appID", arguments))
            return makeResult(envelope, text: "App 删除结果已返回。", context: context)
        case .appList:
            let envelope = await runtime.listAppsEnvelope(scope: arguments.string("scope"), query: arguments.string("query"))
            return makeResult(envelope, text: "App 列表已返回。", context: context)
        case .appGet:
            let envelope = await runtime.appCardEnvelope(appID: try requiredString("appID", arguments), includeGuide: arguments.bool("includeGuide") ?? true)
            return makeResult(envelope, text: "App Card 已返回。", context: context)
        case .tableCreate:
            let envelope = await runtime.tableCreateEnvelope(appID: try requiredString("appID", arguments), table: try object("table", arguments))
            return makeResult(envelope, text: "建表结果已返回（签名级变更，packageVersion 已前移）。", context: context)
        case .tableAlter:
            let envelope = await runtime.tableAlterEnvelope(appID: try requiredString("appID", arguments), tableName: try requiredString("tableName", arguments), changes: try object("changes", arguments))
            return makeResult(envelope, text: "改表结果已返回（签名级变更，packageVersion 已前移）。", context: context)
        case .recordGet:
            let envelope = await runtime.recordGetEnvelope(appID: try requiredString("appID", arguments), table: try requiredString("table", arguments), id: try requiredString("id", arguments))
            return makeResult(envelope, text: "记录已返回。", context: context)
        case .querySelect:
            let envelope = await runtime.querySelectEnvelope(
                appID: try requiredString("appID", arguments),
                table: try requiredString("table", arguments),
                filter: try optionalObject("filter", arguments),
                sort: try optionalArray("sort", arguments),
                page: try optionalObject("page", arguments),
                lookup: try optionalStringArray("lookup", arguments)
            )
            return makeResult(envelope, text: "查询结果已返回（数字出自内核）。", context: context)
        case .queryAggregate:
            let envelope = await runtime.queryAggregateEnvelope(
                appID: try requiredString("appID", arguments),
                table: try requiredString("table", arguments),
                aggregations: try array("aggregations", arguments),
                filter: try optionalObject("filter", arguments),
                groupBy: try optionalStringArray("groupBy", arguments),
                timeSeries: try optionalObject("timeSeries", arguments)
            )
            return makeResult(envelope, text: "聚合结果已返回（数字出自内核）。", context: context)
        case .recordMutate:
            let envelope = await runtime.recordMutateEnvelope(
                appID: try requiredString("appID", arguments),
                table: try requiredString("table", arguments),
                ops: try array("ops", arguments),
                dryRun: arguments.bool("dryRun") ?? false,
                idempotencyKey: arguments.string("idempotencyKey")
            )
            return makeResult(envelope, text: "写入结果已返回。", context: context)
        case .importCSV:
            let envelope = await runtime.importCSVEnvelope(
                appID: try requiredString("appID", arguments),
                table: try requiredString("table", arguments),
                rows: try array("rows", arguments),
                dryRun: arguments.bool("dryRun") ?? false
            )
            return makeResult(envelope, text: "CSV 导入结果已返回（走 mutate 校验路径）。", context: context)
        case .exportCSV:
            let envelope = await runtime.exportCSVEnvelope(
                appID: try requiredString("appID", arguments),
                table: try requiredString("table", arguments),
                filter: try optionalObject("filter", arguments)
            )
            return makeResult(envelope, text: "CSV 导出结果已返回。", context: context)
        }
    }

    // MARK: - 参数与结果辅助

    private func requiredString(_ key: String, _ arguments: AgentToolArguments) throws -> String {
        guard let value = arguments.string(key) else {
            throw AgentToolError.invalidArguments("missing required argument: \(key)")
        }
        return value
    }

    private func object(_ key: String, _ arguments: AgentToolArguments) throws -> [String: Any] {
        guard case .object(let values)? = arguments.values[key] else {
            throw AgentToolError.invalidArguments("\(key) must be an object")
        }
        return values.mapValues { $0.jsonCompatibleObject }
    }

    private func optionalObject(_ key: String, _ arguments: AgentToolArguments) throws -> [String: Any]? {
        guard let value = arguments.values[key] else { return nil }
        guard case .object(let values) = value else {
            throw AgentToolError.invalidArguments("\(key) must be an object when present")
        }
        return values.mapValues { $0.jsonCompatibleObject }
    }

    private func array(_ key: String, _ arguments: AgentToolArguments) throws -> [[String: Any]] {
        guard case .array(let items)? = arguments.values[key] else {
            throw AgentToolError.invalidArguments("\(key) must be an array")
        }
        return try items.map { item in
            guard case .object(let values) = item else {
                throw AgentToolError.invalidArguments("\(key) items must be objects")
            }
            return values.mapValues { $0.jsonCompatibleObject }
        }
    }

    private func optionalArray(_ key: String, _ arguments: AgentToolArguments) throws -> [[String: Any]]? {
        guard let value = arguments.values[key] else { return nil }
        guard case .array(let items) = value else {
            throw AgentToolError.invalidArguments("\(key) must be an array when present")
        }
        return try items.map { item in
            guard case .object(let values) = item else {
                throw AgentToolError.invalidArguments("\(key) items must be objects")
            }
            return values.mapValues { $0.jsonCompatibleObject }
        }
    }

    private func optionalStringArray(_ key: String, _ arguments: AgentToolArguments) throws -> [String]? {
        guard let value = arguments.values[key] else { return nil }
        guard case .array(let items) = value else {
            throw AgentToolError.invalidArguments("\(key) must be an array of strings when present")
        }
        return try items.map { item in
            guard case .string(let text) = item else {
                throw AgentToolError.invalidArguments("\(key) items must be strings")
            }
            return text
        }
    }

    private func makeResult(_ envelope: BaseEnvelope, text: String, context: AgentToolExecutionContext) -> AgentToolResult {
        let data = try? JSONSerialization.data(withJSONObject: envelope.asDictionary(), options: [.sortedKeys])
        let json = data.flatMap { String(data: $0, encoding: .utf8) }
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: text, contentJSON: json)
    }
}

public extension AgentToolRegistry {
    mutating func registerBaseTools(runtime: BaseToolRuntime) {
        for operation in BaseAgentTool.Operation.allCases {
            register(BaseAgentTool(operation: operation, runtime: runtime))
        }
    }
}

