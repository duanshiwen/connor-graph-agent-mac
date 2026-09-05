import XCTest
import Foundation
@testable import ConnorGraphBase

/// M3-K4：E2EE 层——base_keys 密钥生成（幂等）+ 同步载荷 AES-256-GCM 加解密。
///
/// 覆盖：master/app 密钥生成且幂等（不重复落库）；包/行数据 canonicalData 加解密往返一致；
/// 不同 App 密钥不互通（解密抛错）；篡改密文鉴权失败（抛错）；envelope 形状（算法/字段）。
final class BaseE2EECTests: XCTestCase {

    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("base-sync-k4-\(UUID().uuidString)", isDirectory: true)
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

    private func makeApp(_ library: BaseLibraryStore, appID: String) throws {
        _ = try library.createApp(manifest: manifest(appID), schemaObject: schema(), guide: guide(appID), methods: [])
    }

    /// master/app 密钥生成，幂等（不重复落库、返回同载荷）。
    func testKeyGenerationIsIdempotent() throws {
        let library = try BaseLibraryStore(directory: tmpDir)
        defer { library.close() }
        let m1 = try library.ensureMasterKey()
        let m2 = try library.ensureMasterKey()
        XCTAssertEqual(m1, m2)
        XCTAssertFalse(m1.isEmpty)

        let a1 = try library.syncAppKey(appID: "ledger")
        let a2 = try library.syncAppKey(appID: "ledger")
        XCTAssertEqual(a1, a2)
        XCTAssertFalse(a1.isEmpty)

        let b1 = try library.syncAppKey(appID: "other")
        XCTAssertNotEqual(a1, b1)

        let keys = try library.readSyncKeys()
        XCTAssertEqual(keys.count, 3) // master + ledger + other
        XCTAssertEqual(Set(keys.compactMap { $0["kind"] as? String }), ["master", "app"])
    }

    /// 包快照 canonicalData 加解密往返一致。
    func testEncryptDecryptPackageRoundTrip() throws {
        let library = try BaseLibraryStore(directory: tmpDir)
        defer { library.close() }
        try makeApp(library, appID: "ledger")
        let snap = try library.packageSnapshot(appID: "ledger")
        let canonical = try snap.canonicalData()

        let envelope = try library.encryptSyncPayload(canonical, for: "ledger")
        let plain = try library.decryptSyncPayload(envelope, for: "ledger")
        XCTAssertEqual(plain, canonical)
    }

    /// 行数据导出 canonicalData 加解密往返一致（E2EE 通道覆盖两类载荷）。
    func testEncryptDecryptRecordsRoundTrip() throws {
        let library = try BaseLibraryStore(directory: tmpDir)
        defer { library.close() }
        try makeApp(library, appID: "ledger")
        let store = try library.openStore(appID: "ledger")
        try store.insert(id: "rec_1", table: "expenses",
                         values: ["amount": .number(12.5), "category": .string("food")],
                         meta: ["createdAt": "2026-09-05T00:00:00Z"])
        store.close()
        let export = try library.exportRecords(appID: "ledger")
        let canonical = try export.canonicalData()

        let envelope = try library.encryptSyncPayload(canonical, for: "ledger")
        let plain = try library.decryptSyncPayload(envelope, for: "ledger")
        XCTAssertEqual(plain, canonical)
    }

    /// 不同 App 密钥不互通：A 的密文用 B 的密钥解 → 鉴权失败抛错。
    func testDifferentAppKeysNotInterchangeable() throws {
        let library = try BaseLibraryStore(directory: tmpDir)
        defer { library.close() }
        _ = try library.syncAppKey(appID: "ledger")
        _ = try library.syncAppKey(appID: "other")
        let data = Data("hello-sync".utf8)
        let envelope = try library.encryptSyncPayload(data, for: "ledger")

        XCTAssertThrowsError(try library.decryptSyncPayload(envelope, for: "other"))
    }

    /// 篡改密文 → 鉴权失败抛错（E2EE 完整性）。
    func testTamperedCiphertextFails() throws {
        let library = try BaseLibraryStore(directory: tmpDir)
        defer { library.close() }
        _ = try library.syncAppKey(appID: "ledger")
        let data = Data("hello-sync".utf8)
        var envelope = try library.encryptSyncPayload(data, for: "ledger")

        var ct = Data(base64Encoded: envelope["ciphertext"] as! String)!
        if ct.isEmpty { ct = Data([0x00]) }
        ct[ct.startIndex] ^= 0xFF
        envelope["ciphertext"] = ct.base64EncodedString()

        XCTAssertThrowsError(try library.decryptSyncPayload(envelope, for: "ledger"))
    }

    /// envelope 形状：算法 AES-256-GCM，nonce/ciphertext/tag 均为非空 base64。
    func testEnvelopeShape() throws {
        let library = try BaseLibraryStore(directory: tmpDir)
        defer { library.close() }
        _ = try library.syncAppKey(appID: "ledger")
        let envelope = try library.encryptSyncPayload(Data("x".utf8), for: "ledger")

        XCTAssertEqual(envelope["algorithm"] as? String, "AES-256-GCM")
        XCTAssertFalse((envelope["nonce"] as? String ?? "").isEmpty)
        XCTAssertFalse((envelope["ciphertext"] as? String ?? "").isEmpty)
        XCTAssertFalse((envelope["tag"] as? String ?? "").isEmpty)
        XCTAssertFalse((envelope["createdAt"] as? String ?? "").isEmpty)
    }
}
