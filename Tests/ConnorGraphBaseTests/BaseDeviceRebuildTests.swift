import XCTest
import Foundation
@testable import ConnorGraphBase

/// M3-K8：新设备「应用完整重建」六步（主密钥 → 拉密钥 → 拉版本链 → 建子库 → 重放迁移 →
/// 灌数据 → 编译 Card → 注册进能力搜索），按 App 幂等可重入。
///
/// 覆盖：六步全链路重建（含迁移随包重放 + 数据灌入 + Card/能力搜索面）；幂等重入；
/// 版本链缺失/链头非 v1 拒绝；版本记录指纹冲突拒绝；E2EE 传输解密后重建端到端。
final class BaseDeviceRebuildTests: XCTestCase {

    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("base-sync-k8-\(UUID().uuidString)", isDirectory: true)
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

    private func schema1() -> [String: Any] {
        ["tables": [["name": "expenses", "fields": [
            ["name": "amount", "type": "number", "required": true],
            ["name": "category", "type": "enum", "enum": ["food", "transport"]]]]]]
    }

    private func schema2() -> [String: Any] {
        var tables = (schema1()["tables"] as? [[String: Any]]) ?? []
        tables.append(["name": "budgets", "fields": [["name": "limit", "type": "number"]]])
        return ["tables": tables]
    }

    /// 造 sender（v1 → v2 + 数据），返回 (master, appKey, 版本链记录, target, export)。
    private func makeSender(_ dir: URL) throws -> (master: String, appKey: String,
                                                   chain: [BasePackageVersionRecord],
                                                   target: BasePackageSnapshot,
                                                   export: BaseRecordsExport) {
        let src = try BaseLibraryStore(directory: dir)
        _ = try src.createApp(manifest: manifest("ledger"), schemaObject: schema1(), guide: guide("ledger"), methods: [])
        let s1 = try src.packageSnapshot(appID: "ledger")
        try src.updateSchema(appID: "ledger", schemaObject: schema2())
        let s2 = try src.packageSnapshot(appID: "ledger")
        let store = try src.openStore(appID: "ledger")
        try store.insert(id: "rec_1", table: "expenses",
                         values: ["amount": .number(12.5), "category": .string("food")],
                         meta: ["createdAt": "2026-09-05T00:00:00Z"])
        store.close()
        let export = try src.exportRecords(appID: "ledger")
        let master = try src.ensureMasterKey()
        let appKey = try src.syncAppKey(appID: "ledger")
        src.close()
        return (master, appKey, [BasePackageVersionRecord(snapshot: s1, migrations: []),
                                 BasePackageVersionRecord(snapshot: s2, migrations: [2])], s2, export)
    }

    private func makeInput(_ s: (master: String, appKey: String, chain: [BasePackageVersionRecord],
                                 target: BasePackageSnapshot, export: BaseRecordsExport)) -> BaseRebuildInput {
        BaseRebuildInput(masterKeyPayload: s.master, appKeys: ["ledger": s.appKey],
                         packageVersionRecords: s.chain, targetSnapshot: s.target, records: s.export)
    }

    /// 六步重建：新设备上从同步源一次性恢复（密钥/版本链/子库/迁移/数据/Card/能力搜索面全就位）。
    func testRebuildFreshDeviceFullSixSteps() throws {
        let s = try makeSender(tmpDir.appendingPathComponent("sender", isDirectory: true))
        let dst = try BaseLibraryStore(directory: tmpDir.appendingPathComponent("dst", isDirectory: true))
        defer { dst.close() }

        let result = try dst.rebuildApp(from: makeInput(s))
        XCTAssertTrue(result.rebuilt)
        XCTAssertEqual(result.packageVersion, 2)
        XCTAssertEqual(result.recordsDigest, try s.export.digest())
        // ① 主密钥 ② App 密钥。
        XCTAssertEqual(try dst.syncKeyPayload(kind: "master", appID: ""), s.master)
        XCTAssertEqual(try dst.syncKeyPayload(kind: "app", appID: "ledger"), s.appKey)
        // ③ 版本链指纹一致。
        let fps = try dst.allPackageVersionFingerprints(appID: "ledger")
        XCTAssertEqual(fps[1], try s.chain[0].snapshot.digest())
        XCTAssertEqual(fps[2], try s.chain[1].snapshot.digest())
        // ④⑤ 子库 + 迁移随包重放（v1→v2：budgets 由迁移建立，迁移记录 [2]）。
        let store = try dst.openStore(appID: "ledger")
        XCTAssertTrue(try store.tableExists("expenses"))
        XCTAssertTrue(try store.tableExists("budgets"))
        XCTAssertEqual(try store.appliedMigrations(), [2])
        XCTAssertEqual(try store.latestPackageVersion(), 2)
        // ⑥ 数据。
        XCTAssertEqual(try store.fetch(id: "rec_1", table: "expenses")?["amount"], .number(12.5))
        store.close()
        // ⑦⑧ Card + 能力搜索面（注册行在，Card 可编译、purpose 一致）。
        XCTAssertEqual(try dst.packageVersion(appID: "ledger"), 2)
        let card = try XCTUnwrap(try dst.appCard(appID: "ledger"))
        XCTAssertEqual(card["purpose"] as? String, "个人收支")
    }

    /// 幂等重入：同输入再次 rebuild → rebuilt false、状态不变（版本/链/数据均不重放）。
    func testRebuildIdempotentReentry() throws {
        let s = try makeSender(tmpDir.appendingPathComponent("sender", isDirectory: true))
        let dst = try BaseLibraryStore(directory: tmpDir.appendingPathComponent("dst", isDirectory: true))
        defer { dst.close() }
        let input = makeInput(s)
        let first = try dst.rebuildApp(from: input)
        XCTAssertTrue(first.rebuilt)
        let second = try dst.rebuildApp(from: input)
        XCTAssertFalse(second.rebuilt)
        XCTAssertEqual(second.packageVersion, 2)
        XCTAssertEqual(second.recordsDigest, try s.export.digest())
        XCTAssertEqual(try dst.packageVersion(appID: "ledger"), 2)
        XCTAssertEqual(try dst.allPackageVersionFingerprints(appID: "ledger").count, 2)
        let store = try dst.openStore(appID: "ledger")
        XCTAssertEqual(try store.appliedMigrations(), [2])
        XCTAssertEqual(try store.fetch(id: "rec_1", table: "expenses")?["amount"], .number(12.5))
        store.close()
    }

    /// 版本链缺失 → MIGRATION_FAILED（无法确定性重建）。
    func testRebuildMissingVersionChainRejected() throws {
        let s = try makeSender(tmpDir.appendingPathComponent("sender", isDirectory: true))
        let dst = try BaseLibraryStore(directory: tmpDir.appendingPathComponent("dst", isDirectory: true))
        defer { dst.close() }
        // 只给 v2，缺链头 v1。
        let broken = BaseRebuildInput(masterKeyPayload: s.master, appKeys: ["ledger": s.appKey],
                                      packageVersionRecords: [s.chain[1]],
                                      targetSnapshot: s.target, records: s.export)
        XCTAssertThrowsError(try dst.rebuildApp(from: broken)) { error in
            XCTAssertEqual((error as? BaseError)?.code, BaseErrorCode.migrationFailed.rawValue)
        }
    }

    /// 版本记录指纹冲突（同版本不同内容）→ VERSION_MISMATCH（内容寻址冲突）。
    /// 场景：dst 已成功重建（真 v2 记录在链）→ 再用同版本但不同内容的假 v2 重入 → 冲突拒写。
    func testRebuildConflictingVersionRecordRejected() throws {
        let s = try makeSender(tmpDir.appendingPathComponent("sender", isDirectory: true))
        let dst = try BaseLibraryStore(directory: tmpDir.appendingPathComponent("dst", isDirectory: true))
        defer { dst.close() }
        // 先成功重建。
        let first = try dst.rebuildApp(from: makeInput(s))
        XCTAssertTrue(first.rebuilt)
        // 假 v2：与真实 v2 同版本但 schema 不同（指纹必然不同）。
        var fakeSchema = schema2()
        var fakeTables = (fakeSchema["tables"] as? [[String: Any]]) ?? []
        fakeTables[1]["fields"] = [["name": "limit", "type": "number"], ["name": "extra", "type": "text"]]
        fakeSchema["tables"] = fakeTables
        let fakeS2 = try BaseLibraryStore(directory: tmpDir.appendingPathComponent("fake", isDirectory: true))
        _ = try fakeS2.createApp(manifest: manifest("ledger"), schemaObject: fakeSchema, guide: guide("ledger"))
        let fakeSnap = try fakeS2.packageSnapshot(appID: "ledger")
        let snapV2 = BasePackageSnapshot(appID: "ledger", packageVersion: 2,
                                         manifest: fakeSnap.manifestObject, schema: fakeSnap.schemaObject,
                                         methods: fakeSnap.methodsObjects, guide: fakeSnap.guideObject)
        fakeS2.close()

        let conflict = BaseRebuildInput(masterKeyPayload: s.master, appKeys: ["ledger": s.appKey],
                                        packageVersionRecords: [s.chain[0], BasePackageVersionRecord(snapshot: snapV2, migrations: [2])],
                                        targetSnapshot: s.target, records: s.export)
        XCTAssertThrowsError(try dst.rebuildApp(from: conflict)) { error in
            XCTAssertEqual((error as? BaseError)?.code, BaseErrorCode.versionMismatch.rawValue)
        }
        // 冲突后原状态不变（真 v2 指纹仍在）。
        XCTAssertEqual(try dst.allPackageVersionFingerprints(appID: "ledger")[2], try s.chain[1].snapshot.digest())
    }

    /// E2EE 端到端：sender 加密行数据导出 → receiver 拉密钥解密 → 重建灌数据。
    func testRebuildE2EESyncEndToEnd() throws {
        let senderDir = tmpDir.appendingPathComponent("sender", isDirectory: true)
        let s = try makeSender(senderDir)
        // 重开 sender 以执行加密（makeSender 已 close，这里用保存的载荷即可，无需重开）。
        let src = try BaseLibraryStore(directory: senderDir)
        // 传输：加密行数据导出。
        let envelope = try src.encryptSyncPayload(try s.export.canonicalData(), for: "ledger")
        // 拉包状态/密钥：sender 的 base_keys 记录。
        let keys = try src.readSyncKeys()
        let appKeyPayload = try XCTUnwrap(
            keys.first { $0["kind"] as? String == "app" && $0["app_id"] as? String == "ledger" }?["payload_json"] as? String)
        let masterPayload = try XCTUnwrap(
            keys.first { $0["kind"] as? String == "master" }?["payload_json"] as? String)
        src.close()

        // receiver：新设备。先「拉包状态/密钥」落库（K4 语义：解密侧必须已有密钥才能解），
        // 再解密行数据导出。
        let dst = try BaseLibraryStore(directory: tmpDir.appendingPathComponent("dst", isDirectory: true))
        defer { dst.close() }
        try dst.saveSyncKey(keyID: "master_key", kind: "master", appID: "", payloadJSON: masterPayload)
        try dst.saveSyncKey(keyID: "app_key_ledger", kind: "app", appID: "ledger", payloadJSON: appKeyPayload)
        let plain = try dst.decryptSyncPayload(envelope, for: "ledger")
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: plain) as? [String: Any])
        let reExport = try reconstructExport(from: obj)
        XCTAssertEqual(try reExport.digest(), try s.export.digest())

        let input = BaseRebuildInput(masterKeyPayload: masterPayload, appKeys: ["ledger": appKeyPayload],
                                     packageVersionRecords: s.chain, targetSnapshot: s.target, records: reExport)
        let result = try dst.rebuildApp(from: input)
        XCTAssertTrue(result.rebuilt)
        XCTAssertEqual(result.recordsDigest, try s.export.digest())
        let store = try dst.openStore(appID: "ledger")
        XCTAssertEqual(try store.fetch(id: "rec_1", table: "expenses")?["amount"], .number(12.5))
        store.close()
    }

    /// 从 canonicalData 反序列化回 BaseRecordsExport（E2EE 解密后重建）。
    private func reconstructExport(from obj: [String: Any]) throws -> BaseRecordsExport {
        let appID = obj["appID"] as? String ?? ""
        let version = (obj["packageVersion"] as? NSNumber)?.intValue ?? 0
        let tables = (obj["tables"] as? [[String: Any]] ?? []).map { t in
            BaseRecordsTable(table: t["table"] as? String ?? "",
                             rows: (t["rows"] as? [[String: Any]] ?? []).map { row in
                                 var d: [String: JSONValue] = [:]
                                 for (k, v) in row { d[k] = JSONValue(json: v) ?? .null }
                                 return d
                             })
        }
        return BaseRecordsExport(appID: appID, packageVersion: version, tables: tables)
    }
}
