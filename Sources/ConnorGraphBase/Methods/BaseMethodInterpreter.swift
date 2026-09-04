import Foundation

/// M2-K1：声明式方法 DAG 解释器核心。
///
/// 契约语义（v0.12 §4.4 / base.sdk.v1.json）：
/// - 方法 = { name, description, inputSchema, steps[], exports?, readOnly? }
/// - 步骤类型：query / aggregate / mutate / assert（onFail: reject|warn）/ call / reply
/// - 无循环、无任意代码、无外部网络
/// - 配额：maxMethodSteps = 20、maxCrossAppCallDepth = 5
/// - 只读判定：方法体仅 query/aggregate + reply；显式 readOnly 或推导只读均禁写
///
/// 步骤输出以 `as` 命名存入变量上下文；reply 模板用 `$path` 引用上游输出（JSONPath 子集）。
/// M2-K2 起 call 步骤由宿主注入跨 App registry，本解释器仅承担深度计数与递归。

public enum BaseMethodStepType: String, Equatable {
    case query
    case aggregate
    case mutate
    case assert
    case call
    case reply
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
                    hint: "须为 query/aggregate/mutate/assert/call/reply"
                )
            }
            steps.append(BaseMethodStep(type: type, raw: s))
        }
        self.steps = steps
        self.exports = (json["exports"] as? Bool) ?? false
        self.readOnly = (json["readOnly"] as? Bool) ?? false
        // 只读推导：方法体仅 query/aggregate + reply（assert/call/mutate 不计入只读）。
        self.derivedReadOnly = steps.allSatisfy {
            $0.type == .query || $0.type == .aggregate || $0.type == .reply
        }
    }

    /// 有效只读：显式声明或方法体推导只读。
    public var isReadOnly: Bool { readOnly || derivedReadOnly }
}

/// 方法执行结果：reply 数据（或末步骤输出）+ warn 信号 + 变量上下文。
public struct BaseMethodResult {
    public let data: JSONValue
    public let warnings: [String]
    public let variables: [String: JSONValue]

    public init(data: JSONValue, warnings: [String], variables: [String: JSONValue]) {
        self.data = data
        self.warnings = warnings
        self.variables = variables
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
    ///   - appID: 当前 App（write 归属与错误上下文）。
    ///   - method: 方法定义。
    ///   - args: 入参（inputSchema required 校验）。
    ///   - registry: 方法名解析器（call 步骤用；同 App 与跨 App 均由宿主注入）。
    ///   - callDepth: 当前 call 深度（递归调用时 +1）。
    public func invoke(
        appID: String,
        method: BaseMethodDef,
        args: [String: Any],
        registry: (String) throws -> BaseMethodDef?,
        callDepth: Int = 0
    ) throws -> BaseMethodResult {
        try validateArgs(method: method, args: args)

        var vars: [String: JSONValue] = [:]
        var warnings: [String] = []
        var lastData: JSONValue = .object([:])

        for step in method.steps {
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
                try runAssert(step, vars: vars, warnings: &warnings)
            case .call:
                lastData = try runCall(step, appID: appID, method: method, args: args, vars: vars, registry: registry, callDepth: callDepth)
            case .reply:
                lastData = try runReply(step, vars: vars)
                // reply 为终止步骤。
                return BaseMethodResult(data: lastData, warnings: warnings, variables: vars)
            }
            if let name = step.raw["as"] as? String, !name.isEmpty {
                vars[name] = lastData
            }
        }
        return BaseMethodResult(data: lastData, warnings: warnings, variables: vars)
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

    private func runAssert(_ step: BaseMethodStep, vars: [String: JSONValue], warnings: inout [String]) throws {
        guard let on = step.raw["on"] as? [String: Any] else {
            throw BaseError(code: .validationFailed, message: "assert 步骤缺 on", hint: "assert 步骤必须携带 on 表达式")
        }
        let message = (step.raw["message"] as? String) ?? "断言不成立"
        let onFail = (step.raw["onFail"] as? String) ?? "reject"
        let passes = try evaluate(on, vars: vars)
        if !passes {
            if onFail == "warn" {
                warnings.append(message)
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
        registry: (String) throws -> BaseMethodDef?,
        callDepth: Int
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
        guard let targetMethod = try registry(target) else {
            throw BaseError(code: .notFound, message: "方法不存在", hint: target)
        }
        let result = try invoke(
            appID: appID,
            method: targetMethod,
            args: callArgs,
            registry: registry,
            callDepth: callDepth + 1
        )
        return result.data
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
        case "gt": return (lhs as? Double) ?? -Double.greatestFiniteMagnitude > (rhs as? Double) ?? -Double.greatestFiniteMagnitude
        case "gte": return (lhs as? Double) ?? -Double.greatestFiniteMagnitude >= (rhs as? Double) ?? -Double.greatestFiniteMagnitude
        case "lt": return (lhs as? Double) ?? Double.greatestFiniteMagnitude < (rhs as? Double) ?? Double.greatestFiniteMagnitude
        case "lte": return (lhs as? Double) ?? Double.greatestFiniteMagnitude <= (rhs as? Double) ?? Double.greatestFiniteMagnitude
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
