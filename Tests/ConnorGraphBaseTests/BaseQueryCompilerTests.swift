import XCTest
import Foundation
@testable import ConnorGraphBase

/// M1-K4：结构化查询编译器 + 执行器（参数化 SQL、操作符收口、聚合、lookup）。
final class BaseQueryCompilerTests: XCTestCase {

    private var tmpDir: URL!
    private var store: BaseSubLibraryStore!
    private var schema: BaseAppSchema!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("base-k4-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        store = try BaseSubLibraryStore(appID: "acct", directory: tmpDir)
        let expenses = BaseTableDef(name: "expenses", fields: [
            BaseFieldDef(name: "amount", type: "number"),
            BaseFieldDef(name: "category", type: "enum", enumValues: ["food", "transport", "home"]),
            BaseFieldDef(name: "paid", type: "boolean"),
            BaseFieldDef(name: "spent_on", type: "date"),
            BaseFieldDef(name: "note", type: "text"),
            BaseFieldDef(name: "owner", type: "relation", relation: BaseRelationTarget(table: "members", on: "id"))
        ])
        let members = BaseTableDef(name: "members", fields: [
            BaseFieldDef(name: "name", type: "text")
        ])
        schema = BaseAppSchema(tables: [expenses, members])
        try store.createTable(expenses)
        try store.createTable(members)
        try store.insert(id: "m1", table: "members", values: ["name": .string("阿诗")])
        try store.insert(id: "r1", table: "expenses", values: [
            "amount": .number(93), "category": .string("food"), "paid": .bool(true),
            "spent_on": .string("2026-09-01"), "note": .string("火锅 100% 实付"), "owner": .string("m1")
        ])
        try store.insert(id: "r2", table: "expenses", values: [
            "amount": .number(50), "category": .string("transport"), "paid": .bool(false),
            "spent_on": .string("2026-09-02"), "note": .string("打车"), "owner": .string("m1")
        ])
        try store.insert(id: "r3", table: "expenses", values: [
            "amount": .number(200), "category": .string("food"), "paid": .bool(true),
            "spent_on": .string("2026-08-20"), "note": .string("上月聚餐"), "owner": .string("m1")
        ])
    }

    override func tearDownWithError() throws {
        store?.close()
        if let tmpDir { try? FileManager.default.removeItem(at: tmpDir) }
    }

    private var executor: BaseQueryExecutor {
        BaseQueryExecutor(store: store, table: "expenses", schema: schema)
    }

    // MARK: 编译正确性

    func testFilterAndOrCompilation() throws {
        let compiler = BaseQueryCompiler(table: "expenses", fields: store.fields(of: "expenses"))
        let filter: [String: Any] = [
            "and": [
                ["field": "category", "op": "in", "value": ["food"]],
                ["or": [
                    ["field": "amount", "op": "gte", "value": 90],
                    ["field": "paid", "op": "eq", "value": true]
                ]]
            ]
        ]
        let compiled = try compiler.compileSelect(filter: filter, sort: nil, page: nil)
        XCTAssertTrue(compiled.sql.contains("\"category\" IN (?)"))
        XCTAssertTrue(compiled.sql.contains("\"amount\" >="))
        XCTAssertTrue(compiled.sql.contains("(\"category\" IN (?) AND (\"amount\" >= ? OR \"paid\" = ?))"))
        XCTAssertEqual(compiled.parameters.count, 3)
    }

    func testContainsEscapesLikeWildcards() throws {
        let compiler = BaseQueryCompiler(table: "expenses", fields: store.fields(of: "expenses"))
        let compiled = try compiler.compileSelect(
            filter: ["field": "note", "op": "contains", "value": "100%"], sort: nil, page: nil
        )
        XCTAssertTrue(compiled.sql.contains("LIKE ? ESCAPE '\\'"))
        XCTAssertEqual(compiled.parameters.first as? String, "%100\\%")
    }

    func testOperatorTypeMismatchRejected() {
        let compiler = BaseQueryCompiler(table: "expenses", fields: store.fields(of: "expenses"))
        // contains 只允许 text；amount 是 number。
        XCTAssertThrowsError(try compiler.compileSelect(
            filter: ["field": "amount", "op": "contains", "value": "x"], sort: nil, page: nil
        )) { error in
            let e = error as! BaseError
            XCTAssertEqual(e.code, "VALIDATION_FAILED")
        }
    }

    func testUnknownFieldRejected() {
        let compiler = BaseQueryCompiler(table: "expenses", fields: store.fields(of: "expenses"))
        XCTAssertThrowsError(try compiler.compileSelect(
            filter: ["field": "ghost", "op": "eq", "value": 1], sort: nil, page: nil
        ))
    }

    func testPageLimitQuota() {
        let compiler = BaseQueryCompiler(table: "expenses", fields: store.fields(of: "expenses"))
        XCTAssertThrowsError(try compiler.compileSelect(
            filter: nil, sort: nil, page: ["limit": 99999]
        )) { error in
            let e = error as! BaseError
            XCTAssertEqual(e.code, "QUOTA_EXCEEDED")
        }
    }

    // MARK: 执行正确性

    func testSelectWithFilterAndSort() throws {
        let rows = try executor.select(
            filter: ["and": [
                ["field": "category", "op": "in", "value": ["food"]],
                ["field": "paid", "op": "eq", "value": true]
            ]],
            sort: [["field": "amount", "direction": "desc"]]
        )
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual((rows[0]["amount"] as? Double), 200)
        XCTAssertEqual((rows[1]["amount"] as? Double), 93)
    }

    func testSelectContains() throws {
        let rows = try executor.select(filter: ["field": "note", "op": "contains", "value": "聚餐"])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?["id"] as? String, "r3")
    }

    func testAggregateSum() throws {
        let out = try executor.aggregate(
            aggregations: [["op": "sum", "field": "amount", "alias": "total"],
                           ["op": "count", "alias": "n"]],
            filter: ["field": "category", "op": "in", "value": ["food"]]
        )
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0]["total"], .number(293))
        XCTAssertEqual(out[0]["n"], .number(2))
    }

    func testAggregateGroupBy() throws {
        let out = try executor.aggregate(
            aggregations: [["op": "sum", "field": "amount", "alias": "total"]],
            groupBy: ["category"]
        )
        XCTAssertEqual(out.count, 2) // food=293, transport=50
        let food = out.first { ($0["category"] as? JSONValue) == .string("food") }
        XCTAssertEqual(food?["total"], .number(293))
    }

    func testAggregateTimeSeries() throws {
        let out = try executor.aggregate(
            aggregations: [["op": "sum", "field": "amount", "alias": "total"]],
            timeSeries: ["field": "spent_on", "granularity": "month", "start": "2026-08-01", "end": "2026-10-01"]
        )
        XCTAssertEqual(out.count, 2) // 2026-08: 200, 2026-09: 143
        let sep = out.first { ($0["bucket"] as? JSONValue) == .string("2026-09") }
        XCTAssertEqual(sep?["total"], .number(143))
    }

    func testLookupExpansion() throws {
        let rows = try executor.select(
            filter: ["field": "id", "op": "eq", "value": "r1"],
            lookup: ["owner"]
        )
        XCTAssertEqual(rows.count, 1)
        let owner = rows[0]["owner"] as? [String: Any]
        XCTAssertEqual(owner?["name"] as? String, "阿诗")
    }

    func testAggregateRejectsNonNumericField() {
        XCTAssertThrowsError(try executor.aggregate(
            aggregations: [["op": "sum", "field": "note", "alias": "x"]]
        ))
    }
}
