import XCTest
import Foundation
@testable import ConnorGraphBase

/// M3-K6：迁移随包确定性重放——App 已存在且版本落后时的原地升级。
///
/// 覆盖：按版本记录链 1..V 逐版确定性重放（建缺失表/加缺失列）+ 数据保留 + 注册库对齐 + 幂等；
/// 版本链缺失 → MIGRATION_FAILED，注册库/子库整体停留旧版（回滚）、旧数据可用。
final class BasePackageMigrationTests: XCTestCase {

    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("base-sync-k6-\(UUID().uuidString)", isDirectory: true)
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

    private func guide(_ appID: String) -> [String: Any] {
        ["appID": appID, "title": "记账", "whenToUse": "记一笔时用", "whenNotToUse": "闲聊时不用", "sections": []]
    }

    /// v1：expenses。
    private func schema1() -> [String: Any] {
        ["tables": [
            ["name": "expenses", "fields": [
                ["name": "amount", "type": "number", "required": true, "range": ["min": 0]],
                ["name": "category", "type": "enum", "enum": ["food", "transport", "other"]],
                ["name": "note", "type": "text"]
            ]]
        ]]
    }

    /// v2：+budgets（month/limit）。
    private func schema2() -> [String: Any] {
        var tables = (schema1()["tables"] as? [[String: Any]]) ?? []
        tables.append(["name": "budgets", "fields": [
            ["name": "month", "type": "text"], ["name": "limit", "type": "number"]]])
        return ["tables": tables]
    }

    /// v3：budgets +note 列。
    private func schema3() -> [String: Any] {
        var tables = (schema2()["tables"] as? [[String: Any]]) ?? []
        tables[1]["fields"] = [
            ["name": "month", "type": "text"], ["name": "limit", "type": "number"],
            ["name": "note", "type": "text"]]
        return ["tables": tables]
    }

    /// 升级：v1→v3 按版本链确定性重放（建 budgets、加 note 列），数据保留、注册库对齐、指纹一致、幂等。
    func testUpgradeReplaysMigrationsAndPreservesData() throws {
        let dir1 = tmpDir.appendingPathComponent("sender")
        let dir2 = tmpDir.appendingPathComponent("receiver")
        try FileManager.default.createDirectory(at: dir1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir2, withIntermediateDirectories: true)

        // sender：v1 → v2（+budgets 表）→ v3（budgets +note 列）。
        let sender = try BaseLibraryStore(directory: dir1)
        _ = try sender.createApp(manifest: manifest("ledger"), schemaObject: schema1(), guide: guide("ledger"), methods: [])
        let s1 = try sender.packageSnapshot(appID: "ledger")   // v1
        try sender.updateSchema(appID: "ledger", schemaObject: schema2())
        let s2 = try sender.packageSnapshot(appID: "ledger")   // v2
        try sender.updateSchema(appID: "ledger", schemaObject: schema3())
        let s3 = try sender.packageSnapshot(appID: "ledger")   // v3
        sender.close()

        // receiver：fresh restore v1 + 已有数据 + 拉齐版本链 → 升级到 v3。
        let receiver = try BaseLibraryStore(directory: dir2)
        defer { receiver.close() }
        try receiver.applyPackageSnapshot(s1)
        let store = try receiver.openStore(appID: "ledger")
        try store.insert(id: "rec_1", table: "expenses",
                         values: ["amount": .number(12.5), "category": .string("food")],
                         meta: ["createdAt": "2026-09-05T00:00:00Z"])
        store.close()
        try receiver.writePackageVersion(appID: "ledger", snapshot: s2, migrations: [2])
        try receiver.writePackageVersion(appID: "ledger", snapshot: s3, migrations: [3])

        let digest = try receiver.applyPackageSnapshot(s3) // 触发原地升级
        XCTAssertEqual(digest, try s3.digest())
        XCTAssertEqual(try receiver.packageVersion(appID: "ledger"), 3)
        XCTAssertEqual(try receiver.allPackageVersionFingerprints(appID: "ledger").count, 3)

        // 子库：budgets 物理存在、note 列已加、迁移已记录、latest 前移、旧数据保留。
        let store2 = try receiver.openStore(appID: "ledger")
        XCTAssertTrue(try store2.tableExists("budgets"))
        XCTAssertNotNil(try store2.columnType(of: "note", in: "budgets"))
        XCTAssertEqual(try store2.appliedMigrations(), [2, 3])
        XCTAssertEqual(try store2.latestPackageVersion(), 3)
        XCTAssertEqual(try store2.fetch(id: "rec_1", table: "expenses")?["amount"], .number(12.5))
        store2.close()

        // 注册库四件套对齐 s3（v3 记录指纹一致、schema 含两表、指南随包）。
        let rec = try XCTUnwrap(try receiver.readPackageVersion(appID: "ledger", version: 3))
        XCTAssertEqual(rec["fingerprint"] as? String, try s3.digest())
        let tables = (rec["schema"] as? [String: Any])?["tables"] as? [[String: Any]]
        XCTAssertEqual(tables?.count, 2)
        XCTAssertEqual((rec["guide"] as? [String: Any])?["title"] as? String, "记账")

        // 幂等：已是最新再 apply → 无变化。
        _ = try receiver.applyPackageSnapshot(s3)
        XCTAssertEqual(try receiver.packageVersion(appID: "ledger"), 3)
    }

    /// 失败：版本链缺失 → MIGRATION_FAILED，注册库/子库整体停留旧版（回滚）、旧数据可用。
    func testUpgradeFailureStaysOldVersion() throws {
        let dir1 = tmpDir.appendingPathComponent("sender")
        let dir2 = tmpDir.appendingPathComponent("receiver")
        try FileManager.default.createDirectory(at: dir1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir2, withIntermediateDirectories: true)

        let sender = try BaseLibraryStore(directory: dir1)
        _ = try sender.createApp(manifest: manifest("ledger"), schemaObject: schema1(), guide: guide("ledger"), methods: [])
        let s1 = try sender.packageSnapshot(appID: "ledger")
        try sender.updateSchema(appID: "ledger", schemaObject: schema2())
        let s2 = try sender.packageSnapshot(appID: "ledger")
        try sender.updateSchema(appID: "ledger", schemaObject: schema3())
        let s3 = try sender.packageSnapshot(appID: "ledger")
        sender.close()

        let receiver = try BaseLibraryStore(directory: dir2)
        defer { receiver.close() }
        try receiver.applyPackageSnapshot(s1)
        let store = try receiver.openStore(appID: "ledger")
        try store.insert(id: "rec_1", table: "expenses", values: ["amount": .number(12.5)], meta: ["createdAt": "2026-09-05T00:00:00Z"])
        store.close()
        // 只拉 v2，v3 缺失 → 重放 v2 后遇 v3 缺失，整体回滚。
        try receiver.writePackageVersion(appID: "ledger", snapshot: s2, migrations: [2])

        XCTAssertThrowsError(try receiver.applyPackageSnapshot(s3)) { error in
            let e = error as? BaseError
            XCTAssertEqual(e?.code, BaseErrorCode.migrationFailed.rawValue)
        }
        // 停留旧版：注册库 v1、子库回滚（无 budgets、迁移空、latest 0）、旧数据可用。
        XCTAssertEqual(try receiver.packageVersion(appID: "ledger"), 1)
        let store2 = try receiver.openStore(appID: "ledger")
        XCTAssertFalse(try store2.tableExists("budgets"))
        XCTAssertEqual(try store2.appliedMigrations(), [])
        XCTAssertEqual(try store2.latestPackageVersion(), 0)
        XCTAssertEqual(try store2.fetch(id: "rec_1", table: "expenses")?["amount"], .number(12.5))
        store2.close()
    }
}
