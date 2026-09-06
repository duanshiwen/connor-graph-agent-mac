import XCTest
import Foundation
@testable import ConnorGraphBase

/// M1-K5：写入口 record.mutate（原子批、dryRun、幂等、约束校验、乐观并发）。
final class BaseRecordMutatorTests: XCTestCase {

    private var tmpDir: URL!
    private var store: BaseSubLibraryStore!
    private var mutator: BaseRecordMutator!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("base-k5-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        store = try BaseSubLibraryStore(appID: "acct", directory: tmpDir)
        let categories = BaseTableDef(name: "categories", fields: [
            BaseFieldDef(name: "name", type: "text", required: true, unique: true)
        ])
        let expenses = BaseTableDef(name: "expenses", fields: [
            BaseFieldDef(name: "amount", type: "number", required: true, min: 0, max: 10000),
            BaseFieldDef(name: "category", type: "enum", required: true, enumValues: ["food", "transport", "home"]),
            BaseFieldDef(name: "note", type: "text", pattern: "^[a-z0-9 ]+$"),
            BaseFieldDef(name: "paid", type: "boolean"),
            BaseFieldDef(name: "cat_ref", type: "relation", relation: BaseRelationTarget(table: "categories", on: "id"))
        ])
        let schema = BaseAppSchema(tables: [categories, expenses])
        try store.createTable(categories)
        try store.createTable(expenses)
        mutator = BaseRecordMutator(store: store, schema: schema)
    }

    override func tearDownWithError() throws {
        store?.close()
        if let tmpDir { try? FileManager.default.removeItem(at: tmpDir) }
    }

    func testInsertAndFetch() throws {
        let r = try mutator.mutate(appID: "acct", table: "expenses", ops: [[
            "op": "insert",
            "id": "e1",
            "record": ["amount": 360, "category": "food", "paid": true]
        ]])
        XCTAssertEqual(r["affected"] as? Int, 1)
        let row = try store.fetch(id: "e1", table: "expenses")
        XCTAssertEqual(row?["amount"], .number(360))
        XCTAssertEqual(row?["paid"], .bool(true))
    }

    func testSequentialIDsGenerated() throws {
        let r = try mutator.mutate(appID: "acct", table: "expenses", ops: [
            ["op": "insert", "record": ["amount": 1, "category": "food"]],
            ["op": "insert", "record": ["amount": 2, "category": "food"]],
            ["op": "insert", "record": ["amount": 3, "category": "food"]]
        ])
        XCTAssertEqual(r["affected"] as? Int, 3)
        XCTAssertEqual(r["ids"] as? [String], ["rec_1", "rec_2", "rec_3"])
    }

    func testRequiredFieldEnforced() {
        XCTAssertThrowsError(try mutator.mutate(appID: "acct", table: "expenses", ops: [[
            "op": "insert", "record": ["amount": 10]
        ]])) { error in
            let e = error as! BaseError
            XCTAssertEqual(e.code, "VALIDATION_FAILED")
            XCTAssertTrue(e.message.contains("必填字段缺失"))
        }
    }

    func testRangeEnumPatternRelationValidated() throws {
        // 先建关联目标
        _ = try mutator.mutate(appID: "acct", table: "categories", ops: [[
            "op": "insert", "id": "c1", "record": ["name": "餐饮"]
        ]])
        // enum 非法
        XCTAssertThrowsError(try mutator.mutate(appID: "acct", table: "expenses", ops: [[
            "op": "insert", "record": ["amount": 1, "category": "travel"]
        ]]))
        // range 超限
        XCTAssertThrowsError(try mutator.mutate(appID: "acct", table: "expenses", ops: [[
            "op": "insert", "record": ["amount": 99999, "category": "food"]
        ]]))
        // pattern 不匹配
        XCTAssertThrowsError(try mutator.mutate(appID: "acct", table: "expenses", ops: [[
            "op": "insert", "record": ["amount": 1, "category": "food", "note": "大写ABC"]
        ]]))
        // relation 目标不存在
        XCTAssertThrowsError(try mutator.mutate(appID: "acct", table: "expenses", ops: [[
            "op": "insert", "record": ["amount": 1, "category": "food", "cat_ref": "ghost"]
        ]]))
        // 合法写入
        _ = try mutator.mutate(appID: "acct", table: "expenses", ops: [[
            "op": "insert", "id": "e1", "record": ["amount": 1, "category": "food", "note": "abc 123", "cat_ref": "c1"]
        ]])
        XCTAssertNotNil(try store.fetch(id: "e1", table: "expenses"))
    }

    func testOptimisticConcurrency() throws {
        _ = try mutator.mutate(appID: "acct", table: "expenses", ops: [[
            "op": "insert", "id": "e1", "record": ["amount": 1, "category": "food"]
        ]])
        // 版本 1 匹配 → 成功
        _ = try mutator.mutate(appID: "acct", table: "expenses", ops: [[
            "op": "update", "id": "e1", "record": ["amount": 2], "expectedVersion": 1
        ]])
        // 版本过期 → CONFLICT
        XCTAssertThrowsError(try mutator.mutate(appID: "acct", table: "expenses", ops: [[
            "op": "update", "id": "e1", "record": ["amount": 3], "expectedVersion": 1
        ]])) { error in
            let e = error as! BaseError
            XCTAssertEqual(e.code, "CONFLICT")
        }
        // 无 expectedVersion → 成功
        _ = try mutator.mutate(appID: "acct", table: "expenses", ops: [[
            "op": "update", "id": "e1", "record": ["amount": 3]
        ]])
    }

    func testDryRunDoesNotWrite() throws {
        let r = try mutator.mutate(appID: "acct", table: "expenses", ops: [[
            "op": "insert", "id": "e1", "record": ["amount": 1, "category": "food"]
        ]], dryRun: true)
        XCTAssertEqual(r["wouldAffect"] as? Int, 1)
        XCTAssertEqual(r["dryRun"] as? Bool, true)
        XCTAssertNil(try store.fetch(id: "e1", table: "expenses"))
    }

    func testIdempotencyKey() throws {
        let op: [String: Any] = ["op": "insert", "id": "e1", "record": ["amount": 1, "category": "food"]]
        let first = try mutator.mutate(appID: "acct", table: "expenses", ops: [op], idempotencyKey: "key-1")
        let second = try mutator.mutate(appID: "acct", table: "expenses", ops: [op], idempotencyKey: "key-1")
        XCTAssertEqual(first["ids"] as? [String], second["ids"] as? [String])
        // 幂等不重复写入
        let rows = try store.execute("SELECT COUNT(*) AS n FROM expenses")
        XCTAssertEqual((rows.first?["n"] as? Int64), 1)
    }

    func testBatchAtomicRollback() throws {
        XCTAssertThrowsError(try mutator.mutate(appID: "acct", table: "expenses", ops: [
            ["op": "insert", "id": "e1", "record": ["amount": 1, "category": "food"]],
            ["op": "insert", "id": "e2", "record": ["amount": -5, "category": "food"]]  // range 失败
        ]))
        XCTAssertNil(try store.fetch(id: "e1", table: "expenses"), "批中失败应整体回滚")
    }

    func testUniqueConflict() throws {
        _ = try mutator.mutate(appID: "acct", table: "categories", ops: [[
            "op": "insert", "id": "c1", "record": ["name": "餐饮"]
        ]])
        XCTAssertThrowsError(try mutator.mutate(appID: "acct", table: "categories", ops: [[
            "op": "insert", "id": "c2", "record": ["name": "餐饮"]
        ]])) { error in
            let e = error as! BaseError
            XCTAssertEqual(e.code, "CONFLICT")
        }
    }

    func testDelete() throws {
        _ = try mutator.mutate(appID: "acct", table: "expenses", ops: [[
            "op": "insert", "id": "e1", "record": ["amount": 1, "category": "food"]
        ]])
        let r = try mutator.mutate(appID: "acct", table: "expenses", ops: [["op": "delete", "id": "e1"]])
        XCTAssertEqual(r["affected"] as? Int, 1)
        XCTAssertNil(try store.fetch(id: "e1", table: "expenses"))
    }
}
