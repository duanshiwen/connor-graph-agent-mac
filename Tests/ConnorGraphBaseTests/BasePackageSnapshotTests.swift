import XCTest
import Foundation
@testable import ConnorGraphBase

/// M3-K1：不可变包快照（确定性 JSON + SHA-256 指纹）+ 确定性恢复（fresh restore / 幂等 / 版本落后）。
///
/// 覆盖：
/// - 确定性：相同载荷两次构造 → 相同 canonicalData、相同 digest；版本变化 → digest 变化。
/// - 同包同 Card：packageSnapshot 与手写同载荷快照同指纹；恢复后的 appCard 与源端一致（含 purpose）。
/// - fresh restore：空注册表四件套同批创建、版本对齐到快照版本。
/// - 幂等：同一快照重复 apply 不重放、不抛错、版本不倒退。
/// - VERSION_MISMATCH：已存在且版本落后抛错（原地升级由 M3-K6 承担）。
final class BasePackageSnapshotTests: XCTestCase {

    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("base-sync-k1-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tmpDir { try? FileManager.default.removeItem(at: tmpDir) }
    }

    private func manifest(_ appID: String) -> [String: Any] {
        ["appID": appID, "name": "记账", "domain": "finance", "purpose": "个人收支记录与统计",
         "visibility": "private", "requiredCapabilities": [], "imports": [],
         "riskLevel": "low", "sdkVersion": 1]
    }

    private func schema() -> [String: Any] {
        ["tables": [
            ["name": "expenses", "fields": [
                ["name": "amount", "type": "number", "required": true, "range": ["min": 0]],
                ["name": "category", "type": "enum", "enum": ["food", "transport", "other"]],
                ["name": "paid", "type": "boolean", "default": false],
                ["name": "note", "type": "text"]
            ]]
        ]]
    }

    private func guide(_ appID: String) -> [String: Any] {
        ["appID": appID, "title": "记账", "whenToUse": "当用户说记一笔且是个人收支时用",
         "whenNotToUse": "当只是闲聊消费观时不用", "sections": []]
    }

    private func methods() -> [[String: Any]] {
        [["name": "addExpense", "description": "记一笔", "readOnly": false, "exports": false]]
    }

    private func snapshot(appID: String = "ledger", version: Int = 1) throws -> BasePackageSnapshot {
        try BasePackageSnapshot(
            appID: appID,
            packageVersion: version,
            manifest: manifest(appID),
            schema: schema(),
            methods: methods(),
            guide: guide(appID)
        )
    }

    // MARK: - 确定性 JSON 与 SHA-256 指纹

    /// 相同载荷两次构造 → canonicalData 逐字节一致、digest 一致（同包必同字节、必同指纹）。
    func testSnapshotCanonicalBytesAndDigestAreDeterministic() throws {
        let a = try snapshot()
        let b = try snapshot()
        XCTAssertEqual(try a.canonicalData(), try b.canonicalData())
        let d1 = try a.digest()
        let d2 = try b.digest()
        XCTAssertEqual(d1, d2)
        XCTAssertEqual(d1.count, 64) // SHA-256 十六进制 = 64 字符
        XCTAssertTrue(d1.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil)
    }

    /// 版本变化 → 指纹变化（版本是包指纹的组成部分）。
    func testSnapshotVersionChangesDigest() throws {
        let v1 = try snapshot(version: 1)
        let v2 = try snapshot(version: 2)
        XCTAssertNotEqual(try v1.digest(), try v2.digest())
    }

    /// 同一逻辑包经不同构造路径 → 同指纹；与注册表 packageVersion 一致。
    func testPackageSnapshotMatchesManualSnapshot() throws {
        let library = try BaseLibraryStore(directory: tmpDir)
        defer { library.close() }
        _ = try library.createApp(manifest: manifest("ledger"), schemaObject: schema(), guide: guide("ledger"), methods: methods())

        let fromStore = try library.packageSnapshot(appID: "ledger")
        let manual = try snapshot()
        XCTAssertEqual(try fromStore.digest(), try manual.digest())
        XCTAssertEqual(fromStore.packageVersion, 1)
    }

    /// packageSnapshot 对不存在的 App 抛 NOT_FOUND。
    func testPackageSnapshotMissingAppThrowsNotFound() throws {
        let library = try BaseLibraryStore(directory: tmpDir)
        defer { library.close() }
        XCTAssertThrowsError(try library.packageSnapshot(appID: "ghost")) { error in
            let e = error as? BaseError
            XCTAssertEqual(e?.code, BaseErrorCode.notFound.rawValue)
        }
    }

    // MARK: - fresh restore 与同包同 Card

    /// fresh restore：空注册表恢复 → 四件套同批创建、版本对齐、指南/方法/用途完整、同包同 Card。
    func testApplyFreshRestoreRecreatesAppAndCard() throws {
        let src = try BaseLibraryStore(directory: tmpDir.appendingPathComponent("src", isDirectory: true))
        defer { src.close() }
        _ = try src.createApp(manifest: manifest("ledger"), schemaObject: schema(), guide: guide("ledger"), methods: methods())
        let snap = try src.packageSnapshot(appID: "ledger")

        let dst = try BaseLibraryStore(directory: tmpDir.appendingPathComponent("dst", isDirectory: true))
        defer { dst.close() }
        let digest = try dst.applyPackageSnapshot(snap)
        XCTAssertEqual(digest, try snap.digest())

        XCTAssertTrue(try dst.appExists("ledger"))
        XCTAssertEqual(try dst.packageVersion(appID: "ledger"), snap.packageVersion)
        let pkg = try XCTUnwrap(try dst.packageDictionary(appID: "ledger"))
        XCTAssertEqual((pkg["manifest"] as? [String: Any])?["name"] as? String, "记账")
        XCTAssertEqual((pkg["manifest"] as? [String: Any])?["purpose"] as? String, "个人收支记录与统计")
        XCTAssertEqual((pkg["guide"] as? [String: Any])?["title"] as? String, "记账")
        XCTAssertEqual((pkg["methods"] as? [[String: Any]])?.count, 1)

        // 同包同 Card：源端与恢复端 appCard 的包身份字段完全一致（含 purpose/guideOutOfSync 状态）。
        // 排除 createdAt/updatedAt——两端建库时间天然不同（可能跨秒），不参与包身份判定。
        let cardA = try XCTUnwrap(try src.appCard(appID: "ledger", includeGuide: true))
        let cardB = try XCTUnwrap(try dst.appCard(appID: "ledger", includeGuide: true))
        XCTAssertEqual(normalized(cardA) as NSDictionary, normalized(cardB) as NSDictionary)
    }

    /// 去除时间戳字段后的包身份卡片（同包同 Card 的比对面）。
    private func normalized(_ card: [String: Any]) -> [String: Any] {
        var c = card
        c.removeValue(forKey: "createdAt")
        c.removeValue(forKey: "updatedAt")
        return c
    }

    // MARK: - 幂等与版本落后

    /// 幂等：同一快照重复 apply → 同指纹返回、不抛错、不重放、版本不倒退。
    func testApplySnapshotIsIdempotent() throws {
        let src = try BaseLibraryStore(directory: tmpDir.appendingPathComponent("src", isDirectory: true))
        defer { src.close() }
        _ = try src.createApp(manifest: manifest("ledger"), schemaObject: schema(), guide: guide("ledger"), methods: methods())
        let snap = try src.packageSnapshot(appID: "ledger")

        let dst = try BaseLibraryStore(directory: tmpDir.appendingPathComponent("dst", isDirectory: true))
        defer { dst.close() }
        let first = try dst.applyPackageSnapshot(snap)
        let second = try dst.applyPackageSnapshot(snap)
        XCTAssertEqual(first, try snap.digest())
        XCTAssertEqual(second, try snap.digest())
        XCTAssertEqual(try dst.packageVersion(appID: "ledger"), 1)
        // 数据面未被重放清空/覆盖（幂等不重放）。
        let pkg = try XCTUnwrap(try dst.packageDictionary(appID: "ledger"))
        XCTAssertEqual((pkg["methods"] as? [[String: Any]])?.count, 1)
    }

    /// 已存在且目标版本更高，但版本记录链缺失（只有 v1）→ 无法确定性重放 → MIGRATION_FAILED，停留旧版 v1。
    /// （K1 占位断言为 VERSION_MISMATCH；K6 落地后由「迁移随包确定性重放」承担：链缺失即 MIGRATION_FAILED。）
    func testApplyNewerSnapshotMissingChainThrowsMigrationFailed() throws {
        let src = try BaseLibraryStore(directory: tmpDir.appendingPathComponent("src", isDirectory: true))
        defer { src.close() }
        _ = try src.createApp(manifest: manifest("ledger"), schemaObject: schema(), guide: guide("ledger"), methods: methods())
        let snap = try src.packageSnapshot(appID: "ledger")

        let dst = try BaseLibraryStore(directory: tmpDir.appendingPathComponent("dst", isDirectory: true))
        defer { dst.close() }
        _ = try dst.applyPackageSnapshot(snap)

        // 目标版本 2 > 当前 1，但 dst 只有 v1 版本记录 → 链缺失 → MIGRATION_FAILED，且停留旧版（version 不前进）。
        let newer = try snapshot(version: 2)
        XCTAssertThrowsError(try dst.applyPackageSnapshot(newer)) { error in
            let e = error as? BaseError
            XCTAssertEqual(e?.code, BaseErrorCode.migrationFailed.rawValue)
        }
        XCTAssertEqual(try dst.packageVersion(appID: "ledger"), 1)
    }
}
