import XCTest
import Foundation
@testable import ConnorGraphBase

/// M3-K2：四类同步集合——不可变包版本表（`base_pkg_<appID>`）+ 密钥表（`base_keys`）。
///
/// 覆盖：createApp 写 v1 版本记录且指纹=包快照 SHA-256；版本记录内容不可变（同版本覆写拒）；
/// 版本记录可追加（前移）；密钥表 CRUD；注册库 SQL 透传。
final class BaseSyncCollectionsTests: XCTestCase {

    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("base-sync-k2-\(UUID().uuidString)", isDirectory: true)
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

    /// createApp 后 base_pkg_<appID> 有 v1 版本记录，指纹=packageSnapshot.digest()，四件套一致。
    func testCreateAppWritesVersionRecordV1() throws {
        let library = try BaseLibraryStore(directory: tmpDir)
        defer { library.close() }
        _ = try library.createApp(manifest: manifest("ledger"), schemaObject: schema(), guide: guide("ledger"), methods: methods())

        let snap = try library.packageSnapshot(appID: "ledger")
        let fingerprints = try library.allPackageVersionFingerprints(appID: "ledger")
        XCTAssertEqual(fingerprints.count, 1)
        XCTAssertEqual(fingerprints[1], try snap.digest())

        let rec = try XCTUnwrap(try library.readPackageVersion(appID: "ledger", version: 1))
        XCTAssertEqual((rec["manifest"] as? [String: Any])?["name"] as? String, "记账")
        XCTAssertEqual((rec["guide"] as? [String: Any])?["title"] as? String, "记账")
        XCTAssertEqual((rec["methods"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual(rec["migrations"] as? [Int], [])
        XCTAssertEqual(rec["fingerprint"] as? String, try snap.digest())
    }

    /// 版本记录内容不可变：同版本再次写 → VERSION_MISMATCH。
    func testPackageVersionRecordIsImmutable() throws {
        let library = try BaseLibraryStore(directory: tmpDir)
        defer { library.close() }
        _ = try library.createApp(manifest: manifest("ledger"), schemaObject: schema(), guide: guide("ledger"), methods: methods())
        let snap = try library.packageSnapshot(appID: "ledger")

        XCTAssertThrowsError(try library.writePackageVersion(appID: "ledger", snapshot: snap, migrations: [])) { error in
            let e = error as? BaseError
            XCTAssertEqual(e?.code, BaseErrorCode.versionMismatch.rawValue)
        }
        XCTAssertEqual(try library.allPackageVersionFingerprints(appID: "ledger").count, 1)
    }

    /// 版本记录可追加：手动写 v2 后指纹链 {1,2}，latest 语义由调用方单调前移。
    func testPackageVersionRecordsAppend() throws {
        let library = try BaseLibraryStore(directory: tmpDir)
        defer { library.close() }
        _ = try library.createApp(manifest: manifest("ledger"), schemaObject: schema(), guide: guide("ledger"), methods: methods())

        var m2 = manifest("ledger")
        m2["name"] = "记账 Pro"
        let s2: [String: Any] = ["tables": [
            ["name": "expenses", "fields": [
                ["name": "amount", "type": "number", "required": true, "range": ["min": 0]],
                ["name": "category", "type": "enum", "enum": ["food", "transport", "other"]],
                ["name": "note", "type": "text"],
                ["name": "vendor", "type": "text"]
            ]]
        ]]
        let snap2 = try BasePackageSnapshot(appID: "ledger", packageVersion: 2, manifest: m2, schema: s2, methods: methods(), guide: guide("ledger"))
        try library.writePackageVersion(appID: "ledger", snapshot: snap2, migrations: [1])

        let fingerprints = try library.allPackageVersionFingerprints(appID: "ledger")
        XCTAssertEqual(fingerprints.count, 2)
        XCTAssertNotNil(fingerprints[1])
        XCTAssertEqual(fingerprints[2], try snap2.digest())
        let rec2 = try XCTUnwrap(try library.readPackageVersion(appID: "ledger", version: 2))
        XCTAssertEqual(rec2["migrations"] as? [Int], [1])
        // 从版本记录重建快照，指纹一致（同包同 Card 的版本面）。
        let rebuilt = try XCTUnwrap(try library.packageSnapshot(fromVersionRecord: "ledger", version: 2))
        XCTAssertEqual(try rebuilt.digest(), try snap2.digest())
    }

    /// base_keys：master/app 密钥存取。
    func testKeysTableCRUD() throws {
        let library = try BaseLibraryStore(directory: tmpDir)
        defer { library.close() }
        try library.saveSyncKey(keyID: "k_master_1", kind: "master", appID: "", payloadJSON: "{\"algo\":\"aes-gcm\"}")
        try library.saveSyncKey(keyID: "k_ledger_1", kind: "app", appID: "ledger", payloadJSON: "\"AAAA\"")

        let keys = try library.readSyncKeys()
        XCTAssertEqual(keys.count, 2)
        XCTAssertEqual(try library.syncKeyPayload(kind: "master", appID: ""), "{\"algo\":\"aes-gcm\"}")
        XCTAssertEqual(try library.syncKeyPayload(kind: "app", appID: "ledger"), "\"AAAA\"")
        XCTAssertNil(try library.syncKeyPayload(kind: "app", appID: "missing"))
    }

    /// 注册库 SQL 透传可用（四类同步集合的写面）。
    func testRegistryExecuteRoundTrip() throws {
        let library = try BaseLibraryStore(directory: tmpDir)
        defer { library.close() }
        let n = try library.registryExecuteVoid("CREATE TABLE IF NOT EXISTS t_probe (k TEXT PRIMARY KEY)", parameters: [])
        XCTAssertGreaterThanOrEqual(n, 0)
        _ = try library.registryExecuteVoid("INSERT INTO t_probe (k) VALUES (?1)", parameters: ["x"])
        let rows = try library.registryExecute("SELECT k FROM t_probe", parameters: [])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["k"] as? String, "x")
    }
}
