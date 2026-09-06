import Foundation

/// M1-K8：golden 全量执行器。
///
/// 读入 M0-3 canonical fixture（`testdata/base/golden/*.json`，Mac 拷贝在
/// `Tests/ConnorGraphBaseTests/Golden/`），在真实内核上逐条执行并产出契约
/// envelope，与 `then` 逐字段比对（README 动态字段规则：traceId 仅断言存在、
/// site 若出现须一致、sync 若出现须 pending>=0）。
public enum BaseGoldenRunner {

    // MARK: - Fixture 模型（与 canonical fixture 结构对齐）

    public struct Fixture: Decodable {
        public let name: String

        public struct Given: Decodable {
            public let schema: [String: JSONValue]?
            public let methods: JSONValue?
            public let input: Input
            public let appContext: AppContext?
        }
        public struct Input: Decodable {
            public let tool: String
            public let args: [String: JSONValue]
        }
        public struct AppContext: Decodable {
            public let appID: String
            public let visibility: String?
            public let packageVersion: Int?
        }
        public struct Then: Decodable {
            public let envelope: [String: JSONValue]
            public let errorCode: String?
        }

        public let given: Given
        public let then: Then
    }

    /// 配额常量：跨 App 调用深度上限（§3.3/§5.3）。
    public static let maxCrossAppCallDepth = 5

    // MARK: - 执行

    /// 在指定目录上执行 fixture，返回契约 envelope 字典（与 `BaseEnvelope.asDictionary` 同形）。
    public static func execute(_ fixture: Fixture, in directory: URL) throws -> [String: Any] {
        let appID = fixture.given.appContext?.appID ?? "acct"
        let store = try BaseSubLibraryStore(appID: appID, directory: directory)
        defer { store.close() }

        let tool = fixture.given.input.tool
        let args = JSONValue.object(fixture.given.input.args).jsonObject as? [String: Any] ?? [:]

        do {
            // 预置 schema 表（app.create 除外：由工具本身建库建表）。
            // relation 目标表存在性是结构期（app.create/app.update）不变量，读/写执行期不复校验：
            // fixture 的 given.schema 是查询所需的部分快照，允许 relation 目标表未随附。
            if let schemaJSON = fixture.given.schema {
                let appSchema = try BaseSchemaValidator.parseSchema(
                    JSONValue.object(schemaJSON).jsonObject as? [String: Any] ?? [:],
                    validateRelations: tool == "base.app.create" || tool == "base.table.create"
                )
                if tool != "base.app.create" {
                    for table in appSchema.tables {
                        try store.createTable(table)
                    }
                }
            }

            let data: Any?
            switch tool {
            case "base.app.create":
                data = try appCreate(args, store: store)
            case "base.table.create":
                data = try tableCreate(args, store: store)
            case "base.query.select":
                data = try querySelect(args, store: store, schema: fixture.given.schema)
            case "base.record.mutate":
                data = try recordMutate(args, store: store, schema: fixture.given.schema)
            case "base.method.define":
                data = try methodDefine(args)
            case "base.method.invoke":
                data = try methodInvoke(args, methods: fixture.given.methods)
            default:
                throw BaseError(code: .internal, message: "未知工具", hint: tool)
            }
            return BaseEnvelope.success(data: data).asDictionary()
        } catch let error as BaseSchemaValidator.ValidationError {
            // schema 校验错误 → VALIDATION_FAILED 信封（错误文本与 golden 02-05 逐字对齐）。
            let reason = error.reason
            return BaseEnvelope.failure(
                BaseError(code: .validationFailed, message: reason.message, hint: reason.hint)
            ).asDictionary()
        } catch let error as BaseError {
            return BaseEnvelope.failure(error).asDictionary()
        } catch {
            let e = BaseError(code: .internal, message: "内部错误", hint: String(describing: error))
            return BaseEnvelope.failure(e).asDictionary()
        }
    }

    // MARK: - 工具分派

    private static func appCreate(_ args: [String: Any], store: BaseSubLibraryStore) throws -> Any {
        guard let manifest = args["manifest"] as? [String: Any],
              let appID = manifest["appID"] as? String else {
            throw BaseError(code: .validationFailed, message: "manifest/appID 缺失", hint: "app.create 必须携带 manifest.appID")
        }
        guard let schemaJSON = args["schema"] as? [String: Any] else {
            throw BaseError(code: .validationFailed, message: "schema 缺失", hint: "app.create 必须携带 schema")
        }
        let schema = try BaseSchemaValidator.parseSchema(schemaJSON)
        for table in schema.tables {
            try store.createTable(table)
        }
        let next = (try store.latestPackageVersion()) + 1
        try store.advancePackageVersion(to: next)
        return ["appID": appID, "packageVersion": next]
    }

    private static func tableCreate(_ args: [String: Any], store: BaseSubLibraryStore) throws -> Any {
        guard let tableJSON = args["table"] as? [String: Any] else {
            throw BaseError(code: .validationFailed, message: "table 缺失", hint: "table.create 必须携带 table")
        }
        let table = try BaseSchemaValidator.parseTable(tableJSON)
        try store.createTable(table)
        return [:]
    }

    private static func querySelect(_ args: [String: Any], store: BaseSubLibraryStore, schema: [String: JSONValue]?) throws -> Any {
        guard let table = args["table"] as? String else {
            throw BaseError(code: .validationFailed, message: "table 缺失", hint: "query.select 必须携带 table")
        }
        let appSchema = try schema.map {
            try BaseSchemaValidator.parseSchema(
                JSONValue.object($0).jsonObject as? [String: Any] ?? [:],
                validateRelations: false
            ) as BaseAppSchema
        }
        guard let appSchema else {
            throw BaseError(code: .notFound, message: "App 无 schema", hint: "先创建 App")
        }
        let executor = BaseQueryExecutor(store: store, table: table, schema: appSchema)
        let rows = try executor.select(
            filter: args["filter"] as? [String: Any],
            sort: args["sort"] as? [[String: Any]],
            page: args["page"] as? [String: Any]
        )
        return ["rows": rows]
    }

    private static func recordMutate(_ args: [String: Any], store: BaseSubLibraryStore, schema: [String: JSONValue]?) throws -> Any {
        guard let table = args["table"] as? String else {
            throw BaseError(code: .validationFailed, message: "table 缺失", hint: "record.mutate 必须携带 table")
        }
        let appSchema = try schema.map {
            try BaseSchemaValidator.parseSchema(
                JSONValue.object($0).jsonObject as? [String: Any] ?? [:],
                validateRelations: false
            ) as BaseAppSchema
        }
        guard let appSchema else {
            throw BaseError(code: .notFound, message: "App 无 schema", hint: "先创建 App")
        }
        guard let ops = args["ops"] as? [[String: Any]] else {
            throw BaseError(code: .validationFailed, message: "ops 缺失", hint: "record.mutate 必须携带 ops")
        }
        let mutator = BaseRecordMutator(store: store, schema: appSchema)
        return try mutator.mutate(
            appID: (args["appID"] as? String) ?? "acct",
            table: table,
            ops: ops,
            dryRun: (args["dryRun"] as? Bool) ?? false,
            idempotencyKey: args["idempotencyKey"] as? String
        )
    }

    /// 方法定义校验（golden 19）：readOnly 方法禁止 mutate 步骤。
    /// M2-K1 起由完整方法 DAG 模型接管定义与解释。
    private static func methodDefine(_ args: [String: Any]) throws -> Any {
        guard let method = args["method"] as? [String: Any] else {
            throw BaseError(code: .validationFailed, message: "method 缺失", hint: "method.define 必须携带 method")
        }
        let readOnly = (method["readOnly"] as? Bool) ?? false
        if readOnly {
            let steps = method["steps"] as? [[String: Any]] ?? []
            if steps.contains(where: { ($0["type"] as? String) == "mutate" }) {
                throw BaseError(code: .validationFailed,
                                message: "只读方法禁止包含 mutate 步骤",
                                hint: "readOnly 方法体仅允许 query/aggregate + reply")
            }
        }
        return [:]
    }

    /// 最小方法解释器（golden 20）：仅实现 call 步骤递归与深度上限，
    /// 锁定「跨 App 调用深度超限」契约语义；M2-K1 完整解释器接管。
    private static func methodInvoke(_ args: [String: Any], methods: JSONValue?) throws -> Any {
        guard let methodName = args["method"] as? String else {
            throw BaseError(code: .validationFailed, message: "method 缺失", hint: "method.invoke 必须携带 method")
        }
        let list: [Any]
        if case let .array(items)? = methods {
            list = items.map { $0.jsonObject }
        } else {
            list = []
        }
        try invokeCallDepth(methodName, in: list, depth: 0)
        return [:]
    }

    private static func invokeCallDepth(_ name: String, in methods: [Any], depth: Int) throws {
        guard depth <= maxCrossAppCallDepth else {
            throw BaseError(code: .quotaExceeded,
                            message: "跨 App 调用深度超过 maxCrossAppCallDepth=\(maxCrossAppCallDepth)",
                            hint: "检查方法 DAG 的 call 步骤链路")
        }
        guard let method = methods.first(where: { ($0 as? [String: Any])?["name"] as? String == name }) as? [String: Any] else {
            throw BaseError(code: .notFound, message: "方法不存在", hint: name)
        }
        for step in (method["steps"] as? [[String: Any]]) ?? [] {
            if (step["type"] as? String) == "call" {
                try invokeCallDepth(step["method"] as? String ?? name, in: methods, depth: depth + 1)
            }
        }
    }

    // MARK: - 比对

    /// 比对实际 envelope 与 `then`（nil = 通过；否则为失败原因）。
    public static func compare(actual: [String: Any], expected: Fixture.Then) -> String? {
        let expectedEnv = JSONValue.object(expected.envelope).jsonObject as? [String: Any] ?? [:]
        var projection: [String: Any] = [:]
        for key in expectedEnv.keys {
            switch key {
            case "traceId":
                guard let t = actual["traceId"] as? String, !t.isEmpty else {
                    return "traceId 缺失或非字符串"
                }
            case "sync":
                guard let sync = actual["sync"] as? [String: Any],
                      let pending = sync["pending"] as? Int, pending >= 0 else {
                    return "sync 缺失或 pending 非法"
                }
            case "data", "error":
                projection[key] = actual[key] ?? NSNull()
            default:
                projection[key] = actual[key]
            }
        }
        let expectedJSON = canonicalJSON(expectedEnv)
        let actualJSON = canonicalJSON(projection)
        guard actualJSON == expectedJSON else {
            return "信封不一致\n  期望: \(expectedJSON ?? "?")\n  实际: \(actualJSON ?? "?")"
        }
        if let errorCode = expected.errorCode, !errorCode.isEmpty {
            let actualCode = (actual["error"] as? [String: Any])?["code"] as? String
            guard actualCode == errorCode else {
                return "errorCode 不一致：期望 \(errorCode)，实际 \(actualCode ?? "nil")"
            }
        }
        return nil
    }

    private static func canonicalJSON(_ object: Any) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object,
                                                     options: [.sortedKeys, .fragmentsAllowed]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
