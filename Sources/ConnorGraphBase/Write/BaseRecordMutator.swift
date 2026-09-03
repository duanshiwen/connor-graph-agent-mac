import Foundation

/// M1-K5：写入口 `base.record.mutate` 内核实现。
///
/// 契约语义（base.sdk.v1.json）：
/// - ops 有序、单事务原子批；
/// - dryRun：只校验不写入，返回 diff；
/// - idempotencyKey：同 key 重复请求返回首次响应（本地 `base_idempotency` 表，不同步）；
/// - 约束校验（required/unique/range/pattern/enum/relation 目标存在）与值类型校验在写入层强制；
/// - 乐观并发：update/delete 可带 expectedVersion，与 `_meta.version` 比对，不匹配返 `CONFLICT`。
public struct BaseRecordMutator {

    public let store: BaseSubLibraryStore
    public let schema: BaseAppSchema

    public struct DiffItem: Encodable, Equatable {
        public let op: String
        public let id: String
    }

    public init(store: BaseSubLibraryStore, schema: BaseAppSchema) {
        self.store = store
        self.schema = schema
    }

    public func mutate(
        appID: String,
        table: String,
        ops: [[String: Any]],
        dryRun: Bool = false,
        idempotencyKey: String? = nil
    ) throws -> [String: Any] {
        guard try store.tableExists(table) else {
            throw BaseError(code: .notFound, message: "表不存在", hint: "子库无表 \(table)")
        }
        guard let tableDef = schema.table(named: table) else {
            throw BaseError(code: .notFound, message: "表不存在于 schema", hint: "schema 无表 \(table)")
        }
        _ = try BaseNameResolver.resolveTable(table, in: appID)
        guard !ops.isEmpty else {
            throw BaseError(code: .validationFailed, message: "ops 为空", hint: "ops 至少一项")
        }

        // 幂等：命中直接返回首次响应。
        if let key = idempotencyKey, !key.isEmpty {
            if let cached = try store.idempotencyResponse(for: key) {
                return cached
            }
        }

        var diff: [DiffItem] = []
        let response = try store.withTransaction {
            for rawOp in ops {
                guard let op = rawOp["op"] as? String else {
                    throw BaseError(code: .validationFailed, message: "op 缺失", hint: "op 须为 insert/update/delete")
                }
                switch op {
                case "insert":
                    let id = try insertOp(rawOp, tableDef: tableDef, dryRun: dryRun)
                    diff.append(DiffItem(op: "insert", id: id))
                case "update":
                    let id = try updateOp(rawOp, tableDef: tableDef, dryRun: dryRun)
                    diff.append(DiffItem(op: "update", id: id))
                case "delete":
                    let id = try deleteOp(rawOp, tableDef: tableDef, dryRun: dryRun)
                    diff.append(DiffItem(op: "delete", id: id))
                default:
                    throw BaseError(code: .validationFailed, message: "op 不合法", hint: "op 须为 insert/update/delete")
                }
            }
            var result: [String: Any] = [
                "applied": dryRun ? 0 : diff.count,
                "dryRun": dryRun,
                "diff": diff.map { ["op": $0.op, "id": $0.id] },
                "ids": diff.map { $0.id }
            ]
            if dryRun {
                result["dryRunPreview"] = true
            }
            return result
        }

        if let key = idempotencyKey, !key.isEmpty, !dryRun {
            try store.saveIdempotency(key: key, response: response)
        }
        return response
    }

    // MARK: op 执行

    private func insertOp(_ raw: [String: Any], tableDef: BaseTableDef, dryRun: Bool) throws -> String {
        guard let record = raw["record"] as? [String: Any] else {
            throw BaseError(code: .validationFailed, message: "insert 缺 record", hint: "insert op 必须携带 record 对象")
        }
        let id = (raw["id"] as? String) ?? UUID().uuidString.lowercased()
        let values = try validatedValues(record, tableDef: tableDef, forUpdate: false, existingId: nil)
        if !dryRun {
            let meta = baseMeta(version: 1)
            try store.insert(id: id, table: tableDef.name, values: values, meta: meta)
        }
        return id
    }

    private func updateOp(_ raw: [String: Any], tableDef: BaseTableDef, dryRun: Bool) throws -> String {
        guard let id = raw["id"] as? String else {
            throw BaseError(code: .validationFailed, message: "update 缺 id", hint: "update op 必须携带 id")
        }
        let existing = try store.fetch(id: id, table: tableDef.name)
        guard existing != nil else {
            throw BaseError(code: .notFound, message: "记录不存在", hint: "无法更新不存在的记录 \(id)")
        }
        try checkExpectedVersion(raw, table: tableDef.name, id: id)
        let record = (raw["record"] as? [String: Any]) ?? [:]
        let values = try validatedValues(record, tableDef: tableDef, forUpdate: true, existingId: id)
        if !dryRun {
            let newVersion = (try version(of: id, table: tableDef.name) ?? 1) + 1
            let meta = baseMeta(version: newVersion)
            try store.update(id: id, table: tableDef.name, values: values, meta: meta)
        }
        return id
    }

    private func deleteOp(_ raw: [String: Any], tableDef: BaseTableDef, dryRun: Bool) throws -> String {
        guard let id = raw["id"] as? String else {
            throw BaseError(code: .validationFailed, message: "delete 缺 id", hint: "delete op 必须携带 id")
        }
        let existing = try store.fetch(id: id, table: tableDef.name)
        guard existing != nil else {
            throw BaseError(code: .notFound, message: "记录不存在", hint: "无法删除不存在的记录 \(id)")
        }
        try checkExpectedVersion(raw, table: tableDef.name, id: id)
        if !dryRun {
            try store.delete(id: id, table: tableDef.name)
        }
        return id
    }

    // MARK: 校验

    /// 从 `_meta` JSON 列读取版本（乐观并发字段）。
    private func checkExpectedVersion(_ raw: [String: Any], table: String, id: String) throws {
        guard let expected = raw["expectedVersion"] as? Int else { return }
        let current = try version(of: id, table: table)
        guard let current, current == expected else {
            throw BaseError(code: .conflict,
                            message: "记录版本冲突",
                            hint: "期望版本 \(expected)，当前 \(current.map(String.init) ?? "无")")
        }
    }

    private func version(of id: String, table: String) throws -> Int? {
        let rows = try store.execute("SELECT _meta FROM \"\(table)\" WHERE id = ?1", parameters: [id])
        guard let raw = rows.first?["_meta"] as? String,
              let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let v = obj["version"] as? Int else {
            return nil
        }
        return Int(v)
    }

    private func baseMeta(version: Int) -> [String: Any] {
        ["version": version, "createdAt": BaseTime.isoNow(), "updatedAt": BaseTime.isoNow()]
    }

    private func validatedValues(
        _ record: [String: Any],
        tableDef: BaseTableDef,
        forUpdate: Bool,
        existingId: String?
    ) throws -> [String: JSONValue] {
        var out: [String: JSONValue] = [:]
        var fieldByName: [String: BaseFieldDef] = [:]
        for f in tableDef.fields { fieldByName[f.name] = f }

        // 类型/约束校验。
        for (key, rawValue) in record {
            guard let field = fieldByName[key] else {
                throw BaseError(code: .validationFailed,
                                message: "字段不存在",
                                hint: "表 \(tableDef.name) 不含字段 \(key)")
            }
            guard let json = JSONValue(json: rawValue) else {
                throw BaseError(code: .validationFailed, message: "字段值无法解析", hint: key)
            }
            try validateValue(json, for: field, tableDef: tableDef)
            if json == .null { continue } // null 视为未设置
            out[key] = json
        }

        // required：写入层强制（update 时已存在记录，只检查提供的新值）。
        if !forUpdate {
            for field in tableDef.fields where field.required {
                guard out[field.name] != nil else {
                    throw BaseError(code: .validationFailed,
                                    message: "必填字段缺失",
                                    hint: "\(field.name) 为必填字段")
                }
            }
        }

        // unique：冲突检测（排除自身）。
        for field in tableDef.fields where field.unique {
            guard let value = out[field.name] else { continue }
            try checkUnique(value, field: field, tableDef: tableDef, existingId: existingId)
        }
        return out
    }

    private func validateValue(_ json: JSONValue, for field: BaseFieldDef, tableDef: BaseTableDef) throws {
        switch field.type {
        case "text":
            guard case .string = json else {
                throw typeError(field)
            }
            if let pattern = field.pattern, case .string(let s) = json {
                guard Self.matches(pattern, s) else {
                    throw BaseError(code: .validationFailed,
                                    message: "字段值不符合 pattern",
                                    hint: "\(field.name) 须匹配 \(pattern)")
                }
            }
        case "number":
            guard case .number(let n) = json else {
                throw typeError(field)
            }
            if let min = field.min, n < min {
                throw BaseError(code: .validationFailed, message: "字段值低于下限", hint: "\(field.name) 不得小于 \(min)")
            }
            if let max = field.max, n > max {
                throw BaseError(code: .validationFailed, message: "字段值超过上限", hint: "\(field.name) 不得大于 \(max)")
            }
        case "boolean":
            guard case .bool = json else { throw typeError(field) }
        case "date":
            guard case .string = json else { throw typeError(field) }
        case "enum":
            guard case .string(let s) = json else { throw typeError(field) }
            if let allowed = field.enumValues, !allowed.isEmpty, !allowed.contains(s) {
                throw BaseError(code: .validationFailed,
                                message: "枚举值不合法",
                                hint: "\(field.name) 允许值：\(allowed.joined(separator: "/"))")
            }
        case "relation":
            guard case .string(let targetID) = json else { throw typeError(field) }
            if let rel = field.relation {
                let rows = try store.execute("SELECT id FROM \"\(rel.table)\" WHERE id = ?1", parameters: [targetID])
                guard !rows.isEmpty else {
                    throw BaseError(code: .validationFailed,
                                    message: "关系目标不存在",
                                    hint: "\(rel.table) 无记录 \(targetID)")
                }
            }
        case "asset":
            guard case .string = json else { throw typeError(field) }
        default:
            break
        }
    }

    private func checkUnique(_ value: JSONValue, field: BaseFieldDef, tableDef: BaseTableDef, existingId: String?) throws {
        let rows: [[String: Any]]
        if let existingId {
            rows = try store.execute(
                "SELECT id FROM \"\(tableDef.name)\" WHERE \"\(field.name)\" = ?1 AND id != ?2",
                parameters: [storeBindValue(value), existingId]
            )
        } else {
            rows = try store.execute(
                "SELECT id FROM \"\(tableDef.name)\" WHERE \"\(field.name)\" = ?1",
                parameters: [storeBindValue(value)]
            )
        }
        guard rows.isEmpty else {
            throw BaseError(code: .conflict, message: "唯一字段冲突", hint: "\(field.name) 已存在相同值")
        }
    }

    private func storeBindValue(_ value: JSONValue) -> Any {
        switch value {
        case .string(let s): return s
        case .number(let n): return n
        case .bool(let b): return b ? 1 : 0
        default: return NSNull()
        }
    }

    private func typeError(_ field: BaseFieldDef) -> BaseError {
        BaseError(code: .validationFailed,
                  message: "字段值类型不合法",
                  hint: "\(field.name) 应为 \(field.type) 类型")
    }

    private static func matches(_ pattern: String, _ s: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        return regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }
}
