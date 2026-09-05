import Foundation
import Testing
@testable import ConnorGraphBase

/// M3-K9：同步类 golden 三端 SHA-256 对账。
///
/// 读入 canonical sync fixture（`testdata/base/golden-sync/*.json`，Mac 拷贝在
/// `Tests/ConnorGraphBaseTests/GoldenSync/`），在真实内核上执行同步往返，产出
/// packageFingerprint / cardFingerprint / guideFingerprint / methodResult 四组
/// 确定性结果，与 fixture `then` 逐项 SHA-256 对账（同包同 Card、同方法同结果、指南全文一致）。
@Suite("Base · M3-K9 同步 golden 对账")
struct BaseSyncGoldenTests {

    private static var resourceURL: URL? {
        Bundle.module.resourceURL?.appendingPathComponent("GoldenSync", isDirectory: true)
    }

    @Test("GoldenSync fixtures 全部对账通过")
    func syncGoldenAllMatch() throws {
        let dir = try #require(Self.resourceURL, "GoldenSync 资源目录缺失")
        let files = try FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }

        // 非空：至少 1 个同步 fixture 对账
        #expect(!files.isEmpty, "GoldenSync 目录应包含同步 golden fixture")

        for file in files {
            let data = try Data(contentsOf: file)
            let fixture = try JSONDecoder().decode(BaseSyncGoldenRunner.SyncFixture.self, from: data)

            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("k9-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmp) }

            let actual = try BaseSyncGoldenRunner.capture(fixture, in: tmp)
            let failures = BaseSyncGoldenRunner.compare(actual: actual, expected: fixture.then)
            #expect(
                failures.isEmpty,
                "fixture \(fixture.name) 对账失败:\n\(failures.joined(separator: "\n\n"))"
            )
        }
    }

    @Test("GoldenSync 确定性：同 fixture 两次捕获指纹稳定")
    func syncGoldenDeterministic() throws {
        let dir = try #require(Self.resourceURL, "GoldenSync 资源目录缺失")
        let files = try FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard let first = files.first else { return }

        let data = try Data(contentsOf: first)
        let fixture = try JSONDecoder().decode(BaseSyncGoldenRunner.SyncFixture.self, from: data)

        func captureOnce() throws -> [String: Any] {
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("k9d-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmp) }
            return try BaseSyncGoldenRunner.capture(fixture, in: tmp)
        }

        let a = try captureOnce()
        let b = try captureOnce()
        #expect(
            (a["packageFingerprint"] as? String) == (b["packageFingerprint"] as? String),
            "包指纹两次捕获应一致"
        )
        #expect(
            (a["cardFingerprint"] as? String) == (b["cardFingerprint"] as? String),
            "Card 指纹两次捕获应一致"
        )
    }
}
