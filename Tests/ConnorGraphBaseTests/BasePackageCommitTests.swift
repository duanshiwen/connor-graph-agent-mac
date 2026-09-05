import XCTest
import Foundation
@testable import ConnorGraphBase

/// M3-K5：包写乐观并发收口——签名级变更走「不可变版本记录 + 单调 latest」，过期提交 VERSION_MISMATCH。
///
/// 覆盖：commitPackageVersion 乐观并发（过期拒、零副作用）；提交后注册库/子库 latest 单调前移且版本记录不可变；
/// updateSchema 产生版本记录并保留指南漂移；updateApp 产生版本记录并随指南对齐（防漂移）；updateSchema 过期 base 拒。
final class BasePackageCommitTests: XCTestCase {

    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("base-sync-k5-\(UUID().uuidString)", isDirectory: true)
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

    private func schemaWithBudget() -> [String: Any] {
        var tables = (schema()["tables"] as? [[String: Any]]) ?? []
        tables.append(["name": "budgets", "fields": [["name": "month", "type": "text"], ["name": "limit", "type": "number"]]])
        return ["tables": tables]
    }

    private func guide(_ appID: String) -> [String: Any] {
        ["appID": appID, "title": "记账", "whenToUse": "记一笔时用", "whenNotToUse": "闲聊时不用", "sections": []]
    }

    private func guideV2(_ appID: String) -> [String: Any] {
        ["appID": appID, "title": "记账 v2", "whenToUse": "记一笔时用", "whenNotToUse": "闲聊时不用", "sections": []]
    }

    /// 乐观并发：base 落后最新 → VERSION_MISMATCH，不建版本记录、latest 不变（零副作用）。
    func testStaleCommitRejected() throws {
        let library = try BaseLibraryStore(directory: tmpDir)
        defer { library.close() }
        _ = try library.createApp(manifest: manifest("ledger"), schemaObject: schema(), guide: guide("ledger"), methods: [])

        let next = try library.commitPackageVersion(appID: "ledger", basePackageVersion: 1)
        XCTAssertEqual(next, 2)
        XCTAssertEqual(try library.packageVersion(appID: "ledger"), 2)

        // 用过期 base=1 再提交 → VERSION_MISMATCH，无 v3、latest 仍 2。
        XCTAssertThrowsError(try library.commitPackageVersion(appID: "ledger", basePackageVersion: 1)) { error in
            let e = error as? BaseError
            XCTAssertEqual(e?.code, BaseErrorCode.versionMismatch.rawValue)
        }
        XCTAssertEqual(try library.packageVersion(appID: "ledger"), 2)
        XCTAssertEqual(try library.allPackageVersionFingerprints(appID: "ledger").count, 2)
    }

    /// 提交后注册库 latest 前移、子库 base_pkg_state 前移、版本记录不可变且指纹=快照 SHA-256。
    func testCommitAdvancesRegistryAndSubLibrary() throws {
        let library = try BaseLibraryStore(directory: tmpDir)
        defer { library.close() }
        _ = try library.createApp(manifest: manifest("ledger"), schemaObject: schema(), guide: guide("ledger"), methods: [])

        _ = try library.commitPackageVersion(appID: "ledger", basePackageVersion: 1)
        XCTAssertEqual(try library.packageVersion(appID: "ledger"), 2)
        XCTAssertEqual(try library.packageVersion(appID: "ledger"), 2)

        // 子库 latest 单调前移。
        let store = try library.openStore(appID: "ledger")
        XCTAssertEqual(try store.latestPackageVersion(), 2)
        store.close()

        // 版本记录链 {1, 2}；v2 指纹 = 当前快照 digest。
        let snaps = try library.allPackageVersionFingerprints(appID: "ledger")
        XCTAssertEqual(Array(snaps.keys).sorted(), [1, 2])
        let snap = try library.packageSnapshot(appID: "ledger")
        XCTAssertEqual(snaps[2], try snap.digest())

        // 版本记录不可变：同版本再写拒。
        XCTAssertThrowsError(try library.writePackageVersion(appID: "ledger", snapshot: snap, migrations: [])) { error in
            let e = error as? BaseError
            XCTAssertEqual(e?.code, BaseErrorCode.versionMismatch.rawValue)
        }
    }

    /// updateSchema（结构变更）产生版本记录、单调前移；指南漂移保留（guide_version 不前移）。
    func testUpdateSchemaProducesVersionRecordAndKeepsDrift() throws {
        let library = try BaseLibraryStore(directory: tmpDir)
        defer { library.close() }
        _ = try library.createApp(manifest: manifest("ledger"), schemaObject: schema(), guide: guide("ledger"), methods: [])

        // 工具层流程：先建物理表，再 updateSchema 回写 schema。
        let store = try library.openStore(appID: "ledger")
        let tableDef = try BaseSchemaValidator.parseTable(["name": "budgets", "fields": [
            ["name": "month", "type": "text"], ["name": "limit", "type": "number"]]], schema: nil)
        try store.createTable(tableDef)
        store.close()
        try library.updateSchema(appID: "ledger", schemaObject: schemaWithBudget())

        XCTAssertEqual(try library.packageVersion(appID: "ledger"), 2)
        let snaps = try library.allPackageVersionFingerprints(appID: "ledger")
        XCTAssertEqual(Array(snaps.keys).sorted(), [1, 2])
        let rec = try XCTUnwrap(try library.readPackageVersion(appID: "ledger", version: 2))
        let tables = (rec["schema"] as? [String: Any])?["tables"] as? [[String: Any]]
        XCTAssertEqual(tables?.count, 2)
        // 结构变更保留指南漂移（guide_version 仍 1 < package_version 2）。
        XCTAssertTrue(try library.isGuideOutOfSync(appID: "ledger"))
        // 子库 latest 前移 + 物理表存在。
        let store2 = try library.openStore(appID: "ledger")
        XCTAssertEqual(try store2.latestPackageVersion(), 2)
        XCTAssertTrue(try store2.tableExists("budgets"))
        store2.close()
    }

    /// updateApp（manifest/guide 签名级变更）产生版本记录、指南对齐防漂移。
    func testUpdateAppCommitsVersionRecordAndAlignsGuide() throws {
        let library = try BaseLibraryStore(directory: tmpDir)
        defer { library.close() }
        _ = try library.createApp(manifest: manifest("ledger"), schemaObject: schema(), guide: guide("ledger"), methods: [])

        var m = manifest("ledger")
        m["purpose"] = "记录个人收支、按月给预算"
        let card = try library.updateApp(appID: "ledger", manifest: m, guide: guideV2("ledger"), basePackageVersion: 1)
        XCTAssertEqual(card["packageVersion"] as? Int64, 2)
        XCTAssertFalse(try library.isGuideOutOfSync(appID: "ledger"))

        let snaps = try library.allPackageVersionFingerprints(appID: "ledger")
        XCTAssertEqual(Array(snaps.keys).sorted(), [1, 2])
        let rec = try XCTUnwrap(try library.readPackageVersion(appID: "ledger", version: 2))
        XCTAssertEqual((rec["guide"] as? [String: Any])?["title"] as? String, "记账 v2")
        XCTAssertEqual((rec["manifest"] as? [String: Any])?["purpose"] as? String, "记录个人收支、按月给预算")
    }

    /// updateSchema 过期 base 拒：零副作用（不写 schema_json、不建版本记录、latest 不变）。
    func testUpdateSchemaStaleBaseRejected() throws {
        let library = try BaseLibraryStore(directory: tmpDir)
        defer { library.close() }
        _ = try library.createApp(manifest: manifest("ledger"), schemaObject: schema(), guide: guide("ledger"), methods: [])

        XCTAssertThrowsError(try library.updateSchema(appID: "ledger", schemaObject: schemaWithBudget(), basePackageVersion: 99)) { error in
            let e = error as? BaseError
            XCTAssertEqual(e?.code, BaseErrorCode.versionMismatch.rawValue)
        }
        XCTAssertEqual(try library.packageVersion(appID: "ledger"), 1)
        XCTAssertEqual(try library.allPackageVersionFingerprints(appID: "ledger").count, 1)
        // schema_json 未被写：仍只有 expenses。
        let currentSchema = try library.currentSchemaObject(appID: "ledger")
        let tables = (currentSchema["tables"] as? [[String: Any]]) ?? []
        XCTAssertEqual(tables.count, 1)
    }
}
