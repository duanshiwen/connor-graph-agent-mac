import Foundation

/// M2-K1：声明式方法 DAG 解释器核心。
///
/// 契约语义（v0.12 §4.4 / base.sdk.v1.json）：
/// - 方法 = { name, description, inputSchema, steps[], exports?, readOnly? }
/// - 步骤类型：query / aggregate / mutate / assert（onFail: reject|warn）/ call / reply /
///   export.csv（列白名单 + 行数上限导出 CSV；含 export.csv 步骤的方法非只读）
/// - 无循环、无任意代码、无外部网络
/// - 配额：maxMethodSteps = 20、maxCrossAppCallDepth = 5、maxRowsPerQuery = 5000
/// - 只读判定：方法体仅 query/aggregate + reply；显式 readOnly 或推导只读均禁写
///
/// 步骤输出以 `as` 命名存入变量上下文；reply 模板用 `$path` 引用上游输出（JSONPath 子集）。
/// M2-K2 起 call 步骤由宿主注入跨 App registry，本解释器仅承担深度计数与递归。
/// M7：每步执行后写一条 method.step 审计（traceId 贯穿整次 invoke，跨 App call 子调用继承）。

public enum BaseMethodStepType: String, Equatable {
    case query
    case aggregate
    case mutate
    case assert
    case call
    case reply
    case exportCSV = "export.csv"
}

/// M7：方法执行的追踪上下文（invoke 全链路贯穿；跨 App call 子调用继承同一 traceId）。
public struct BaseMethodTraceContext {
    public let traceId: String
    public let methodName: String
    /// 固定 "runtime"（方法执行只发生在运行面）。
    public let surface: String

    public init(traceId: String, methodName: String, surface: String = "runtime") {
        self.traceId = traceId
        self.methodName = methodName
        self.surface = surface
    }
}

/// 方法步骤模型（保留原始 JSON 供各步骤执行器使用）。
public struct BaseMethodStep {
    public let type: BaseMethodStepType
    public let raw: [String: Any]

    public init(type: BaseMethodStepType, raw: [String: Any]) {
        self.type = type
        self.raw = raw
    }
}

/// 方法定义模型（v0.12 §4.4）。
public struct BaseMethodDef {
    public let name: String
    public let description: String
    public let inputSchema: [String: Any]?
    public let steps: [BaseMethodStep]
    public let exports: Bool
    public let readOnly: Bool          // 显式声明
    public let derivedReadOnly: Bool   // 方法体推导：仅 query/aggregate + reply

    public init(json: [String: Any]) throws {
        guard let name = json["name"] as? String, !name.isEmpty else {
            throw BaseError(code: .validationFailed, message: "方法 name 缺失", hint: "方法必须有名字")
        }
        self.name = name
        self.description = (json["description"] as? String) ?? ""
        self.inputSchema = json["inputSchema"] as? [String: Any]
        let rawSteps = (json["steps"] as? [[String: Any]]) ?? []
        guard !rawSteps.isEmpty else {
            throw BaseError(code: .validationFailed, message: "方法 steps 为空", hint: "方法至少一个步骤")
        }
        guard rawSteps.count <= BaseMethodInterpreter.maxMethodSteps else {
            throw BaseError(
                code: .quotaExceeded,
                message: "方法步骤数超过 maxMethodSteps=\(BaseMethodInterpreter.maxMethodSteps)",
                hint: "拆分方法，方法体保持声明式 DAG"
            )
        }
        var steps: [BaseMethodStep] = []
        for s in rawSteps {
            guard let t = s["type"] as? String, let type = BaseMethodStepType(rawValue: t) else {
                throw BaseError(
                    code: .validationFailed,
                    message: "步骤 type 不合法",
                    hint: "须为 query/aggregate/mutate/assert/call/reply/export.csv"
                )
            }
            steps.append(BaseMethodStep(type: type, raw: s))
        }
        self.steps = steps
        self.exports = (json["exports"] as? Bool) ?? false
        self.readOnly = (json["readOnly"] as? Bool) ?? false
        // 只读推导：方法体仅 query/aggregate + reply（assert/call/mutate/export.csv 不计入只读；
        // 含 export.csv 步骤的方法一律非只读——契约口径）。
        self.derivedReadOnly = steps.allSatisfy {
            $0.type == .query || $0.type == .aggregate || $0.type == .reply
        }
    }

    /// 有效只读：显式声明或方法体推导只读。
    public var isReadOnly: Bool { readOnly || derivedReadOnly }
}

/// 断言信号：v0.12 §2.7.4 事实层——warn 信号必出内核、不可压。
/// 当前仅 `warn`（onFail: reject 直接抛错，不入信号）；level 字段留给后续扩展。
public struct BaseMethodSignal: Equatable {
    public let level: String
    public let message: String

    public init(level: String = "warn", message: String) {
        self.level = level
        self.message = message
    }
}

/// 方法执行结果：reply 数据（或末步骤输出）+ warn 信号 + 变量上下文。
public struct BaseMethodResult {
    public let data: JSONValue
    public let signals: [BaseMethodSignal]
    public let variables: [String: JSONValue]

    public init(data: JSONValue, signals: [BaseMethodSignal], variables: [String: JSONValue]) {
        self.data = data
        self.signals = signals
        self.variables = variables
    }

    /// warn 消息列表（便捷访问，供信封/富集层用）。
    public var warnings: [String] { signals.map(\.message) }
}

/// 方法调用目标：解析后的执行上下文（appID + 子库 + schema + 方法定义）。
/// M2-K2：call 步骤可切换上下文——同 App 调用解析为当前子库；跨 App 调用由宿主解析为属主子库，
/// 在属主上下文执行、受属主权限约束（target.appID 即执行归属）。
public struct BaseMethodTarget {
    public let appID: String
    public let store: BaseSubLibraryStore
    public let schema: BaseAppSchema
    public let method: BaseMethodDef

    public init(appID: String, store: BaseSubLibraryStore, schema: BaseAppSchema, method: BaseMethodDef) {
        self.appID = appID
        self.store = store
        self.schema = schema
        self.method = method
    }
}

/// 方法 DAG 解释器：顺序执行步骤，变量上下文驱动 assert/call/reply。
public struct BaseMethodInterpreter {
    public static let maxMethodSteps = 20
    public static let maxCrossAppCallDepth = 5

    public let store: BaseSubLibraryStore
    public let schema: BaseAppSchema

    public init(store: BaseSubLibraryStore, schema: BaseAppSchema) {
        self.store = store
        self.schema = schema
    }

    /// 执行方法。
    /// - Parameters:
    ///   - method: 方法定义。
    ///   - args: 入参（inputSchema required 校验）。
    ///   - resolver: 方法引用解析器（call 步骤用）。同 App 名解析为当前子库上下文；
    ///     全限定名 `appID.method` 由宿主解析为属主子库上下文（并完成 imports 校验）。
    ///   - appID: 当前 App（write 归属、跨 App exported 判定与错误上下文）。
    ///   - callDepth: 当前 call 深度（递归调用时 +1）。
    ///   - trace: M7 追踪上下文（traceId/methodName/surface）；每步执行后写一条
    ///     method.step 审计到当前上下文子库。跨 App call 子调用继承同一 traceId。
    ///     缺省时内部铸造新 traceId（历史调用面兼容）。
    public func invoke(
        method: BaseMethodDef,
        args: [String: Any],
        resolver: (String) throws -> BaseMethodTarget?,
        appID: String,
        callDepth: Int = 0,
        trace: BaseMethodTraceContext? = nil
    ) throws -> BaseMethodResult {
        try validateArgs(method: method, args: args)

        let context = trace ?? BaseMethodTraceContext(traceId: BaseEnvelope.newTraceID(), methodName: method.name)
        var vars: [String: JSONValue] = [:]
        var signals: [BaseMethodSignal] = []
        var lastData: JSONValue = .object([:])

        for step in method.steps {
            let stepStartData = lastData
            switch step.type {
            case .query:
                lastData = try runQuery(step)
            case .aggregate:
                lastData = try runAggregate(step)
            case .mutate:
                guard !method.isReadOnly else {
                    throw BaseError(
                        code: .validationFailed,
                        message: "只读方法禁止包含 mutate 步骤",
                        hint: "readOnly 方法体仅允许 query/aggregate + reply"
                    )
                }
                lastData = try runMutate(step, appID: appID)
            case .assert:
                try runAssert(step, vars: vars, signals: &signals)
            case .call:
                lastData = try runCall(step, appID: appID, method: method, args: args, vars: vars, resolver: resolver, callDepth: callDepth, trace: context)
            case .reply:
                lastData = try runReply(step, vars: vars)
                auditStep(method: method, step: step, table: step.raw["table"] as? String, result: lastData, previous: stepStartData, trace: context)
                // reply 为终止步骤。
                return BaseMethodResult(data: lastData, signals: signals, variables: vars)
            case .exportCSV:
                guard !method.isReadOnly else {
                    throw BaseError(
                        code: .validationFailed,
                        message: "只读方法禁止包含 export.csv 步骤",
                        hint: "readOnly 方法体仅允许 query/aggregate + reply；含 export.csv 的方法非只读"
                    )
                }
                lastData = try runExportCSV(step)
            }
            if let name = step.raw["as"] as? String, !name.isEmpty {
                vars[name] = lastData
            }
            auditStep(method: method, step: step, table: step.raw["table"] as? String, result: lastData, previous: stepStartData, trace: context)
        }
        return BaseMethodResult(data: lastData, signals: signals, variables: vars)
    }

    // MARK: - 步骤审计（M7）

    /// 每步一条 method.step 审计（best-effort；不改审计表 schema，detail 为 JSON 文本）。
    /// 子库即当前执行上下文（跨 App call 的子调用审计落在目标 App 子库，traceId 继承）。
    private func auditStep(
        method: BaseMethodDef,
        step: BaseMethodStep,
        table: String?,
        result: JSONValue,
        previous: JSONValue,
        trace: BaseMethodTraceContext
    ) {
        let rows = Self.auditRowCount(for: step, result: result, previous: previous)
        let detail = Self.stepAuditDetail(
            traceId: trace.traceId,
            methodName: trace.methodName,
            surface: trace.surface,
            stepType: step.type.rawValue,
            table: table ?? "",
            rows: rows
        )
        store.recordAudit(operation: "method.step", detail: detail)
    }

    /// 步骤涉及的行数（审计观测字段）：数组=行数；mutate=applied；export.csv=rowCount；其余 0。
    private static func auditRowCount(for step: BaseMethodStep, result: JSONValue, previous: JSONValue) -> Int {
        switch step.type {
        case .query, .aggregate:
            if case let .array(items) = result { return items.count }
            return 0
        case .mutate:
            if case let .object(dict) = result, let applied = dict["applied"]?.numberValue {
                return Int(applied)
            }
            return 0
        case .exportCSV:
            if case let .object(dict) = result, let rowCount = dict["rowCount"]?.numberValue {
                return Int(rowCount)
            }
            return 0
        case .assert:
            return 0
        case .call:
            // 子调用各步在目标上下文自记审计；此处只记调用发起本身。
            return 0
        case .reply:
            if case let .object(dict) = result, !dict.isEmpty { return 1 }
            return 0
        }
    }

    static func stepAuditDetail(
        traceId: String,
        methodName: String,
        surface: String,
        stepType: String,
        table: String,
        rows: Int
    ) -> String {
        let payload: [String: Any] = [
            "traceId": traceId,
            "methodName": methodName,
            "surface": surface,
            "stepType": stepType,
            "table": table,
            "rows": rows
        ]
        let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return String(data: data ?? Data(), encoding: .utf8) ?? "{}"
    }

    // MARK: - 入参校验

    private func validateArgs(method: BaseMethodDef, args: [String: Any]) throws {
        guard let schema = method.inputSchema, let required = schema["required"] as? [String] else {
            return
        }
        for key in required where args[key] == nil {
            throw BaseError(
                code: .validationFailed,
                message: "方法 \(method.name) 缺必填入参 \(key)",
                hint: "按 inputSchema 的 required 提供参数"
            )
        }
    }

    // MARK: - 步骤执行

    private func runQuery(_ step: BaseMethodStep) throws -> JSONValue {
        guard let table = step.raw["table"] as? String else {
            throw BaseError(code: .validationFailed, message: "query 步骤缺 table", hint: "query 步骤必须指定表")
        }
        let executor = BaseQueryExecutor(store: store, table: table, schema: schema)
        let rows = try executor.select(
            filter: step.raw["filter"] as? [String: Any],
            sort: step.raw["sort"] as? [[String: Any]],
            page: step.raw["page"] as? [String: Any]
        )
        return JSONValue(json: rows) ?? .null
    }

    private func runAggregate(_ step: BaseMethodStep) throws -> JSONValue {
        guard let table = step.raw["table"] as? String else {
            throw BaseError(code: .validationFailed, message: "aggregate 步骤缺 table", hint: "aggregate 步骤必须指定表")
        }
        let aggregations = (step.raw["aggregations"] as? [[String: Any]]) ?? []
        let executor = BaseQueryExecutor(store: store, table: table, schema: schema)
        let rows = try executor.aggregate(
            aggregations: aggregations,
            filter: step.raw["filter"] as? [String: Any],
            groupBy: step.raw["groupBy"] as? [String],
            timeSeries: step.raw["timeSeries"] as? [String: Any]
        )
        return .array(rows.map { .object($0) })
    }

    private func runMutate(_ step: BaseMethodStep, appID: String) throws -> JSONValue {
        guard let table = step.raw["table"] as? String else {
            throw BaseError(code: .validationFailed, message: "mutate 步骤缺 table", hint: "mutate 步骤必须指定表")
        }
        guard let ops = step.raw["ops"] as? [[String: Any]] else {
            throw BaseError(code: .validationFailed, message: "mutate 步骤缺 ops", hint: "mutate 步骤必须携带 ops 数组")
        }
        let mutator = BaseRecordMutator(store: store, schema: schema)
        let result = try mutator.mutate(
            appID: appID,
            table: table,
            ops: ops,
            dryRun: (step.raw["dryRun"] as? Bool) ?? false
        )
        return JSONValue(json: result) ?? .null
    }

    private func runAssert(_ step: BaseMethodStep, vars: [String: JSONValue], signals: inout [BaseMethodSignal]) throws {
        guard let on = step.raw["on"] as? [String: Any] else {
            throw BaseError(code: .validationFailed, message: "assert 步骤缺 on", hint: "assert 步骤必须携带 on 表达式")
        }
        let message = (step.raw["message"] as? String) ?? "断言不成立"
        let onFail = (step.raw["onFail"] as? String) ?? "reject"
        let passes = try evaluate(on, vars: vars)
        if !passes {
            if onFail == "warn" {
                signals.append(BaseMethodSignal(level: "warn", message: message))
            } else {
                throw BaseError(code: .validationFailed, message: message, hint: "assert 拒绝")
            }
        }
    }

    private func runCall(
        _ step: BaseMethodStep,
        appID: String,
        method: BaseMethodDef,
        args: [String: Any],
        vars: [String: JSONValue],
        resolver: (String) throws -> BaseMethodTarget?,
        callDepth: Int,
        trace: BaseMethodTraceContext
    ) throws -> JSONValue {
        if callDepth >= Self.maxCrossAppCallDepth {
            throw BaseError(
                code: .quotaExceeded,
                message: "跨 App 调用深度超过 maxCrossAppCallDepth=\(Self.maxCrossAppCallDepth)",
                hint: "检查方法 DAG 的 call 步骤链路"
            )
        }
        guard let target = step.raw["method"] as? String, !target.isEmpty else {
            throw BaseError(code: .validationFailed, message: "call 步骤缺 method", hint: "call 步骤必须指定方法名")
        }
        let callArgs: [String: Any]
        if let staticArgs = step.raw["args"] as? [String: Any] {
            callArgs = resolveArgs(staticArgs, vars: vars)
        } else {
            callArgs = args
        }
        guard let t = try resolver(target) else {
            throw BaseError(code: .notFound, message: "方法不存在", hint: target)
        }
        // M2-K2 跨 App 门禁：目标 app 不同于当前 app 时，方法必须 exported。
        if t.appID != appID && !t.method.exports {
            throw BaseError(
                code: .permissionDenied,
                message: "方法 \(t.method.name) 未导出，无法被跨 App 调用",
                hint: "请属主在方法定义中设置 exports=true"
            )
        }
        // 切换执行上下文：在属主子库/schema 中解释目标方法。
        // M7：子调用继承同一 traceId（跨 App 全链路一次追踪），methodName 换为目标方法。
        let targetInterpreter = BaseMethodInterpreter(store: t.store, schema: t.schema)
        let childTrace = BaseMethodTraceContext(traceId: trace.traceId, methodName: t.method.name, surface: trace.surface)
        let result = try targetInterpreter.invoke(
            method: t.method,
            args: callArgs,
            resolver: resolver,
            appID: t.appID,
            callDepth: callDepth + 1,
            trace: childTrace
        )
        return result.data
    }

    /// export.csv 步骤：列白名单（声明顺序即 CSV 表头）+ 可选 filter + 行数上限（maxRows，
    /// 缺省契约 maxRowsPerQuery=5000），超限/未知列 → VALIDATION_FAILED。
    /// 输出 {csv, rowCount, table}，可经 `as` 存入变量上下文（含此步骤的方法非只读）。
    private func runExportCSV(_ step: BaseMethodStep) throws -> JSONValue {
        guard let table = step.raw["table"] as? String else {
            throw BaseError(code: .validationFailed, message: "export.csv 步骤缺 table", hint: "export.csv 步骤必须指定表")
        }
        guard let tableDef = schema.table(named: table) else {
            throw BaseError(code: .notFound, message: "表不存在于 schema", hint: "schema 无表 \(table)")
        }
        let declaredColumns = (step.raw["columns"] as? [String]) ?? []
        guard !declaredColumns.isEmpty else {
            throw BaseError(
                code: .validationFailed,
                message: "export.csv 步骤缺 columns",
                hint: "export.csv 须声明列白名单（按导出顺序）；表 \(table) 允许列：\(tableDef.fields.map { $0.name }.joined(separator: "/"))"
            )
        }
        // 列白名单校验：声明列必须都在 schema 内（缺列/未知列拒绝）。
        let fieldNames = tableDef.fields.map { $0.name }
        for column in declaredColumns {
            guard fieldNames.contains(column) else {
                throw BaseError(
                    code: .validationFailed,
                    message: "export.csv 列未声明于 schema",
                    hint: "未知列 \(column)；表 \(table) 允许列：\(fieldNames.joined(separator: "/"))"
                )
            }
        }
        let executor = BaseQueryExecutor(store: store, table: table, schema: schema)
        let rows = try executor.select(
            filter: step.raw["filter"] as? [String: Any],
            sort: step.raw["sort"] as? [[String: Any]],
            page: step.raw["page"] as? [String: Any]
        )
        let maxRows = (step.raw["maxRows"] as? Int) ?? BaseQueryCompiler.maxRowsPerQuery
        guard rows.count <= maxRows else {
            throw BaseError(
                code: .validationFailed,
                message: "导出行数超过 maxRows=\(maxRows)",
                hint: "当前命中 \(rows.count) 行；请收紧 filter 或下调 maxRows"
            )
        }
        let csv = BaseCSV.exportCSV(records: rows, fieldOrder: declaredColumns)
        return .object([
            "table": .string(table),
            "rowCount": .number(Double(rows.count)),
            "csv": .string(csv)
        ])
    }

    private func runReply(_ step: BaseMethodStep, vars: [String: JSONValue]) throws -> JSONValue {
        guard let template = step.raw["template"] else {
            throw BaseError(code: .validationFailed, message: "reply 步骤缺 template", hint: "reply 步骤必须携带模板")
        }
        return resolveTemplate(template, vars: vars)
    }

    // MARK: - 断言求值

    /// assert 的 `on` 表达式：{ path, op, value }；value 可为字面量或 `$path`。
    private func evaluate(_ on: [String: Any], vars: [String: JSONValue]) throws -> Bool {
        guard let path = on["path"] as? String, let op = on["op"] as? String else {
            throw BaseError(code: .validationFailed, message: "assert on 表达式不合法", hint: "须含 path 与 op")
        }
        guard let lhs = resolvePath(path, in: vars) else {
            return false
        }
        let rhs: JSONValue
        if let v = on["value"] as? String, v.hasPrefix("$") {
            rhs = resolvePath(v, in: vars) ?? .null
        } else {
            rhs = JSONValue(json: on["value"] as Any) ?? .null
        }
        return compare(lhs, op: op, rhs: rhs)
    }

    private func compare(_ lhs: JSONValue, op: String, rhs: JSONValue) -> Bool {
        switch op {
        case "eq": return lhs == rhs
        case "neq": return lhs != rhs
        case "gt": return (lhs.numberValue ?? -Double.greatestFiniteMagnitude) > (rhs.numberValue ?? -Double.greatestFiniteMagnitude)
        case "gte": return (lhs.numberValue ?? -Double.greatestFiniteMagnitude) >= (rhs.numberValue ?? -Double.greatestFiniteMagnitude)
        case "lt": return (lhs.numberValue ?? Double.greatestFiniteMagnitude) < (rhs.numberValue ?? Double.greatestFiniteMagnitude)
        case "lte": return (lhs.numberValue ?? Double.greatestFiniteMagnitude) <= (rhs.numberValue ?? Double.greatestFiniteMagnitude)
        default:
            return false
        }
    }

    // MARK: - 模板与路径

    /// reply 模板：字符串以 `$` 开头视为变量路径；`$$` 转义字面 `$`；对象/数组递归。
    private func resolveTemplate(_ value: Any, vars: [String: JSONValue]) -> JSONValue {
        if let s = value as? String {
            if s.hasPrefix("$$") {
                return .string(String(s.dropFirst()))
            }
            if s.hasPrefix("$") {
                return resolvePath(s, in: vars) ?? .null
            }
            return .string(s)
        }
        if let dict = value as? [String: Any] {
            var out: [String: JSONValue] = [:]
            for (k, v) in dict {
                out[k] = resolveTemplate(v, vars: vars)
            }
            return .object(out)
        }
        if let arr = value as? [Any] {
            return .array(arr.map { resolveTemplate($0, vars: vars) })
        }
        return JSONValue(json: value) ?? .null
    }

    /// `$a.b.c` 点路径在变量上下文中取值。
    public func resolvePath(_ path: String, in vars: [String: JSONValue]) -> JSONValue? {
        var p = path
        if p.hasPrefix("$") {
            p = String(p.dropFirst())
        }
        guard !p.isEmpty else { return nil }
        let parts = p.split(separator: ".").map(String.init)
        guard let first = parts.first, let current = vars[first] else { return nil }
        var value = current
        for key in parts.dropFirst() {
            if case let .object(dict) = value {
                guard let next = dict[key] else { return nil }
                value = next
            } else if case let .array(arr) = value, let idx = Int(key), arr.indices.contains(idx) {
                value = arr[idx]
            } else {
                return nil
            }
        }
        return value
    }

    /// call 步骤的静态 args 中 `$path` 引用替换。
    private func resolveArgs(_ args: [String: Any], vars: [String: JSONValue]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (k, v) in args {
            if let s = v as? String, s.hasPrefix("$") {
                out[k] = resolvePath(s, in: vars)?.jsonObject ?? NSNull()
            } else if let dict = v as? [String: Any] {
                out[k] = resolveArgs(dict, vars: vars)
            } else if let arr = v as? [Any] {
                out[k] = arr.map { item -> Any in
                    if let s = item as? String, s.hasPrefix("$") {
                        return resolvePath(s, in: vars)?.jsonObject ?? NSNull()
                    }
                    return item
                }
            } else {
                out[k] = v
            }
        }
        return out
    }
}
