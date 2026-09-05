import Foundation
import CryptoKit

/// M3-K9：同步类 golden 执行器。
///
/// 读入 M3-K9 canonical sync fixture（`testdata/base/golden-sync/*.json`，Mac 拷贝在
/// `Tests/ConnorGraphBaseTests/GoldenSync/`），在真实内核上执行同步往返并产出确定性结果：
/// - `packageFingerprint`：包快照确定性 JSON 的 SHA-256（同包同指纹）
/// - `cardFingerprint`：编译 Card 规范化 JSON（去时间戳）的 SHA-256（同包同 Card）
/// - `guideFingerprint`：指南全文规范化 JSON 的 SHA-256（指南全文一致）
/// - `methodResult`：方法 DAG 在种子数据上的确定性执行结果（同方法同结果）
///
/// 期望值来自内核实际输出（Mac 为参考实现），canonical 固化后三端字节一致；
/// 与既有 M1-K8 `BaseGoldenRunner`（工具执行类）互补，本类为同步对象类。
public enum BaseSyncGoldenRunner {

    // MARK: - Fixture 模型（与 canonical sync fixture 结构对齐）

    public struct SyncFixture: Decodable {
        public let name: String
        public let kind: String?

        public struct Package: Decodable {
            public let manifest: [String: JSONValue]
            public let schema: [String: JSONValue]
            public let methods: [JSONValue]
            public let guide: [String: JSONValue]
        }

        public struct Invoke: Decodable {
            public let method: String
            public let args: [String: JSONValue]
        }

        public struct Then: Decodable {
            public let packageFingerprint: String?
            public let cardFingerprint: String?
            public let guideFingerprint: String?
            public let methodResult: JSONValue?
        }

        public let package: Package
        public let seed: [String: [[String: JSONValue]]]?
        public let invoke: Invoke?
        public let then: Then
    }

    /// 捕获执行结果：在指定目录建库并返回确定性信封（键与 fixture.then 对齐）。
    public static func capture(_ fixture: SyncFixture, in directory: URL) throws -> [String: Any] {
        let manifest = object(fixture.package.manifest)
        let appID = manifest["appID"] as? String ?? "acct"

        let store = try BaseLibraryStore(directory: directory)
        defer { store.close() }

        let snapshot = BasePackageSnapshot(
            appID: appID,
            packageVersion: 1,
            manifest: manifest,
            schema: object(fixture.package.schema),
            methods: fixture.package.methods.map { $0.jsonObject } as? [[String: Any]] ?? [],
            guide: object(fixture.package.guide)
        )
        _ = try store.applyPackageSnapshot(snapshot)

        // 1) 同包同指纹：包快照确定性 JSON 的 SHA-256
        let packageFingerprint = try store.packageSnapshot(appID: appID).digest()

        // 2) 同包同 Card：编译 Card 规范化（去时间戳）JSON 的 SHA-256
        let card = try store.appCard(appID: appID) ?? [:]
        var cardNorm = card
        cardNorm["createdAt"] = nil
        cardNorm["updatedAt"] = nil
        let cardFingerprint = sha256Hex(canonicalData(cardNorm))

        // 3) 指南全文一致：指南规范化 JSON 的 SHA-256
        let guideFingerprint = sha256Hex(canonicalData(object(fixture.package.guide)))

        // 4) 同方法同结果：灌种子数据后执行方法，产出确定性结果
        var methodResult: Any = NSNull()
        if let invoke = fixture.invoke {
            let sub = try store.openStore(appID: appID)
            if let seed = fixture.seed {
                for (table, rows) in seed {
                    for row in rows {
                        var values = row
                        let id = values.removeValue(forKey: "id")?.jsonObject as? String ?? ""
                        try sub.insert(id: id, table: table, values: values, meta: [:])
                    }
                }
            }
            guard let methodJSON = fixture.package.methods.first(where: {
                ($0.jsonObject as? [String: Any])?["name"] as? String == invoke.method
            })?.jsonObject as? [String: Any] else {
                throw BaseError(code: .internal, message: "方法缺失: \(invoke.method)", hint: "")
            }
            let method = try BaseMethodDef(json: methodJSON)
            let schema = try BaseSchemaValidator.parseSchema(object(fixture.package.schema), validateRelations: false)
            let interpreter = BaseMethodInterpreter(store: sub, schema: schema)
            let args = object(invoke.args)
            let result = try interpreter.invoke(method: method, args: args, resolver: { _ in nil }, appID: appID)
            methodResult = result.data.jsonObject
        }

        return [
            "packageFingerprint": packageFingerprint,
            "cardFingerprint": cardFingerprint,
            "guideFingerprint": guideFingerprint,
            "methodResult": methodResult,
        ]
    }

    /// 与 fixture.then 比对，返回失败明细列表（空 = 全对账通过）。
    public static func compare(actual: [String: Any], expected: SyncFixture.Then) -> [String] {
        var failures: [String] = []
        func check(_ key: String, _ actualValue: Any, _ expectedValue: Any?) {
            if let expectedValue {
                let a = canonicalData(actualValue)
                let e = canonicalData(expectedValue)
                if a != e {
                    failures.append("\(key) 不一致\n  期望: \(String(data: e, encoding: .utf8) ?? "?")\n  实际: \(String(data: a, encoding: .utf8) ?? "?")")
                }
            }
        }
        check("packageFingerprint", actual["packageFingerprint"] ?? "", expected.packageFingerprint)
        check("cardFingerprint", actual["cardFingerprint"] ?? "", expected.cardFingerprint)
        check("guideFingerprint", actual["guideFingerprint"] ?? "", expected.guideFingerprint)
        check("methodResult", actual["methodResult"] ?? NSNull(), expected.methodResult?.jsonObject)
        return failures
    }

    // MARK: - Helpers

    private static func object(_ dict: [String: JSONValue]) -> [String: Any] {
        dict.mapValues { $0.jsonObject }
    }

    private static func canonicalData(_ object: Any) -> Data {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed]) else {
            return Data()
        }
        return data
    }

    private static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
