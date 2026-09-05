import Foundation
import CryptoKit

/// M3-K1 · 不可变包快照：AppPackage 四件套（manifest/schema/methods/guide）+ 版本 的确定性序列化。
///
/// 这是「应用整体同步」的基本单位：同包必同字节（canonicalData）、必同指纹（digest），
/// 支撑 golden 三端 SHA-256 对账（同包同 Card、同方法同结果）与 1MiB 分块校验。
///
/// 四件套以 `JSONValue` 存储（Sendable/Equatable），`canonicalData()` 产出键排序的确定性 JSON；
/// 恢复时经 `*Object` 访问器还原为 Foundation 字典交给 `createApp`。guide 为 App Guide
/// 十一段结构化对象（契约 base.app.create 的 guide 是 object，v0.12 无字符串指南）。
public struct BasePackageSnapshot: Sendable, Equatable {
    public var appID: String
    public var packageVersion: Int
    public var manifest: JSONValue
    public var schema: JSONValue?
    public var methods: [JSONValue]?
    public var guide: JSONValue

    public init(
        appID: String,
        packageVersion: Int,
        manifest: [String: Any],
        schema: [String: Any]?,
        methods: [[String: Any]]?,
        guide: [String: Any]
    ) {
        self.appID = appID
        self.packageVersion = packageVersion
        self.manifest = JSONValue(json: manifest) ?? .object([:])
        self.schema = schema.flatMap { JSONValue(json: $0) }
        self.methods = methods?.map { JSONValue(json: $0) ?? .object([:]) }
        self.guide = JSONValue(json: guide) ?? .object([:])
    }

    // MARK: 恢复访问器（还原为 Foundation 字典）

    /// manifest 字典（含 appID/name/domain/purpose/…）。
    public var manifestObject: [String: Any] {
        manifest.jsonObject as? [String: Any] ?? [:]
    }

    /// schema 对象（缺省空表集）。
    public var schemaObject: [String: Any] {
        (schema?.jsonObject as? [String: Any]) ?? ["tables": []]
    }

    /// methods 数组。
    public var methodsObjects: [[String: Any]] {
        (methods ?? []).map { $0.jsonObject as? [String: Any] ?? [:] }
    }

    /// guide 对象。
    public var guideObject: [String: Any] {
        guide.jsonObject as? [String: Any] ?? [:]
    }

    /// 载荷字典（四件套 + 版本）。
    public var payload: [String: Any] {
        var d: [String: Any] = [
            "appID": appID,
            "packageVersion": packageVersion,
            "manifest": manifestObject,
            "guide": guideObject,
        ]
        if let schema { d["schema"] = schema.jsonObject }
        if let methods { d["methods"] = methods.map { $0.jsonObject } }
        return d
    }

    /// 确定性规范 JSON：键排序（sortedKeys），同包必同字节。
    public func canonicalData() throws -> Data {
        try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .fragmentsAllowed])
    }

    /// SHA-256 十六进制指纹（包版本指纹，golden 对账 / 1MiB 分块校验）。
    public func digest() throws -> String {
        let data = try canonicalData()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
