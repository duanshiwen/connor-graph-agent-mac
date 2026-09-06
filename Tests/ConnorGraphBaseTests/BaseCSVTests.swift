import XCTest
import Foundation
@testable import ConnorGraphBase

/// M1-K7：CSV 导入/导出（外部文件通道）。
final class BaseCSVTests: XCTestCase {

    private var tmpDir: URL!
    private var store: BaseSubLibraryStore!
    private var schema: BaseAppSchema!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("base-k7-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        store = try BaseSubLibraryStore(appID: "acct", directory: tmpDir)
        let expenses = BaseTableDef(name: "expenses", fields: [
            BaseFieldDef(name: "amount", type: "number", required: true),
            BaseFieldDef(name: "category", type: "enum", required: true, enumValues: ["food", "transport"]),
            BaseFieldDef(name: "paid", type: "boolean"),
            BaseFieldDef(name: "note", type: "text")
        ])
        schema = BaseAppSchema(tables: [expenses])
        try store.createTable(expenses)
    }

    override func tearDownWithError() throws {
        store?.close()
        if let tmpDir { try? FileManager.default.removeItem(at: tmpDir) }
    }

    func testParseCSVHandlesQuotesAndNewlines() throws {
        let csv = "a,b\r\n\"x,y\",\"multi\nline\"\r\nz,\"has \"\"quote\"\"\"\r\n"
        let rows = try BaseCSV.parseCSV(csv)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0], ["a", "b"])
        XCTAssertEqual(rows[1], ["x,y", "multi\nline"])
        XCTAssertEqual(rows[2], ["z", "has \"quote\""])
    }

    func testImportWritesRowsThroughMutator() throws {
        let csv = "amount,category,paid,note\n93,food,true,火锅\n50,transport,false,打车\n"
        let result = try BaseCSV.importCSV(csv: csv, table: "expenses", schema: schema, store: store)
        XCTAssertEqual(result.imported, 2)
        XCTAssertTrue(result.errors.isEmpty)
        let rows = try store.execute("SELECT COUNT(*) AS n FROM expenses")
        XCTAssertEqual(rows.first?["n"] as? Int64, 2)
    }

    func testImportRejectsUnknownColumn() {
        let csv = "amount,ghost\n1,x\n"
        XCTAssertThrowsError(try BaseCSV.importCSV(csv: csv, table: "expenses", schema: schema, store: store)) { error in
            let e = error as! BaseError
            XCTAssertEqual(e.code, "VALIDATION_FAILED")
            XCTAssertTrue(e.message.contains("不匹配"))
        }
    }

    func testImportAppliesConstraints() {
        // enum 非法值 → 整批回滚并抛错
        let csv = "amount,category\n1,travel\n"
        XCTAssertThrowsError(try BaseCSV.importCSV(csv: csv, table: "expenses", schema: schema, store: store))
        // 必填缺失
        let csv2 = "amount,category\n, food\n".replacingOccurrences(of: " ", with: "")
        XCTAssertThrowsError(try BaseCSV.importCSV(csv: csv2, table: "expenses", schema: schema, store: store))
    }

    func testImportDryRun() throws {
        let csv = "amount,category\n1,food\n"
        let result = try BaseCSV.importCSV(csv: csv, table: "expenses", schema: schema, store: store, dryRun: true)
        XCTAssertEqual(result.imported, 1)
        XCTAssertTrue(result.dryRun)
        let rows = try store.execute("SELECT COUNT(*) AS n FROM expenses")
        XCTAssertEqual(rows.first?["n"] as? Int64, 0)
    }

    func testExportSerializesWithEscaping() throws {
        _ = try BaseCSV.importCSV(
            csv: "amount,category,paid,note\n93,food,true,\"含,逗号\"\n50,transport,false,simple\n",
            table: "expenses", schema: schema, store: store
        )
        let rows = try store.execute("SELECT * FROM expenses ORDER BY amount")
        let records: [[String: Any]] = rows.map { row in
            var rec: [String: Any] = [:]
            for (k, v) in row where k != "_meta" {
                if k == "id" { rec[k] = v } else if k == "amount" { rec[k] = v } else if k == "category" { rec[k] = v }
                else if k == "paid" { rec[k] = v } else if k == "note" { rec[k] = v }
            }
            return rec
        }
        let csv = BaseCSV.exportCSV(records: records, fieldOrder: ["amount", "category", "paid", "note"])
        XCTAssertTrue(csv.hasPrefix("amount,category,paid,note\r\n"))
        XCTAssertTrue(csv.contains("\"含,逗号\""))
        // 导出后可再导入（往返）
        let result = try BaseCSV.importCSV(csv: csv, table: "expenses", schema: schema, store: store)
        XCTAssertEqual(result.imported, 2)
    }
}
