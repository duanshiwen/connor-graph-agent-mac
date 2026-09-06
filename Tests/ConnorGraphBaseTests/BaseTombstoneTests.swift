import XCTest
import Foundation
@testable import ConnorGraphBase

/// M3-K7：墓碑一体传播——删 App = 包 + 版本 + 数据 + 安装注册一起墓碑传播。
///
/// 覆盖：deleteApp 产墓碑（latest 版本 + 指纹）+ 本地一体清除（注册行/子库文件/版本链表）；
/// 对端 applyTombstone 持久化墓碑并对已装 App 一体删除（幂等可重入）；墓碑指纹确定性。
final class BaseTombstoneTests: XCTestCase {

    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("base-sync-k7-\(UUID().uuidString)", isDirectory: true)
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

    private func schema() -> [String: Any] {
        ["tables": [["name": "expenses", "fields": [
            ["name": "amount", "type": "number", "required": true],
            ["name": "category", "type": "enum", "enum": ["food", "transport"]]]]]]
    }

    private func schemaV2() -> [String: Any] {
        var tables = (schema()["tables"] as? [[String: Any]]) ?? []
        tables.append(["name": "budgets", "fields": [["name": "limit", "type": "number"]]])
        return ["tables": tables]
    }

    /// 墓碑一体：deleteApp 产墓碑（latest 版本 + 指纹），删注册行/子库文件/版本链表；重复删除抛 notFound。
    func testDeleteAppProducesTombstoneAndPurgesLocally() throws {
        let lib = try BaseLibraryStore(directory: tmpDir.appendingPathComponent("lib", isDirectory: true))
        defer { lib.close() }
        _ = try lib.createApp(manifest: manifest("ledger"), schemaObject: schema(), guide: guide("ledger"))
        try lib.updateSchema(appID: "ledger", schemaObject: schemaV2())
        let s2 = try lib.packageSnapshot(appID: "ledger")

        let store = try lib.openStore(appID: "ledger")
        let dbPath = store.dbURL.path
        store.close()
        XCTAssertTrue(FileManager.default.fileExists(atPath: dbPath))

        try lib.deleteApp(appID: "ledger")
        // 墓碑记录：latest 版本 2 + 指纹 = s2.digest() + 删除时间非空。
        let t = try XCTUnwrap(try lib.tombstone(appID: "ledger"))
        XCTAssertEqual(t.packageVersion, 2)
        XCTAssertEqual(t.fingerprint, try s2.digest())
        XCTAssertFalse(t.deletedAt.isEmpty)
        // 本地一体清除：注册行 / 子库文件 / 版本链表。
        XCTAssertFalse(try lib.appExists("ledger"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dbPath))
        XCTAssertTrue(try lib.allPackageVersionFingerprints(appID: "ledger").isEmpty)
        // 重复删除：App 已不存在 → notFound。
        XCTAssertThrowsError(try lib.deleteApp(appID: "ledger"))
    }

    /// 对端应用墓碑：持久化墓碑并对已装 App 一体删除（含版本链表），幂等可重入。
    func testApplyTombstonePurgesRemoteAppIdempotently() throws {
        // sender：创建 v1 → v2 → 删除 → 产墓碑。
        let src = try BaseLibraryStore(directory: tmpDir.appendingPathComponent("src", isDirectory: true))
        _ = try src.createApp(manifest: manifest("ledger"), schemaObject: schema(), guide: guide("ledger"))
        try src.updateSchema(appID: "ledger", schemaObject: schemaV2())
        let s2 = try src.packageSnapshot(appID: "ledger")
        try src.deleteApp(appID: "ledger")
        let tombstone = try XCTUnwrap(try src.tombstone(appID: "ledger"))
        src.close()

        // receiver：先装 v2，再应用墓碑。
        let dst = try BaseLibraryStore(directory: tmpDir.appendingPathComponent("dst", isDirectory: true))
        defer { dst.close() }
        try dst.applyPackageSnapshot(s2)
        XCTAssertTrue(try dst.appExists("ledger"))
        let store = try dst.openStore(appID: "ledger")
        let dbPath = store.dbURL.path
        store.close()

        let removed = try dst.applyTombstone(tombstone)
        XCTAssertTrue(removed)
        XCTAssertEqual(try dst.tombstone(appID: "ledger")?.packageVersion, 2)
        XCTAssertFalse(try dst.appExists("ledger"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dbPath))
        XCTAssertTrue(try dst.allPackageVersionFingerprints(appID: "ledger").isEmpty)
        // 幂等：再次应用 → 实际未删除（false），但墓碑持久化不变。
        let again = try dst.applyTombstone(tombstone)
        XCTAssertFalse(again)
        XCTAssertEqual(try dst.tombstone(appID: "ledger")?.fingerprint, tombstone.fingerprint)
    }

    /// 墓碑确定性：同参数两次 digest 一致；版本变则指纹变。
    func testTombstoneDigestIsDeterministic() throws {
        let a = BaseTombstone(appID: "ledger", packageVersion: 2, fingerprint: "abc", deletedAt: "2026-09-05T00:00:00Z")
        let b = BaseTombstone(appID: "ledger", packageVersion: 2, fingerprint: "abc", deletedAt: "2026-09-05T00:00:00Z")
        let c = BaseTombstone(appID: "ledger", packageVersion: 3, fingerprint: "abc", deletedAt: "2026-09-05T00:00:00Z")
        XCTAssertEqual(try a.digest(), try b.digest())
        XCTAssertNotEqual(try a.digest(), try c.digest())
    }
}
