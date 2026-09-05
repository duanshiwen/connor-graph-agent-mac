import Foundation

/// Connor Base 平台契约加载器（Mac 端）。
///
/// 从本 target 的 Bundle 资源（`Resources/Contracts/`）加载契约 JSON。
/// 契约文件由 `scripts/sync-base-golden.sh` 从后端 canonical（`testdata/base/contract`）同步，
/// 三端 SHA-256 一致，禁止本仓手改。
public enum SDKContractLoader {

    /// 契约文件清单。
    public enum ContractFile: String, CaseIterable {
        case sdk = "base.sdk.v1"
        case appPackage = "app-package.schema"

        public var fileName: String { rawValue + ".json" }
    }

    public enum ContractError: Error, LocalizedError {
        case missingFile(String)
        case invalidJSON(String)

        public var errorDescription: String? {
            switch self {
            case .missingFile(let f):
                return "Connor Base 契约文件缺失: \(f)"
            case .invalidJSON(let f):
                return "Connor Base 契约文件不是合法 JSON 对象: \(f)"
            }
        }
    }

    /// 读取契约文件原始字节。
    public static func loadData(_ file: ContractFile, bundle: Bundle? = nil) throws -> Data {
        let resolved = bundle ?? .module
        guard let url = resolved.url(forResource: file.rawValue, withExtension: "json", subdirectory: "Contracts") else {
            throw ContractError.missingFile(file.fileName)
        }
        return try Data(contentsOf: url)
    }

    /// 读取并解析契约 JSON 为字典（顶层必须是 JSON 对象）。
    public static func load(_ file: ContractFile, bundle: Bundle? = nil) throws -> [String: Any] {
        let data = try loadData(file, bundle: bundle)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dict = object as? [String: Any] else {
            throw ContractError.invalidJSON(file.fileName)
        }
        return dict
    }

    /// `base.guide` 契约全文（M1 的 base.guide 工具直接返回此文本）。
    public static func guideContractText(bundle: Bundle? = nil) throws -> String {
        let data = try loadData(.sdk, bundle: bundle)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ContractError.invalidJSON(ContractFile.sdk.fileName)
        }
        return text
    }
}
