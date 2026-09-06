import XCTest
import Foundation
@testable import ConnorGraphBase

/// M3-K3：子库行数据确定性导出（含 `_meta`）+ 空库导入。
///
/// 覆盖：确定性 JSON（同数据同字节同指纹）；导出含 `_meta` 与类型化值；导出→空库 fresh restore→导入→再导出
/// 指纹一致（同包同数据同指纹，K8 重建「灌数据」基础）；非空库导入拒（仅空库导入）；包版本不符拒（VERSION_MISMATCH）；
/// 空 App 导出确定性。
final class BaseRecordsSyncTests: XCTestCase {

    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("base-sync-k3-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tmpDir { try? FileManager.default.removeItem(at: tmpDir) }
    }

    private func manifest(_ appID: String) -> [String: Any] {
        ["appID": appID, "name": "记账", "domain": "finance", "purpose": "个人收支",
         "visibility": "private", "requiredCapabilities": [], "imports": [],
         "riskLevel": "low", "sdkVersion": 1]
    }

    private func schema() -> [String: Any] {
        ["tables": [
            ["name": "expenses", "fields": [
                ["name": "amount", "type": "number", "required": true, "range": ["min": 0]],
                ["name": "category", "type": "enum", "enum": ["food", "transport", "other"]],
                ["name": "note", "type": "text"]
            ]]
        ]]
    }

    private func guide(_ appID: String) -> [String: Any] {
        ["appID": appID, "title": "记账", "whenToUse": "记一笔时用", "whenNotToUse": "闲聊时不用", "sections": []]
    }

    private func methods() -> [[String: Any]] {
        [["name": "addExpense", "description": "记一笔", "readOnly": false, "exports": false]]
    }

    private func seedRows(_ library: BaseLibraryStore, appID: String) throws {
        let store = try library.openStore(appID: appID)
        defer { store.close() }
        try store.insert(id: "rec_1", table: "expenses",
                         values: ["amount": .number(12.5), "category": .string("food"), "note": .string("午餐")],
                         meta: ["createdAt": "2026-09-05T00:00:00Z", "updatedAt": "2026-09-05T00:00:00Z"])
        try store.insert(id: "rec_2", table: "expenses",
                         values: ["amount": .number(30), "category": .string("transport"), "note": .string("地铁")],
                         meta: ["createdAt": "2026-09-05T00:00:00Z"])
    }

    /// 确定性：同数据两次导出字节/指纹一致。
    func testExportIsDeterministic() throws {
        let library = try BaseLibraryStore(directory: tmpDir)
        defer { library.close() }
        _ = try library.createApp(manifest: manifest("ledger"), schemaObject: schema(), guide: guide("ledger"), methods: methods())
        try seedRows(library, appID: "ledger")

        let a = try library.exportRecords(appID: "ledger")
        let b = try library.exportRecords(appID: "ledger")
        XCTAssertEqual(try a.canonicalData(), try b.canonicalData())
        XCTAssertEqual(try a.digest(), try b.digest())
    }

    /// 导出含类型化字段值与 `_meta`（解析为对象）；记录 id 保留；包版本正确。
    func testExportContainsTypedValuesAndMeta() throws {
        let library = try BaseLibraryStore(directory: tmpDir)
        defer { library.close() }
        _ = try library.createApp(manifest: manifest("ledger"), schemaObject: schema(), guide: guide("ledger"), methods: methods())
        try seedRows(library, appID: "ledger")

        let export = try library.exportRecords(appID: "ledger")
        XCTAssertEqual(export.appID, "ledger")
        XCTAssertEqual(export.packageVersion, 1)
        XCTAssertEqual(export.tables.count, 1)
        XCTAssertEqual(export.tables[0].table, "expenses")
        XCTAssertEqual(export.tables[0].rows.count, 2)

        let row = export.tables[0].rows[0]
        XCTAssertEqual(row["id"], .string("rec_1"))
        XCTAssertEqual(row["amount"], .number(12.5))
        XCTAssertEqual(row["category"], .string("food"))
        guard case .object(let meta) = row["_meta"] else {
            return XCTFail("_meta 应为对象")
        }
        XCTAssertEqual(meta["createdAt"], .string("2026-09-05T00:00:00Z"))
        XCTAssertEqual(meta["updatedAt"], .string("2026-09-05T00:00:00Z"))
    }

    /// 空库导入后同包同数据同指纹：导出→空库 fresh restore→导入→再导出，指纹一致（K8 灌数据）。
    func testRoundTripRebuildFingerprintEqual() throws {
        let dir1 = tmpDir.appendingPathComponent("src")
        let dir2 = tmpDir.appendingPathComponent("rebuild")
        try FileManager.default.createDirectory(at: dir1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir2, withIntermediateDirectories: true)

        let library1 = try BaseLibraryStore(directory: dir1)
        _ = try library1.createApp(manifest: manifest("ledger"), schemaObject: schema(), guide: guide("ledger"), methods: methods())
        try seedRows(library1, appID: "ledger")
        let snapshot = try library1.packageSnapshot(appID: "ledger")
        let export = try library1.exportRecords(appID: "ledger")
        library1.close()

        // K8 重建：fresh restore（空注册表）→ 灌数据
        let library2 = try BaseLibraryStore(directory: dir2)
        defer { library2.close() }
        try library2.applyPackageSnapshot(snapshot)
        try library2.applyRecordsExport(export)

        let rebuilt = try library2.exportRecords(appID: "ledger")
        XCTAssertEqual(try rebuilt.digest(), try export.digest())
        XCTAssertEqual(try rebuilt.canonicalData(), try export.canonicalData())

        // 数据可读
        let store = try library2.openStore(appID: "ledger")
        defer { store.close() }
        let fetched = try store.fetch(id: "rec_1", table: "expenses")
        XCTAssertEqual(fetched?["amount"], .number(12.5))
        XCTAssertEqual(fetched?["category"], .string("food"))
    }

    /// 非空库导入拒（仅空库导入）：对已有数据的子库重复导入 → VALIDATION_FAILED。
    func testImportRejectsNonEmptyLibrary() throws {
        let library = try BaseLibraryStore(directory: tmpDir)
        defer { library.close() }
        _ = try library.createApp(manifest: manifest("ledger"), schemaObject: schema(), guide: guide("ledger"), methods: methods())
        try seedRows(library, appID: "ledger")
        let export = try library.exportRecords(appID: "ledger")

        XCTAssertThrowsError(try library.applyRecordsExport(export)) { error in
            let e = error as? BaseError
            XCTAssertEqual(e?.code, BaseErrorCode.validationFailed.rawValue)
        }
    }

    /// 包版本不符拒（VERSION_MISMATCH）：目标 latest 与导出版本不一致。
    func testImportRejectsVersionMismatch() throws {
        let library = try BaseLibraryStore(directory: tmpDir)
        defer { library.close() }
        _ = try library.createApp(manifest: manifest("ledger"), schemaObject: schema(), guide: guide("ledger"), methods: methods())
        try seedRows(library, appID: "ledger")
        let export = try library.exportRecords(appID: "ledger")

        // 目标升到 v2 后导入 v1 数据 → 版本不符
        try library.alignPackageVersion(appID: "ledger", to: 2)
        XCTAssertThrowsError(try library.applyRecordsExport(export)) { error in
            let e = error as? BaseError
            XCTAssertEqual(e?.code, BaseErrorCode.versionMismatch.rawValue)
        }
    }

    /// 空 App 导出：无行数据仍可确定性导出（空表集、指纹稳定、包版本正确）。
    func testExportEmptyAppDeterministic() throws {
        let library = try BaseLibraryStore(directory: tmpDir)
        defer { library.close() }
        _ = try library.createApp(manifest: manifest("ledger"), schemaObject: schema(), guide: guide("ledger"), methods: methods())

        let a = try library.exportRecords(appID: "ledger")
        let b = try library.exportRecords(appID: "ledger")
        // 空 App：schema 用户表存在但 0 行；导出确定（同指纹）。
        XCTAssertEqual(a.tables.count, 1)
        XCTAssertEqual(a.tables[0].table, "expenses")
        XCTAssertTrue(a.tables[0].rows.isEmpty)
        XCTAssertEqual(try a.digest(), try b.digest())
        XCTAssertEqual(a.packageVersion, 1)
    }
}
