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
        let result = try makeInterpreter().invoke(appID: "acct", method: def, args: [:], registry: { _ in nil })
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
        let result = try makeInterpreter().invoke(appID: "acct", method: def, args: [:], registry: { _ in nil })
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
        let result = try makeInterpreter().invoke(appID: "acct", method: def, args: [:], registry: { _ in nil })
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
        XCTAssertThrowsError(try makeInterpreter().invoke(appID: "acct", method: def, args: [:], registry: { _ in nil })) { error in
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
        XCTAssertThrowsError(try makeInterpreter().invoke(appID: "acct", method: def, args: [:], registry: { _ in nil })) { error in
            XCTAssertEqual((error as! BaseError).code, "VALIDATION_FAILED")
        }
    }

    func testAssertWarnCollectsSignal() throws {
        let json: [String: Any] = [
            "name": "assert.warn",
            "steps": [
                ["type": "aggregate", "table": "expenses", "aggregations": [["op": "sum", "field": "amount", "alias": "total"]], "as": "agg"],
                ["type": "assert", "on": ["path": "$agg.0.total", "op": "gt", "value": 100], "onFail": "warn", "message": "超预算信号"],
                ["type": "reply", "template": ["total": "$agg.0.total"]]
            ]
        ]
        let def = try BaseMethodDef(json: json)
        let result = try makeInterpreter().invoke(appID: "acct", method: def, args: [:], registry: { _ in nil })
        XCTAssertEqual(result.warnings, ["超预算信号"])
    }

    // MARK: 入参校验

    func testArgsRequiredValidation() throws {
        let json: [String: Any] = [
            "name": "needs.month",
            "inputSchema": ["type": "object", "required": ["month"], "properties": [:]],
            "steps": [["type": "reply", "template": ["month": "$month"]]]
        ]
        let def = try BaseMethodDef(json: json)
        XCTAssertThrowsError(try makeInterpreter().invoke(appID: "acct", method: def, args: [:], registry: { _ in nil })) { error in
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
        let registry: (String) throws -> BaseMethodDef? = { name in
            name == "expenses.total" ? totalDef : nil
        }
        let result = try makeInterpreter().invoke(appID: "acct", method: caller, args: [:], registry: registry)
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
        let registry: (String) throws -> BaseMethodDef? = { defs[$0] }
        XCTAssertThrowsError(try makeInterpreter().invoke(appID: "acct", method: loopA, args: [:], registry: registry)) { error in
            let e = error as! BaseError
            XCTAssertEqual(e.code, "QUOTA_EXCEEDED")
            XCTAssertTrue(e.message.contains("maxCrossAppCallDepth"))
        }
    }

    // MARK: reply 转义

    func testReplyEscapesDollar() throws {
        let json: [String: Any] = [
            "name": "escape",
            "steps": [["type": "reply", "template": ["literal": "$$money"]]]
        ]
        let def = try BaseMethodDef(json: json)
        let result = try makeInterpreter().invoke(appID: "acct", method: def, args: [:], registry: { _ in nil })
        guard case let .object(reply) = result.data, case let .string(literal)? = reply["literal"] else {
            return XCTFail("literal 应为字符串")
        }
        XCTAssertEqual(literal, "$money")
    }
}
