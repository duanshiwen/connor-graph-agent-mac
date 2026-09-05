import XCTest
import Foundation
@testable import ConnorGraphBase

/// M1-M5：无工作台机制（不自动创建任何固定 appID）+ AppPackage 四件套统一存取 + 子库物理隔离与墓碑删除。
final class BaseLibraryStoreTests: XCTestCase {

    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("base-m5-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tmpDir {
            try? FileManager.default.removeItem(at: tmpDir)
        }
    }

    private func manifest(_ appID: String) -> [String: Any] {
        ["appID": appID, "name": "记账", "domain": "finance", "visibility": "private",
         "requiredCapabilities": [], "imports": [], "riskLevel": "low", "sdkVersion": 1]
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

    /// v0.12：不设个人工作台/散表/转正中间态——初始化不创建任何固定 appID（无 personal_workbench）。
    func testInitCreatesNoFixedDefaultApp() throws {
        let library = try BaseLibraryStore(directory: tmpDir)
        defer { library.close() }
        XCTAssertTrue(try library.listApps().isEmpty)
        XCTAssertFalse(try library.appExists("personal_workbench"))
    }

    /// 四件套统一存取：createApp 同批写入 manifest/schema/guide/methods，packageDictionary 读回一致。
    func testFourArtifactsRoundTrip() throws {
        let library = try BaseLibraryStore(directory: tmpDir)
        defer { library.close() }
        let methods: [[String: Any]] = [["name": "addExpense", "description": "记一笔", "readOnly": false, "exports": false]]
        _ = try library.createApp(manifest: manifest("ledger"), schemaObject: schema(), guide: guide("ledger"), methods: methods)

        let pkg = try XCTUnwrap(try library.packageDictionary(appID: "ledger"))
        let pkgManifest = pkg["manifest"] as? [String: Any]
        XCTAssertEqual(pkgManifest?["appID"] as? String, "ledger")
        XCTAssertEqual(pkgManifest?["name"] as? String, "记账")
        XCTAssertEqual(pkgManifest?["visibility"] as? String, "private")
        XCTAssertEqual(pkg["packageVersion"] as? Int64, 1)
        let pkgSchema = pkg["schema"] as? [String: Any]
        XCTAssertNotNil((pkgSchema?["tables"] as? [[String: Any]])?.first)
        XCTAssertEqual((pkg["guide"] as? [String: Any])?["title"] as? String, "记账")
        XCTAssertEqual((pkg["methods"] as? [[String: Any]])?.first?["name"] as? String, "addExpense")
    }

    /// 子库物理隔离：每个 App 独立 base_<appID>.db 文件；写入后经 store 读回。
    func testSubLibraryPhysicalIsolation() throws {
        let library = try BaseLibraryStore(directory: tmpDir)
        defer { library.close() }
        _ = try library.createApp(manifest: manifest("ledger"), schemaObject: schema(), guide: guide("ledger"))

        let store = try library.openStore(appID: "ledger")
        defer { store.close() }
        XCTAssertEqual(store.dbURL.lastPathComponent, "base_ledger.db")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.dbURL.path))

        try store.insert(id: "rec_1", table: "expenses", values: [
            "amount": .number(120), "category": .string("food"), "paid": .bool(true), "note": .string("午饭")
        ])
        let rows = try store.execute("SELECT * FROM expenses")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["id"] as? String, "rec_1")
    }

    /// 墓碑删除：deleteApp 移除注册行 + 子库文件（含 WAL/SHM）。
    func testDeleteAppRemovesRegistryAndSubLibraryFile() throws {
        let library = try BaseLibraryStore(directory: tmpDir)
        defer { library.close() }
        _ = try library.createApp(manifest: manifest("ledger"), schemaObject: schema(), guide: guide("ledger"))
        let store = try library.openStore(appID: "ledger")
        let dbPath = store.dbURL.path
        store.close()
        XCTAssertTrue(FileManager.default.fileExists(atPath: dbPath))

        try library.deleteApp(appID: "ledger")
        XCTAssertFalse(try library.appExists("ledger"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dbPath))
    }

    /// 能力点门禁：deferred 的 import（跨库只读导入，v0.11 暂缓）拒绝创建。
    func testCreateAppRejectsDeferredImportCapability() throws {
        let library = try BaseLibraryStore(directory: tmpDir)
        defer { library.close() }
        var m = manifest("xapp")
        m["requiredCapabilities"] = ["import"]
        XCTAssertThrowsError(try library.createApp(manifest: m, schemaObject: schema(), guide: guide("xapp"))) { error in
            let e = error as? BaseError
            XCTAssertEqual(e?.code, BaseErrorCode.capabilityRequired.rawValue)
        }
    }

    // MARK: - M2-M3 能力搜索 catalog（v0.12 §6.6/§6.7）

    /// 一句话用途（purpose）进入 catalog 检索字段：query 命中 purpose 但未命中名称/领域/appID。
    func testCatalogSearchMatchesPurpose() throws {
        let library = try BaseLibraryStore(directory: tmpDir)
        defer { library.close() }
        var m = manifest("ledger")
        m["name"] = "我的本子"
        m["purpose"] = "记录个人收支、按月给预算"
        _ = try library.createApp(manifest: m, schemaObject: schema(), guide: guide("ledger"))

        XCTAssertEqual(try library.listApps(query: "预算").count, 1, "query 应命中一句话用途")
        XCTAssertEqual(try library.listApps(query: "我的本子").count, 1, "query 应命中名称")
        XCTAssertTrue(try library.listApps(query: "不存在的词").isEmpty)
    }

    /// 方法名进入 catalog 检索字段（解锁你没用过的方法）：query 命中方法名。
    func testCatalogSearchMatchesMethodName() throws {
        let library = try BaseLibraryStore(directory: tmpDir)
        defer { library.close() }
        let methods: [[String: Any]] = [
            ["name": "monthlyTotal", "description": "本月合计", "readOnly": true, "exports": false]
        ]
        _ = try library.createApp(manifest: manifest("ledger"), schemaObject: schema(), guide: guide("ledger"), methods: methods)

        XCTAssertEqual(try library.listApps(query: "monthlyTotal").count, 1)
        XCTAssertEqual(try library.listApps(query: "monthly").count, 1, "子串命中")
    }

    /// scope + query 组合：v1 端侧均为 private（本人创建），scope=private 返回全部、query 进一步收敛。
    func testCatalogSearchScopeAndQuery() throws {
        let library = try BaseLibraryStore(directory: tmpDir)
        defer { library.close() }
        _ = try library.createApp(manifest: manifest("ledger"), schemaObject: schema(), guide: guide("ledger"))
        var m2 = manifest("habits")
        m2["name"] = "习惯打卡"
        m2["domain"] = "habit"
        _ = try library.createApp(manifest: m2, schemaObject: schema(), guide: guide("habits"))

        XCTAssertEqual(try library.listApps(scope: "private").count, 2)
        XCTAssertEqual(try library.listApps(scope: "private", query: "ledger").count, 1)
        XCTAssertEqual(try library.listApps(scope: "public").count, 0, "v1 端侧无私密外的共享/公开 App")
    }

    /// App Card 含一句话用途（purpose）、catalog 来源（source）与兼容标志（compatible），对齐 v0.12 §6.1。
    func testCardIncludesPurposeSourceAndCompatible() throws {
        let library = try BaseLibraryStore(directory: tmpDir)
        defer { library.close() }
        var m = manifest("ledger")
        m["purpose"] = "记录个人收支"
        _ = try library.createApp(manifest: m, schemaObject: schema(), guide: guide("ledger"))

        let card = try XCTUnwrap(try library.appCard(appID: "ledger"))
        XCTAssertEqual(card["purpose"] as? String, "记录个人收支")
        XCTAssertEqual(card["source"] as? String, "private")
        XCTAssertEqual(card["compatible"] as? Bool, true)
        XCTAssertEqual(card["visibility"] as? String, "private")
    }

    /// purpose 随 create 写入、随 update 演进（manifest 更新路径）。
    func testPurposeRoundTripThroughCreateAndUpdate() throws {
        let library = try BaseLibraryStore(directory: tmpDir)
        defer { library.close() }
        _ = try library.createApp(manifest: manifest("ledger"), schemaObject: schema(), guide: guide("ledger"))
        let card1 = try XCTUnwrap(try library.appCard(appID: "ledger"))
        XCTAssertEqual(card1["purpose"] as? String, "")

        var m = manifest("ledger")
        m["purpose"] = "记录个人收支、按月给预算"
        let updated = try library.updateApp(appID: "ledger", manifest: m, guide: nil, basePackageVersion: nil)
        XCTAssertEqual(updated["packageVersion"] as? Int64, 2)
        let card2 = try XCTUnwrap(try library.appCard(appID: "ledger"))
        XCTAssertEqual(card2["purpose"] as? String, "记录个人收支、按月给预算")
        XCTAssertEqual(try library.listApps(query: "预算").count, 1)
    }
}
