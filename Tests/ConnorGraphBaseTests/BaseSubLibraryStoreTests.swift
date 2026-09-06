import XCTest
import Foundation
@testable import ConnorGraphBase

/// M1-K2：子库存储层（每 App 独立 SQLite 文件、参数绑定、包版本、迁移记录）。
final class BaseSubLibraryStoreTests: XCTestCase {

    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("base-k2-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tmpDir {
            try? FileManager.default.removeItem(at: tmpDir)
        }
    }

    private func expensesTable() -> BaseTableDef {
        BaseTableDef(name: "expenses", fields: [
            BaseFieldDef(name: "amount", type: "number", required: true, min: 0),
            BaseFieldDef(name: "category", type: "enum", enumValues: ["food", "transport", "home", "other"]),
            BaseFieldDef(name: "paid", type: "boolean", defaultValue: .bool(false)),
            BaseFieldDef(name: "note", type: "text")
        ])
    }

    func testCreateLibraryCreatesFileAndSystemTables() throws {
        let store = try BaseSubLibraryStore(appID: "acct", directory: tmpDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.dbURL.path))
        XCTAssertTrue(try store.tableExists("base_pkg_state"))
        XCTAssertTrue(try store.tableExists("schema_migrations"))
        XCTAssertEqual(try store.latestPackageVersion(), 0)
        store.close()
    }

    func testRejectsInvalidAppID() {
        XCTAssertThrowsError(try BaseSubLibraryStore(appID: "Bad App", directory: tmpDir))
        XCTAssertThrowsError(try BaseSubLibraryStore(appID: String(repeating: "a", count: 49), directory: tmpDir))
    }

    func testCreateTableAndCRUD() throws {
        let store = try BaseSubLibraryStore(appID: "acct", directory: tmpDir)
        try store.createTable(expensesTable())
        XCTAssertTrue(try store.tableExists("expenses"))

        try store.insert(id: "r1", table: "expenses", values: [
            "amount": .number(93),
            "category": .string("food"),
            "paid": .bool(true)
        ], meta: ["source": "test"])

        let row = try store.fetch(id: "r1", table: "expenses")
        XCTAssertNotNil(row)
        XCTAssertEqual(row?["amount"], .number(93))
        XCTAssertEqual(row?["category"], .string("food"))
        XCTAssertEqual(row?["paid"], .bool(true), "boolean 列应还原为 bool 而非 number")

        try store.update(id: "r1", table: "expenses", values: ["amount": .number(100)])
        XCTAssertEqual(try store.fetch(id: "r1", table: "expenses")?["amount"], .number(100))

        try store.delete(id: "r1", table: "expenses")
        XCTAssertNil(try store.fetch(id: "r1", table: "expenses"))
        store.close()
    }

    func testParameterBindingEscapesInjection() throws {
        let store = try BaseSubLibraryStore(appID: "acct", directory: tmpDir)
        try store.createTable(expensesTable())
        // 值里的 SQL 注入字符串应作为字面量存储，不执行。
        let malicious = "x'); DROP TABLE expenses; --"
        try store.insert(id: "r2", table: "expenses", values: ["note": .string(malicious)])
        XCTAssertTrue(try store.tableExists("expenses"), "注入字符串不应破坏表结构")
        XCTAssertEqual(try store.fetch(id: "r2", table: "expenses")?["note"], .string(malicious))
        store.close()
    }

    func testRejectsInvalidTableAndFieldNames() throws {
        let store = try BaseSubLibraryStore(appID: "acct", directory: tmpDir)
        XCTAssertThrowsError(try store.createTable(BaseTableDef(name: "Bad-Table!", fields: [])))
        XCTAssertThrowsError(try store.createTable(BaseTableDef(name: "t", fields: [
            BaseFieldDef(name: "bad name", type: "text")
        ])))
        XCTAssertThrowsError(try store.insert(id: "x", table: "Bad-Table!", values: [:]))
        store.close()
    }

    func testPackageVersionMonotonic() throws {
        let store = try BaseSubLibraryStore(appID: "acct", directory: tmpDir)
        try store.advancePackageVersion(to: 3)
        XCTAssertEqual(try store.latestPackageVersion(), 3)
        XCTAssertThrowsError(try store.advancePackageVersion(to: 2), "latest 不可回退")
        try store.advancePackageVersion(to: 4)
        XCTAssertEqual(try store.latestPackageVersion(), 4)
        store.close()
    }

    func testMigrations() throws {
        let store = try BaseSubLibraryStore(appID: "acct", directory: tmpDir)
        XCTAssertTrue(try store.appliedMigrations().isEmpty)
        try store.recordMigration(1)
        try store.recordMigration(3)
        XCTAssertEqual(try store.appliedMigrations(), [1, 3])
        store.close()
    }

    func testTransactionRollsBack() throws {
        let store = try BaseSubLibraryStore(appID: "acct", directory: tmpDir)
        try store.createTable(expensesTable())
        XCTAssertThrowsError(try store.withTransaction {
            try store.insert(id: "r9", table: "expenses", values: ["amount": .number(1)])
            throw BaseError.notFound("故意失败")
        })
        XCTAssertNil(try store.fetch(id: "r9", table: "expenses"), "事务回滚后不应残留写入")
        store.close()
    }
}
