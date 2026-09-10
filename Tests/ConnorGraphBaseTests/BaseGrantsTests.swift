import XCTest
import Foundation
@testable import ConnorGraphBase

/// M4-K1/K2：权限能力位 grant（base.app.grant）——ACL 内核 + 随包状态同步。
///
/// 覆盖：
/// - 门控：仅 shared 可见性可授权/回收（private 拒绝 PERMISSION_DENIED，public 全公开无需授权）。
/// - 幂等 + 包版本提交：grant/revoke 幂等，授权状态变更即写新不可变版本记录 + latest 单调前移。
/// - 随包往返：ACL 随包快照同步，对端 applyPackageSnapshot 恢复授权（新设备免重新授权）。
/// - 指纹稳定：private 无 ACL 应用快照不含 acls 键，K9 固化指纹不受影响。
final class BaseGrantsTests: XCTestCase {

    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("base-m4-grant-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tmpDir { try? FileManager.default.removeItem(at: tmpDir) }
    }

    private func makeStore() throws -> (BaseLibraryStore, URL) {
        let dir = tmpDir.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (try BaseLibraryStore(directory: dir), dir)
    }

    private func manifest(_ appID: String, visibility: String) -> [String: Any] {
        ["appID": appID, "name": "共享应用", "domain": "test", "purpose": "授权测试",
         "visibility": visibility, "requiredCapabilities": [], "imports": [],
         "riskLevel": "low", "sdkVersion": 1]
    }

    private func schema() -> [String: Any] {
        ["tables": [["name": "items", "fields": [
            ["name": "name", "type": "text"],
            ["name": "amount", "type": "number", "required": true]
        ]]]]
    }

    /// M7 双态硬切：guide 须为 {authoring, usage}（测试夹具与内核同一口径）。
    private func guide(_ appID: String) -> [String: Any] {
        let state: [String: Any] = ["appID": appID, "whenToUse": "记一笔时用",
                                    "whenNotToUse": "闲聊时不用", "sections": []]
        return ["authoring": state, "usage": state]
    }

    // MARK: - 门控

    /// 仅 shared 可见性可授权/回收；private 拒绝 PERMISSION_DENIED。
    func testGrantRequiresSharedVisibility() throws {
        let (library, _) = try makeStore()
        defer { library.close() }
        let schemaDict = schema()
        // private 应用拒绝。
        _ = try library.createApp(
            manifest: manifest("priv", visibility: "private"),
            schemaObject: schemaDict, guide: guide("priv"), methods: [])
        XCTAssertThrowsError(try library.grantAccess(appID: "priv", peer: "alice", grant: true)) { err in
            guard let base = err as? BaseError else {
                return XCTFail("期望 BaseError，实际 \(err)")
            }
            XCTAssertEqual(base.code, BaseErrorCode.permissionDenied.rawValue)
        }
        // shared 应用成功授权。
        _ = try library.createApp(
            manifest: manifest("shared", visibility: "shared"),
            schemaObject: schemaDict, guide: guide("shared"), methods: [])
        let version = try library.grantAccess(appID: "shared", peer: "alice", grant: true)
        XCTAssertEqual(version, 2) // v1 → v2（授权状态变更即新版本记录）
    }

    // MARK: - 幂等 + 包版本提交

    /// grant/revoke 幂等；授权状态变更即写新不可变版本记录 + latest 单调前移。
    func testGrantRevokeIdempotentAndBumpsVersion() throws {
        let (library, _) = try makeStore()
        defer { library.close() }
        let schemaDict = schema()
        _ = try library.createApp(
            manifest: manifest("shared", visibility: "shared"),
            schemaObject: schemaDict, guide: guide("shared"), methods: [])
        _ = try library.grantAccess(appID: "shared", peer: "alice", grant: true)
        _ = try library.grantAccess(appID: "shared", peer: "alice", grant: true) // 幂等重授权
        let grants = try library.grants(appID: "shared")
        XCTAssertEqual(grants.count, 1)
        XCTAssertEqual(grants[0]["peer"] as? String, "alice")
        XCTAssertEqual((grants[0]["granted"] as? Int64) ?? 0, 1)
        // 版本：v1 → grant → v2 → 重授权 → v3（每次授权状态变更都写版本记录）
        XCTAssertEqual(try library.packageVersion(appID: "shared"), 3)
        // revoke 幂等
        _ = try library.grantAccess(appID: "shared", peer: "alice", grant: false)
        let after = try library.grants(appID: "shared")
        XCTAssertEqual((after[0]["granted"] as? Int64) ?? 1, 0)
        XCTAssertEqual(try library.packageVersion(appID: "shared"), 4)
        // 版本链含新记录
        let fingerprints = try library.allPackageVersionFingerprints(appID: "shared")
        XCTAssertEqual(fingerprints.keys.max(), 4)
    }

    // MARK: - 随包往返（新设备免重新授权）

    /// ACL 随包快照同步：src 授权 → snapshot 含 ACL → 对端 applyPackageSnapshot 恢复授权。
    func testAclRidesSnapshotRoundtrip() throws {
        let (src, _) = try makeStore()
        defer { src.close() }
        let schemaDict = schema()
        _ = try src.createApp(
            manifest: manifest("shared", visibility: "shared"),
            schemaObject: schemaDict, guide: guide("shared"), methods: [])
        _ = try src.grantAccess(appID: "shared", peer: "alice", grant: true)
        _ = try src.grantAccess(appID: "shared", peer: "bob", grant: false)
        let snapshot = try src.packageSnapshot(appID: "shared")
        // 快照携带 ACL 段（非空）
        let acls = snapshot.aclsObjects
        XCTAssertEqual(acls.count, 2)
        XCTAssertTrue(acls.contains { ($0["peer"] as? String) == "alice" })
        XCTAssertTrue(acls.contains { ($0["peer"] as? String) == "bob" })
        // 对端（空库）applyPackageSnapshot 恢复授权，免重新授权
        let (dst, _) = try makeStore()
        defer { dst.close() }
        _ = try dst.applyPackageSnapshot(snapshot)
        let restored = try dst.grants(appID: "shared")
        XCTAssertEqual(restored.count, 2)
        XCTAssertEqual(try dst.packageVersion(appID: "shared"), snapshot.packageVersion)
    }

    // MARK: - 指纹稳定（private 无 ACL）

    /// private 无 ACL 应用：快照不含 acls 键、指纹确定性（K9 固化指纹不受影响）。
    func testPrivateWithoutAclKeepsFingerprintStable() throws {
        let (library, _) = try makeStore()
        defer { library.close() }
        let schemaDict = schema()
        _ = try library.createApp(
            manifest: manifest("priv", visibility: "private"),
            schemaObject: schemaDict, guide: guide("priv"), methods: [])
        let snapshot = try library.packageSnapshot(appID: "priv")
        XCTAssertTrue(snapshot.aclsObjects.isEmpty)
        let payload = snapshot.payload
        XCTAssertNil(payload["acls"]) // 非空才输出
        let d1 = try snapshot.digest()
        let d2 = try library.packageSnapshot(appID: "priv").digest()
        XCTAssertEqual(d1, d2)
    }
}
