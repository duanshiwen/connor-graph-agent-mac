import XCTest
import Foundation
@testable import ConnorGraphBase

/// M2-K1：方法 DAG 解释器核心。
final class BaseMethodInterpreterTests: XCTestCase {

    private var tmpDir: URL!
    private var store: BaseSubLibraryStore!
    private var schema: BaseAppSchema!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("base-m2k1-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        store = try BaseSubLibraryStore(appID: "acct", directory: tmpDir)
        let expenses = BaseTableDef(name: "expenses", fields: [
            BaseFieldDef(name: "amount", type: "number", required: true),
            BaseFieldDef(name: "category", type: "enum", required: true, enumValues: ["food", "transport"])
        ])
        schema = BaseAppSchema(tables: [expenses])
        try store.createTable(expenses)
        // 预置两条记录（走顺序 ID，避免与 nextRecordID 序列冲突）
        try store.insert(id: try store.nextRecordID(), table: "expenses", values: [
            "amount": .number(93), "category": .string("food")
        ])
        try store.insert(id: try store.nextRecordID(), table: "expenses", values: [
            "amount": .number(50), "category": .string("transport")
        ])
    }

    override func tearDownWithError() throws {
        store?.close()
        if let tmpDir { try? FileManager.default.removeItem(at: tmpDir) }
    }

    private func makeInterpreter() -> BaseMethodInterpreter {
        BaseMethodInterpreter(store: store, schema: schema)
    }

    // MARK: 方法定义模型

    func testParsesMethodDefAndDerivesReadOnly() throws {
        let json: [String: Any] = [
            "name": "monthly.total",
            "description": "本月合计",
            "inputSchema": ["type": "object", "required": ["month"], "properties": [:]],
            "steps": [
                ["type": "aggregate", "table": "expenses", "aggregations": [["op": "sum", "field": "amount", "as": "total"]]]
            ]
        ]
        let def = try BaseMethodDef(json: json)
        XCTAssertEqual(def.name, "monthly.total")
        XCTAssertTrue(def.derivedReadOnly)
        XCTAssertTrue(def.isReadOnly)
        XCTAssertFalse(def.exports)
    }

    func testMutateStepMakesMethodNonReadOnly() throws {
        let json: [String: Any] = [
            "name": "add.expense",
            "steps": [
                ["type": "mutate", "table": "expenses", "ops": [["op": "insert", "record": ["amount": 10, "category": "food"]]]]
            ]
        ]
        let def = try BaseMethodDef(json: json)
        XCTAssertFalse(def.derivedReadOnly)
        XCTAssertFalse(def.isReadOnly)
    }

    func testRejectsUnknownStepType() {
        let json: [String: Any] = [
            "name": "bad",
            "steps": [["type": "loop", "table": "expenses"]]
        ]
        XCTAssertThrowsError(try BaseMethodDef(json: json)) { error in
            let e = error as! BaseError
            XCTAssertEqual(e.code, "VALIDATION_FAILED")
        }
    }

    func testRejectsEmptySteps() {
        let json: [String: Any] = ["name": "empty", "steps": []]
        XCTAssertThrowsError(try BaseMethodDef(json: json)) { error in
            XCTAssertEqual((error as! BaseError).code, "VALIDATION_FAILED")
        }
    }

    func testRejectsTooManySteps() {
        var steps: [[String: Any]] = []
        for i in 0..<21 {
            steps.append(["type": "query", "table": "expenses", "as": "q\(i)"])
        }
        let json: [String: Any] = ["name": "too.many", "steps": steps]
        XCTAssertThrowsError(try BaseMethodDef(json: json)) { error in
            XCTAssertEqual((error as! BaseError).code, "QUOTA_EXCEEDED")
        }
    }

    // MARK: 查询 / 聚合步骤

    func testQueryStepStoresRowsInVar() throws {
        let json: [String: Any] = [
            "name": "all.expenses",
            "steps": [
                ["type": "query", "table": "expenses", "as": "rows"],
                ["type": "reply", "template": ["count": "$rows"]]
            ]
        ]
        let def = try BaseMethodDef(json: json)
        let result = try makeInterpreter().invoke(method: def, args: [:], resolver: { _ in nil }, appID: "acct")
        guard case let .object(reply) = result.data else {
            return XCTFail("reply 应为对象")
        }
        guard case let .array(rows) = reply["count"] else {
            return XCTFail("rows 应为数组")
        }
        XCTAssertEqual(rows.count, 2)
    }

    func testAggregateStepComputesSum() throws {
        let json: [String: Any] = [
            "name": "monthly.total",
            "steps": [
                ["type": "aggregate", "table": "expenses", "aggregations": [["op": "sum", "field": "amount", "alias": "total"]], "as": "agg"],
                ["type": "reply", "template": ["total": "$agg.0.total"]]
            ]
        ]
        let def = try BaseMethodDef(json: json)
        let result = try makeInterpreter().invoke(method: def, args: [:], resolver: { _ in nil }, appID: "acct")
        guard case let .object(reply) = result.data, case let .number(total)? = reply["total"] else {
            return XCTFail("total 应为数字")
        }
        XCTAssertEqual(total, 143)
    }

    // MARK: 写步骤与只读约束

    func testMutateStepWritesAndReturnsResult() throws {
        let json: [String: Any] = [
            "name": "add.expense",
            "steps": [
                ["type": "mutate", "table": "expenses", "as": "res",
                 "ops": [["op": "insert", "record": ["amount": 10, "category": "food"]]]],
                ["type": "reply", "template": ["affected": "$res.affected"]]
            ]
        ]
        let def = try BaseMethodDef(json: json)
        let result = try makeInterpreter().invoke(method: def, args: [:], resolver: { _ in nil }, appID: "acct")
        guard case let .object(reply) = result.data, case let .number(affected)? = reply["affected"] else {
            return XCTFail("affected 应为数字")
        }
        XCTAssertEqual(affected, 1)
        let count = try store.execute("SELECT COUNT(*) AS n FROM expenses")
        XCTAssertEqual(count.first?["n"] as? Int64, 3)
    }

    func testReadOnlyMethodForbidsMutate() throws {
        let json: [String: Any] = [
            "name": "should.not.write",
            "readOnly": true,
            "steps": [
                ["type": "mutate", "table": "expenses", "ops": [["op": "insert", "record": ["amount": 1, "category": "food"]]]]
            ]
        ]
        let def = try BaseMethodDef(json: json)
        XCTAssertThrowsError(try makeInterpreter().invoke(method: def, args: [:], resolver: { _ in nil }, appID: "acct")) { error in
            let e = error as! BaseError
            XCTAssertEqual(e.code, "VALIDATION_FAILED")
            XCTAssertTrue(e.message.contains("只读方法禁止包含 mutate 步骤"))
        }
    }

    // MARK: 断言步骤

    func testAssertRejectThrows() throws {
        let json: [String: Any] = [
            "name": "assert.reject",
            "steps": [
                ["type": "aggregate", "table": "expenses", "aggregations": [["op": "sum", "field": "amount", "alias": "total"]], "as": "agg"],
                ["type": "assert", "on": ["path": "$agg.0.total", "op": "lt", "value": 100], "onFail": "reject", "message": "本月支出超 100 元"],
                ["type": "reply", "template": ["ok": true]]
            ]
        ]
        let def = try BaseMethodDef(json: json)
        XCTAssertThrowsError(try makeInterpreter().invoke(method: def, args: [:], resolver: { _ in nil }, appID: "acct")) { error in
            XCTAssertEqual((error as! BaseError).code, "VALIDATION_FAILED")
        }
    }

    func testAssertWarnCollectsSignal() throws {
        let json: [String: Any] = [
            "name": "assert.warn",
            "steps": [
                ["type": "aggregate", "table": "expenses", "aggregations": [["op": "sum", "field": "amount", "alias": "total"]], "as": "agg"],
                ["type": "assert", "on": ["path": "$agg.0.total", "op": "lte", "value": 100], "onFail": "warn", "message": "超预算信号"],
                ["type": "reply", "template": ["total": "$agg.0.total"]]
            ]
        ]
        let def = try BaseMethodDef(json: json)
        let result = try makeInterpreter().invoke(method: def, args: [:], resolver: { _ in nil }, appID: "acct")
        XCTAssertEqual(result.warnings, ["超预算信号"])
        XCTAssertEqual(result.signals.map(\.level), ["warn"])
        XCTAssertEqual(result.signals.map(\.message), ["超预算信号"])
    }

    func testMultipleWarnAssertsContinueToReply() throws {
        let json: [String: Any] = [
            "name": "multi.warn",
            "steps": [
                ["type": "aggregate", "table": "expenses", "aggregations": [["op": "sum", "field": "amount", "alias": "total"]], "as": "agg"],
                ["type": "assert", "on": ["path": "$agg.0.total", "op": "lte", "value": 100], "onFail": "warn", "message": "超预算"],
                ["type": "assert", "on": ["path": "$agg.0.total", "op": "lte", "value": 130], "onFail": "warn", "message": "严重超预算"],
                ["type": "reply", "template": ["total": "$agg.0.total"]]
            ]
        ]
        let def = try BaseMethodDef(json: json)
        let result = try makeInterpreter().invoke(method: def, args: [:], resolver: { _ in nil }, appID: "acct")
        XCTAssertEqual(result.warnings, ["超预算", "严重超预算"])
        guard case let .object(reply) = result.data, case let .number(total)? = reply["total"] else {
            return XCTFail("reply 应含 total")
        }
        XCTAssertEqual(total, 143)
    }

    func testWarnSignalPreservedAfterMutate() throws {
        let json: [String: Any] = [
            "name": "warn.after.mutate",
            "steps": [
                ["type": "mutate", "table": "expenses", "as": "res",
                 "ops": [["op": "insert", "record": ["amount": 10, "category": "food"]]]],
                ["type": "aggregate", "table": "expenses", "aggregations": [["op": "sum", "field": "amount", "alias": "total"]], "as": "agg"],
                ["type": "assert", "on": ["path": "$agg.0.total", "op": "lte", "value": 150], "onFail": "warn", "message": "已超 150"],
                ["type": "reply", "template": ["total": "$agg.0.total"]]
            ]
        ]
        let def = try BaseMethodDef(json: json)
        let result = try makeInterpreter().invoke(method: def, args: [:], resolver: { _ in nil }, appID: "acct")
        XCTAssertEqual(result.warnings, ["已超 150"])
        XCTAssertEqual(result.signals.map(\.level), ["warn"])
    }

    func testAssertNumericComparisonBoundaries() throws {
        // 回归（M2-M4 发现）：compare 曾用 `as? Double`（JSONValue 是枚举，永远 nil）
        // 导致数值比较失效——gt/lt 恒假、gte/lte 恒真。修复后须按真实数值比较。
        // 总支出 143：gt 100 通过（不 warn）、lte 142 失败（warn）、lte 143 边界通过（不 warn）。
        let json: [String: Any] = [
            "name": "numeric.boundary",
            "steps": [
                ["type": "aggregate", "table": "expenses", "aggregations": [["op": "sum", "field": "amount", "alias": "total"]], "as": "agg"],
                ["type": "assert", "on": ["path": "$agg.0.total", "op": "gt", "value": 100], "onFail": "warn", "message": "不该触发：143>100 通过"],
                ["type": "assert", "on": ["path": "$agg.0.total", "op": "lte", "value": 142], "onFail": "warn", "message": "应触发：143>142"],
                ["type": "assert", "on": ["path": "$agg.0.total", "op": "lte", "value": 143], "onFail": "warn", "message": "不该触发：143<=143 边界通过"],
                ["type": "reply", "template": ["total": "$agg.0.total"]]
            ]
        ]
        let def = try BaseMethodDef(json: json)
        let result = try makeInterpreter().invoke(method: def, args: [:], resolver: { _ in nil }, appID: "acct")
        XCTAssertEqual(result.warnings, ["应触发：143>142"])
        XCTAssertEqual(result.signals.map(\.level), ["warn"])
    }

    // MARK: 入参校验

    func testArgsRequiredValidation() throws {
        let json: [String: Any] = [
            "name": "needs.month",
            "inputSchema": ["type": "object", "required": ["month"], "properties": [:]],
            "steps": [["type": "reply", "template": ["month": "$month"]]]
        ]
        let def = try BaseMethodDef(json: json)
        XCTAssertThrowsError(try makeInterpreter().invoke(method: def, args: [:], resolver: { _ in nil }, appID: "acct")) { error in
            XCTAssertTrue((error as! BaseError).message.contains("缺必填入参"))
        }
    }

    // MARK: call 步骤（同 App 方法编排）

    func testCallStepComposesMethods() throws {
        let totalDef = try BaseMethodDef(json: [
            "name": "expenses.total",
            "steps": [
                ["type": "aggregate", "table": "expenses", "aggregations": [["op": "sum", "field": "amount", "alias": "total"]], "as": "agg"],
                ["type": "reply", "template": ["total": "$agg.0.total"]]
            ]
        ])
        let caller = try BaseMethodDef(json: [
            "name": "expenses.summary",
            "steps": [
                ["type": "call", "method": "expenses.total", "as": "inner"],
                ["type": "reply", "template": ["grand": "$inner.total"]]
            ]
        ])
        let resolver: (String) throws -> BaseMethodTarget? = { name in
            name == "expenses.total" ? BaseMethodTarget(appID: "acct", store: self.store, schema: self.schema, method: totalDef) : nil
        }
        let result = try makeInterpreter().invoke(method: caller, args: [:], resolver: resolver, appID: "acct")
        guard case let .object(reply) = result.data, case let .number(grand)? = reply["grand"] else {
            return XCTFail("grand 应为数字")
        }
        XCTAssertEqual(grand, 143)
    }

    func testCallDepthLimitEnforced() throws {
        var defs: [String: BaseMethodDef] = [:]
        let loopA = try BaseMethodDef(json: [
            "name": "a", "steps": [["type": "call", "method": "b"]]
        ])
        let loopB = try BaseMethodDef(json: [
            "name": "b", "steps": [["type": "call", "method": "a"]]
        ])
        defs["a"] = loopA
        defs["b"] = loopB
        let resolver: (String) throws -> BaseMethodTarget? = { defs[$0].map { BaseMethodTarget(appID: "acct", store: self.store, schema: self.schema, method: $0) } }
        XCTAssertThrowsError(try makeInterpreter().invoke(method: loopA, args: [:], resolver: resolver, appID: "acct")) { error in
            let e = error as! BaseError
            XCTAssertEqual(e.code, "QUOTA_EXCEEDED")
            XCTAssertTrue(e.message.contains("maxCrossAppCallDepth"))
        }
    }

    // MARK: reply 转义

    // MARK: reply 转义

    func testReplyEscapesDollar() throws {
        let json: [String: Any] = [
            "name": "escape",
            "steps": [["type": "reply", "template": ["literal": "$$money"]]]
        ]
        let def = try BaseMethodDef(json: json)
        let result = try makeInterpreter().invoke(method: def, args: [:], resolver: { _ in nil }, appID: "acct")
        guard case let .object(reply) = result.data, case let .string(literal)? = reply["literal"] else {
            return XCTFail("literal 应为字符串")
        }
        XCTAssertEqual(literal, "$money")
    }

    // MARK: M2-K4 reply 模板 / JSONPath 边界

    func testReplyMissingPathResolvesToNull() throws {
        let json: [String: Any] = [
            "name": "missing",
            "steps": [["type": "reply", "template": ["nope": "$not.there"]]]
        ]
        let def = try BaseMethodDef(json: json)
        let result = try makeInterpreter().invoke(method: def, args: [:], resolver: { _ in nil }, appID: "acct")
        guard case let .object(reply) = result.data else {
            return XCTFail("reply 应为对象")
        }
        guard case .null = reply["nope"] else {
            return XCTFail("缺失路径应解析为 null")
        }
    }

    func testReplyArrayIndexOutOfBoundsIsNull() throws {
        let json: [String: Any] = [
            "name": "bounds",
            "steps": [
                ["type": "aggregate", "table": "expenses", "aggregations": [["op": "sum", "field": "amount", "alias": "total"]], "as": "agg"],
                ["type": "reply", "template": ["x": "$agg.9.total"]]
            ]
        ]
        let def = try BaseMethodDef(json: json)
        let result = try makeInterpreter().invoke(method: def, args: [:], resolver: { _ in nil }, appID: "acct")
        guard case let .object(reply) = result.data, case .null = reply["x"] else {
            return XCTFail("越界下标应解析为 null")
        }
    }

    func testReplyNestedObjectPath() throws {
        let json: [String: Any] = [
            "name": "nested",
            "steps": [
                ["type": "query", "table": "expenses", "as": "rows"],
                ["type": "reply", "template": [
                    "firstCategory": "$rows.0.category",
                    "firstAmount": "$rows.0.amount"
                ]]
            ]
        ]
        let def = try BaseMethodDef(json: json)
        let result = try makeInterpreter().invoke(method: def, args: [:], resolver: { _ in nil }, appID: "acct")
        guard case let .object(reply) = result.data,
              case let .string(category)? = reply["firstCategory"],
              case let .number(amount)? = reply["firstAmount"] else {
            return XCTFail("嵌套投影应解析")
        }
        XCTAssertEqual(category, "food")
        XCTAssertEqual(amount, 93)
    }

    func testReplyLiteralPassthroughTypes() throws {
        let json: [String: Any] = [
            "name": "passthrough",
            "steps": [["type": "reply", "template": [
                "text": "plain",
                "num": 3.14,
                "flag": true,
                "arr": [1, "two"],
                "obj": ["inner": 42]
            ]]]
        ]
        let def = try BaseMethodDef(json: json)
        let result = try makeInterpreter().invoke(method: def, args: [:], resolver: { _ in nil }, appID: "acct")
        guard case let .object(reply) = result.data else {
            return XCTFail("reply 应为对象")
        }
        XCTAssertEqual(reply["text"], .string("plain"))
        XCTAssertEqual(reply["num"], .number(3.14))
        XCTAssertEqual(reply["flag"], .bool(true))
        XCTAssertEqual(reply["arr"], .array([.number(1), .string("two")]))
        XCTAssertEqual(reply["obj"], .object(["inner": .number(42)]))
    }

    func testReplyArrayInTemplateResolvesPaths() throws {
        let json: [String: Any] = [
            "name": "arr.tpl",
            "steps": [
                ["type": "aggregate", "table": "expenses", "aggregations": [["op": "sum", "field": "amount", "alias": "total"]], "as": "agg"],
                ["type": "reply", "template": ["series": ["$agg.0.total", "$missing"]]]
            ]
        ]
        let def = try BaseMethodDef(json: json)
        let result = try makeInterpreter().invoke(method: def, args: [:], resolver: { _ in nil }, appID: "acct")
        guard case let .object(reply) = result.data, case let .array(series)? = reply["series"] else {
            return XCTFail("series 应为数组")
        }
        XCTAssertEqual(series, [.number(143), .null])
    }

    // MARK: M2-K2 跨 App exported 调用

    /// 造一个订阅 App（subs）子库：表 subs，一条记录 amount=200。
    private func makeSubsContext() throws -> (store: BaseSubLibraryStore, schema: BaseAppSchema) {
        let subsDir = tmpDir.appendingPathComponent("subs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: subsDir, withIntermediateDirectories: true)
        let subsStore = try BaseSubLibraryStore(appID: "subs", directory: subsDir)
        let subsTable = BaseTableDef(name: "subs", fields: [
            BaseFieldDef(name: "amount", type: "number", required: true)
        ])
        let subsSchema = BaseAppSchema(tables: [subsTable])
        try subsStore.createTable(subsTable)
        try subsStore.insert(id: try subsStore.nextRecordID(), table: "subs", values: ["amount": .number(200)])
        return (subsStore, subsSchema)
    }

    func testCrossAppCallExecutesInOwnerContext() throws {
        let subs = try makeSubsContext()
        defer { subs.store.close() }
        let subsMonthly = try BaseMethodDef(json: [
            "name": "subs.monthly",
            "description": "订阅本月待扣总额",
            "exports": true,
            "steps": [
                ["type": "aggregate", "table": "subs", "aggregations": [["op": "sum", "field": "amount", "alias": "total"]], "as": "agg"],
                ["type": "reply", "template": ["total": "$agg.0.total"]]
            ]
        ])
        // acct 侧方法调用 subs.monthly，引用其返回值
        let summary = try BaseMethodDef(json: [
            "name": "acct.summary",
            "steps": [
                ["type": "call", "method": "subs.monthly", "as": "subsTotal"],
                ["type": "reply", "template": ["subsTotal": "$subsTotal.total"]]
            ]
        ])
        let resolver: (String) throws -> BaseMethodTarget? = { ref in
            if ref == "subs.monthly" {
                return BaseMethodTarget(appID: "subs", store: subs.store, schema: subs.schema, method: subsMonthly)
            }
            return nil
        }
        let result = try makeInterpreter().invoke(method: summary, args: [:], resolver: resolver, appID: "acct")
        guard case let .object(reply) = result.data, case let .number(total)? = reply["subsTotal"] else {
            return XCTFail("subsTotal 应为数字")
        }
        XCTAssertEqual(total, 200)
    }

    func testCrossAppCallRequiresExported() throws {
        let subs = try makeSubsContext()
        defer { subs.store.close() }
        let privateMethod = try BaseMethodDef(json: [
            "name": "subs.private",
            "exports": false,
            "steps": [["type": "reply", "template": ["ok": true]]]
        ])
        let caller = try BaseMethodDef(json: [
            "name": "acct.sneaky",
            "steps": [["type": "call", "method": "subs.private"]]
        ])
        let resolver: (String) throws -> BaseMethodTarget? = { ref in
            ref == "subs.private" ? BaseMethodTarget(appID: "subs", store: subs.store, schema: subs.schema, method: privateMethod) : nil
        }
        XCTAssertThrowsError(try makeInterpreter().invoke(method: caller, args: [:], resolver: resolver, appID: "acct")) { error in
            let e = error as! BaseError
            XCTAssertEqual(e.code, "PERMISSION_DENIED")
            XCTAssertTrue(e.message.contains("未导出"))
        }
    }

    func testSameAppCallDoesNotRequireExported() throws {
        let local = try BaseMethodDef(json: [
            "name": "expenses.helper",
            "exports": false,
            "steps": [
                ["type": "aggregate", "table": "expenses", "aggregations": [["op": "sum", "field": "amount", "alias": "total"]], "as": "agg"],
                ["type": "reply", "template": ["total": "$agg.0.total"]]
            ]
        ])
        let caller = try BaseMethodDef(json: [
            "name": "expenses.wrapper",
            "steps": [
                ["type": "call", "method": "expenses.helper", "as": "inner"],
                ["type": "reply", "template": ["grand": "$inner.total"]]
            ]
        ])
        let resolver: (String) throws -> BaseMethodTarget? = { ref in
            ref == "expenses.helper" ? BaseMethodTarget(appID: "acct", store: self.store, schema: self.schema, method: local) : nil
        }
        let result = try makeInterpreter().invoke(method: caller, args: [:], resolver: resolver, appID: "acct")
        guard case let .object(reply) = result.data, case let .number(grand)? = reply["grand"] else {
            return XCTFail("grand 应为数字")
        }
        XCTAssertEqual(grand, 143)
    }

    // MARK: M7 export.csv 步骤

    /// export.csv：表头 = 声明列顺序；输出 {table, rowCount, csv} 可经 `as` 入变量上下文。
    func testExportCSVStepProducesDeclaredColumnsInOrder() throws {
        let json: [String: Any] = [
            "name": "expenses.export",
            "steps": [
                ["type": "export.csv", "table": "expenses", "columns": ["category", "amount"], "as": "csv"],
                ["type": "reply", "template": ["csv": "$csv.csv", "rows": "$csv.rowCount"]]
            ]
        ]
        let def = try BaseMethodDef(json: json)
        // 契约口径：含 export.csv 步骤的方法非只读。
        XCTAssertFalse(def.isReadOnly, "含 export.csv 步骤的方法应非只读")
        let result = try makeInterpreter().invoke(method: def, args: [:], resolver: { _ in nil }, appID: "acct")
        guard case let .object(reply) = result.data,
              case let .string(csv)? = reply["csv"],
              case let .number(rows)? = reply["rows"] else {
            return XCTFail("reply 应含 csv 与 rows")
        }
        // 表头 = 声明列顺序（category 在前，非 schema 字段序）。
        XCTAssertTrue(csv.hasPrefix("category,amount\r\n"), "表头应为声明列顺序，实际: \(csv.prefix(40))")
        XCTAssertEqual(rows, 2, "rowCount 应为命中行数")
        XCTAssertTrue(csv.contains("93"))
    }

    /// export.csv：缺 columns / 未知列 → VALIDATION_FAILED。
    func testExportCSVStepRejectsUndeclaredColumn() throws {
        let missing: [String: Any] = [
            "name": "bad.export",
            "steps": [["type": "export.csv", "table": "expenses"]]
        ]
        XCTAssertThrowsError(try makeInterpreter().invoke(method: try BaseMethodDef(json: missing), args: [:], resolver: { _ in nil }, appID: "acct")) { error in
            let e = error as! BaseError
            XCTAssertEqual(e.code, "VALIDATION_FAILED")
            XCTAssertTrue(e.message.contains("缺 columns"))
        }
        let unknown: [String: Any] = [
            "name": "bad.export2",
            "steps": [["type": "export.csv", "table": "expenses", "columns": ["amount", "nonsense"]]]
        ]
        XCTAssertThrowsError(try makeInterpreter().invoke(method: try BaseMethodDef(json: unknown), args: [:], resolver: { _ in nil }, appID: "acct")) { error in
            let e = error as! BaseError
            XCTAssertEqual(e.code, "VALIDATION_FAILED")
            XCTAssertTrue(e.hint.contains("nonsense"))
        }
    }

    /// export.csv：行数超 maxRows → VALIDATION_FAILED（缺省上限为契约 maxRowsPerQuery）。
    func testExportCSVStepEnforcesMaxRows() throws {
        let json: [String: Any] = [
            "name": "capped.export",
            "steps": [["type": "export.csv", "table": "expenses", "columns": ["amount"], "maxRows": 1]]
        ]
        let def = try BaseMethodDef(json: json)
        XCTAssertThrowsError(try makeInterpreter().invoke(method: def, args: [:], resolver: { _ in nil }, appID: "acct")) { error in
            let e = error as! BaseError
            XCTAssertEqual(e.code, "VALIDATION_FAILED")
            XCTAssertTrue(e.message.contains("maxRows=1"), "应报告上限，实际: \(e.message)")
        }
    }

    /// readOnly 方法含 export.csv → 执行即拒（export.csv 非只读步骤）。
    func testReadOnlyMethodForbidsExportCSVStep() throws {
        let json: [String: Any] = [
            "name": "readonly.export",
            "readOnly": true,
            "steps": [["type": "export.csv", "table": "expenses", "columns": ["amount"]]]
        ]
        let def = try BaseMethodDef(json: json)
        XCTAssertTrue(def.readOnly, "显式 readOnly 声明应保留")
        XCTAssertFalse(def.derivedReadOnly)
        XCTAssertFalse(def.isReadOnly == false && def.readOnly == false, "isReadOnly 应为 true")
        XCTAssertThrowsError(try makeInterpreter().invoke(method: def, args: [:], resolver: { _ in nil }, appID: "acct")) { error in
            let e = error as! BaseError
            XCTAssertEqual(e.code, "VALIDATION_FAILED")
            XCTAssertTrue(e.message.contains("只读方法禁止包含 export.csv 步骤"))
        }
    }

    /// 步骤 type 枚举校验 hint 与契约/golden 22 逐字对齐（含 export.csv）。
    func testRejectsUnknownStepTypeHintMentionsExportCSV() {
        let json: [String: Any] = ["name": "bad", "steps": [["type": "frobnicate"]]]
        XCTAssertThrowsError(try BaseMethodDef(json: json)) { error in
            let e = error as! BaseError
            XCTAssertEqual(e.code, "VALIDATION_FAILED")
            XCTAssertEqual(e.message, "步骤 type 不合法")
            XCTAssertEqual(e.hint, "须为 query/aggregate/mutate/assert/call/reply/export.csv")
        }
    }

    // MARK: M7 步骤审计 + traceId 贯穿

    /// 每步一条 method.step 审计：detail JSON {traceId, methodName, surface, stepType, table, rows}；
    /// 同一次 invoke 的全部步骤共享同一 traceId。
    func testStepAuditRowsShareSingleTraceId() throws {
        let json: [String: Any] = [
            "name": "audit.report",
            "steps": [
                ["type": "aggregate", "table": "expenses", "aggregations": [["op": "sum", "field": "amount", "alias": "total"]], "as": "agg"],
                ["type": "assert", "on": ["path": "$agg.0.total", "op": "lte", "value": 100], "onFail": "warn", "message": "超 100"],
                ["type": "reply", "template": ["total": "$agg.0.total"]]
            ]
        ]
        let def = try BaseMethodDef(json: json)
        let result = try makeInterpreter().invoke(
            method: def, args: [:], resolver: { _ in nil }, appID: "acct",
            trace: BaseMethodTraceContext(traceId: "trace-xyz", methodName: "audit.report")
        )
        XCTAssertEqual(result.warnings, ["超 100"])

        let stepRows = store.readAudit(limit: 100).filter { ($0["operation"] as? String) == "method.step" }
        XCTAssertEqual(stepRows.count, 3, "三个步骤应各有一条 method.step 审计")
        var stepTypes: [String] = []
        for row in stepRows {
            let detail = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data((row["detail"] as? String ?? "").utf8)) as? [String: Any])
            XCTAssertEqual(detail["traceId"] as? String, "trace-xyz", "同一 invoke 的步骤审计应共享 traceId")
            XCTAssertEqual(detail["methodName"] as? String, "audit.report")
            XCTAssertEqual(detail["surface"] as? String, "runtime")
            stepTypes.append(detail["stepType"] as? String ?? "")
        }
        XCTAssertEqual(Set(stepTypes), ["aggregate", "assert", "reply"])
    }

    /// call 子调用继承父 traceId，methodName 换为子方法名；审计落在子方法执行上下文子库。
    func testCallChildInheritsTraceIdAndAuditsInTargetContext() throws {
        let subs = try makeSubsContext()
        defer { subs.store.close() }
        let subsMonthly = try BaseMethodDef(json: [
            "name": "subs.monthly",
            "exports": true,
            "steps": [
                ["type": "aggregate", "table": "subs", "aggregations": [["op": "sum", "field": "amount", "alias": "total"]], "as": "agg"],
                ["type": "reply", "template": ["total": "$agg.0.total"]]
            ]
        ])
        let caller = try BaseMethodDef(json: [
            "name": "acct.summary",
            "steps": [
                ["type": "call", "method": "subs.monthly", "as": "subsTotal"],
                ["type": "reply", "template": ["total": "$subsTotal.total"]]
            ]
        ])
        let resolver: (String) throws -> BaseMethodTarget? = { ref in
            ref == "subs.monthly" ? BaseMethodTarget(appID: "subs", store: subs.store, schema: subs.schema, method: subsMonthly) : nil
        }
        _ = try makeInterpreter().invoke(
            method: caller, args: [:], resolver: resolver, appID: "acct",
            trace: BaseMethodTraceContext(traceId: "trace-parent", methodName: "acct.summary")
        )

        // 父方法步骤：审计在 acct 子库，methodName=acct.summary。
        let parentRows = store.readAudit(limit: 100).filter { ($0["operation"] as? String) == "method.step" }
        XCTAssertFalse(parentRows.isEmpty)
        for row in parentRows {
            let detail = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data((row["detail"] as? String ?? "").utf8)) as? [String: Any])
            XCTAssertEqual(detail["traceId"] as? String, "trace-parent")
            XCTAssertEqual(detail["methodName"] as? String, "acct.summary")
        }
        // 子方法步骤：审计落在 subs 子库，traceId 继承，methodName 换为 subs.monthly。
        let childRows = subs.store.readAudit(limit: 100).filter { ($0["operation"] as? String) == "method.step" }
        XCTAssertEqual(childRows.count, 2, "子方法两步应各有一条审计")
        for row in childRows {
            let detail = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data((row["detail"] as? String ?? "").utf8)) as? [String: Any])
            XCTAssertEqual(detail["traceId"] as? String, "trace-parent", "跨 App 子调用应继承父 traceId")
            XCTAssertEqual(detail["methodName"] as? String, "subs.monthly")
        }
    }
}
