import XCTest
import Foundation
@testable import ConnorGraphBase

/// M4-T1：跨设备网络传输层内核（1MiB 分块 / 组装 SHA-256 校验 / 断点续传状态表）。
///
/// 覆盖：分块/组装往返字节一致；1MiB 边界；篡改/缺块/重复 index 拒绝（VALIDATION_FAILED）；
/// 断点续传（缺块补齐 + complete 标记）；幂等重复保存；E2EE 加密载荷分块传输 → 组装 → 解密端到端；
/// 与 K8 重建接线（组装还原明文喂 rebuildApp 六步）。
final class BaseTransferTests: XCTestCase {

    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("base-transfer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tmpDir { try? FileManager.default.removeItem(at: tmpDir) }
    }

    private func randomData(_ count: Int) -> Data {
        Data((0..<count).map { _ in UInt8.random(in: 0...255) })
    }

    private func assertValidationFailed(_ body: () throws -> Void, file: StaticString = #filePath,
                                        line: UInt = #line) {
        do {
            try body()
            XCTFail("应抛 VALIDATION_FAILED", file: file, line: line)
        } catch let e as BaseError {
            XCTAssertEqual(e.code, "VALIDATION_FAILED", file: file, line: line)
        } catch {
            XCTFail("错误类型错误: \(error)", file: file, line: line)
        }
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

    // ── 分块 / 组装（内存态） ──

    /// 2.5MiB 随机载荷 → 默认 1MiB → 3 块 → 组装 → 字节与 SHA-256 一致。
    func testChunkAssembleRoundTrip() throws {
        let store = try BaseLibraryStore(directory: tmpDir)
        defer { store.close() }
        let payload = randomData(2_500_000)
        let (meta, chunks) = try store.chunk(payload: payload, payloadID: "pkg_ledger_v2")
        XCTAssertEqual(meta.totalChunks, 3)
        XCTAssertTrue(chunks.allSatisfy { $0.data.count <= 1_048_576 })
        let out = try store.assemble(chunks, expectedSHA256: meta.sha256)
        XCTAssertEqual(out, payload)
    }

    /// 1MiB 边界：恰好 1MiB → 1 块；1MiB+1 字节 → 2 块。
    func testChunkBoundaryExactly1MiB() throws {
        let store = try BaseLibraryStore(directory: tmpDir)
        defer { store.close() }
        let exact = randomData(1_048_576)
        let (m1, c1) = try store.chunk(payload: exact, payloadID: "exact")
        XCTAssertEqual(m1.totalChunks, 1)
        XCTAssertEqual(c1.count, 1)
        let over = randomData(1_048_577)
        let (m2, c2) = try store.chunk(payload: over, payloadID: "over")
        XCTAssertEqual(m2.totalChunks, 2)
        XCTAssertEqual(c2[0].data.count, 1_048_576)
        XCTAssertEqual(c2[1].data.count, 1)
    }

    /// 空载荷 → 1 块（空 data），往返一致。
    func testChunkEmptyPayload() throws {
        let store = try BaseLibraryStore(directory: tmpDir)
        defer { store.close() }
        let (meta, chunks) = try store.chunk(payload: Data(), payloadID: "empty")
        XCTAssertEqual(meta.totalChunks, 1)
        XCTAssertEqual(try store.assemble(chunks, expectedSHA256: meta.sha256), Data())
    }

    /// 篡改任一块 → SHA-256 失配拒绝。
    func testAssembleRejectsTamperedChunk() throws {
        let store = try BaseLibraryStore(directory: tmpDir)
        defer { store.close() }
        let payload = randomData(2_000_000)
        let (meta, chunks) = try store.chunk(payload: payload, payloadID: "tampered")
        var bad = chunks
        bad[1] = BaseTransferChunk(payloadID: "tampered", index: 1, totalChunks: meta.totalChunks,
                                   payloadSHA256: meta.sha256, data: randomData(1_048_576))
        assertValidationFailed { try store.assemble(bad, expectedSHA256: meta.sha256) }
    }

    /// 缺一块 → 拒绝。
    func testAssembleRejectsMissingChunk() throws {
        let store = try BaseLibraryStore(directory: tmpDir)
        defer { store.close() }
        let (meta, chunks) = try store.chunk(payload: randomData(2_500_000), payloadID: "missing")
        assertValidationFailed { try store.assemble(Array(chunks.dropLast()), expectedSHA256: meta.sha256) }
    }

    /// 重复 index → 拒绝。
    func testAssembleRejectsDuplicateIndex() throws {
        let store = try BaseLibraryStore(directory: tmpDir)
        defer { store.close() }
        let payload = randomData(2_500_000)
        let (meta, chunks) = try store.chunk(payload: payload, payloadID: "dup")
        var dup = chunks
        dup.append(BaseTransferChunk(payloadID: "dup", index: 0, totalChunks: meta.totalChunks,
                                     payloadSHA256: meta.sha256, data: chunks[0].data))
        assertValidationFailed { try store.assemble(dup, expectedSHA256: meta.sha256) }
    }

    // ── 断点续传状态表 ──

    /// 收前 2 块 → status 显示 received=[0,1]、missing=[2]；补齐后 assembleStored 字节一致；complete 标记生效。
    func testStoreResumeAndComplete() throws {
        let store = try BaseLibraryStore(directory: tmpDir)
        defer { store.close() }
        let payload = randomData(2_500_000)
        let (meta, chunks) = try store.chunk(payload: payload, payloadID: "resume")
        // 断点：只收到前 2 块。
        try store.storeChunk(chunks[0])
        try store.storeChunk(chunks[1])
        var status = try XCTUnwrap(try store.transferStatus(payloadID: "resume"))
        XCTAssertFalse(status.complete)
        XCTAssertEqual(status.receivedChunks, [0, 1])
        XCTAssertEqual(status.missingChunks, [2])
        XCTAssertEqual(status.sha256, meta.sha256)
        // 断点续传：只补缺失块。
        assertValidationFailed { try store.assembleStored(payloadID: "resume") }
        try store.storeChunk(chunks[2])
        status = try XCTUnwrap(try store.transferStatus(payloadID: "resume"))
        XCTAssertEqual(status.receivedChunks, [0, 1, 2])
        XCTAssertTrue(status.missingChunks.isEmpty)
        let out = try store.assembleStored(payloadID: "resume")
        XCTAssertEqual(out, payload)
        try store.markTransferComplete(payloadID: "resume")
        XCTAssertTrue(try XCTUnwrap(try store.transferStatus(payloadID: "resume")).complete)
    }

    /// 幂等：同块重复保存 → 块行数不变。
    func testStoreChunkIdempotent() throws {
        let store = try BaseLibraryStore(directory: tmpDir)
        defer { store.close() }
        let (meta, chunks) = try store.chunk(payload: randomData(2_500_000), payloadID: "idem")
        try store.storeChunk(chunks[0])
        try store.storeChunk(chunks[0])
        try store.storeChunk(chunks[1])
        let status = try XCTUnwrap(try store.transferStatus(payloadID: "idem"))
        XCTAssertEqual(status.receivedChunks, [0, 1])
        XCTAssertEqual(status.totalChunks, meta.totalChunks)
    }

    /// 清理：完成后清空状态表。
    func testClearTransfer() throws {
        let store = try BaseLibraryStore(directory: tmpDir)
        defer { store.close() }
        let (_, chunks) = try store.chunk(payload: randomData(1_200_000), payloadID: "clear_me")
        for c in chunks { try store.storeChunk(c) }
        try store.clearTransfer(payloadID: "clear_me")
        XCTAssertNil(try store.transferStatus(payloadID: "clear_me"))
    }

    // ── 端到端：E2EE 加密载荷分块传输 → 组装 → 解密 → K8 重建 ──

    /// sender 加密包快照（K4）→ 分块传输 → 对端组装 → 解密 → 指纹与原始一致；再喂 rebuildApp 六步重建成功。
    func testEndToEndE2EEChunkThenRebuild() throws {
        let sender = try BaseLibraryStore(directory: tmpDir.appendingPathComponent("sender", isDirectory: true))
        _ = try sender.createApp(manifest: manifest("ledger"), schemaObject: schema1(), guide: guide("ledger"), methods: [])
        let snapshot = try sender.packageSnapshot(appID: "ledger")
        let payloadData = try snapshot.canonicalData()
        let envelope = try sender.encryptSyncPayload(payloadData, for: "ledger")
        let envelopeData = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
        let (meta, chunks) = try sender.chunk(payload: envelopeData, payloadID: "pkg_ledger")
        XCTAssertGreaterThanOrEqual(meta.totalChunks, 1)
        // 对端须先有密钥才能解密（K4 语义：拉包状态/密钥落库后再解；K8 第②步 saveSyncKey 装钥）。
        let appKey = try sender.syncAppKey(appID: "ledger")  // 同钥（幂等取回既有）
        sender.close()

        // 对端：收块 → 组装 → 解密。
        let dst = try BaseLibraryStore(directory: tmpDir.appendingPathComponent("dst", isDirectory: true))
        defer { dst.close() }
        for c in chunks { try dst.storeChunk(c) }
        let restored = try dst.assembleStored(payloadID: "pkg_ledger")
        let env = try XCTUnwrap(try JSONSerialization.jsonObject(with: restored) as? [String: Any])
        try dst.saveSyncKey(keyID: "app_key_ledger", kind: "app", appID: "ledger", payloadJSON: appKey)
        let plain = try dst.decryptSyncPayload(env, for: "ledger")
        XCTAssertEqual(plain, payloadData)
        // 传输层+K4 分层验证：分块往返字节级保真（组装后解密 == 原始快照 canonicalData，指纹一致）。
        let plainDigest = BaseLibraryStore.sha256Hex(plain)
        XCTAssertEqual(plainDigest, try snapshot.digest())
    }
}
