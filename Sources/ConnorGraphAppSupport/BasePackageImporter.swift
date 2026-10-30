import Foundation
import ConnorGraphBase

public enum BasePackageImporter {
    public static func review(_ data: Data) throws -> String {
        guard data.count <= 10_000_000 else { throw ImportError.invalid("小程序定义包超过 10 MB。") }
        guard var package = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var manifest = package["manifest"] as? [String: Any],
              package["schema"] is [String: Any], package["guide"] is [String: Any] else {
            throw ImportError.invalid("包须完整包含 manifest、schema、guide；methods 默认为空数组。")
        }
        guard package["data"] == nil else { throw ImportError.invalid("定义包不能包含运行数据；请通过小程序的数据导入方法处理，避免遗漏记录。") }
        guard Set(package.keys).isSubset(of: Set(["manifest", "schema", "guide", "methods"])) else { throw ImportError.invalid("定义包包含未知顶层字段，未丢弃或导入这些内容。") }
        guard let methods = (package["methods"] ?? []) as? [[String: Any]] else { throw ImportError.invalid("methods 必须是数组。") }
        package["methods"] = methods
        for method in methods { _ = try BaseMethodDef(json: method) }
        manifest["visibility"] = "private"
        package["manifest"] = manifest
        let output = try JSONSerialization.data(withJSONObject: package, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: output, as: UTF8.self)
    }
    public static func install(_ reviewedJSON: String, library: BaseLibraryStore) throws -> String {
        let normalized = try review(Data(reviewedJSON.utf8))
        let package = try JSONSerialization.jsonObject(with: Data(normalized.utf8)) as! [String: Any]
        let card = try library.createApp(manifest: package["manifest"] as! [String: Any], schemaObject: package["schema"] as! [String: Any], guide: package["guide"] as! [String: Any], methods: package["methods"] as! [[String: Any]])
        return card["appID"] as? String ?? ""
    }
    public enum ImportError: Error, LocalizedError {
        case invalid(String)
        public var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
    }
}
