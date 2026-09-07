import Foundation

/// 云端小程序（Connor Base）RPC 客户端。
/// 走契约统一端点 POST /api/v1/base/rpc，envelope 语义与 base.sdk.v1 对齐：
/// `{ok, data, error:{code,message,hint,retryable}, traceId, site, sync}`。
/// 目前仅使用只读目录工具：base.app.list（分页列表）/ base.app.get（详情）。
public struct BaseCloudAPIClient: Sendable {
    public var baseURL: URL
    private let transport: any ConnorBackendHTTPTransport
    private let credentials: any CloudKnowledgeCredentialProvider
    private let decoder: JSONDecoder

    public init(
        baseURL: URL,
        transport: any ConnorBackendHTTPTransport = URLSession.shared,
        credentials: any CloudKnowledgeCredentialProvider = StoredCloudKnowledgeCredentialProvider()
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.credentials = credentials
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    /// 云端小程序目录：分页 + 关键词过滤。
    public func listApps(query: String = "", page: Int = 1, limit: Int = 20) async throws -> BaseAppListPage {
        let args: [String: Any] = [
            "query": query,
            "page": max(page, 1),
            "limit": min(max(limit, 1), 50)
        ]
        return try await rpc(tool: "base.app.list", args: args)
    }

    /// 云端小程序详情（功能说明 + 汇总提示）。
    public func appDetail(appID: String) async throws -> BaseCloudAppDetail {
        try await rpc(tool: "base.app.get", args: ["appID": appID])
    }

    // MARK: - 请求内核

    private func rpc<T: Decodable>(tool: String, args: [String: Any]) async throws -> T {
        let url = baseURL.appendingPathComponent("api/v1/base/rpc")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(try await credentials.accessToken())", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = ["tool": tool, "args": args]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw rpcFailure(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data)
        }
        let envelope: BaseRPCEnvelope<T>
        do {
            envelope = try decoder.decode(BaseRPCEnvelope<T>.self, from: data)
        } catch {
            throw BaseCloudAPIError.invalidResponse
        }
        guard envelope.ok, let value = envelope.data else {
            throw BaseCloudAPIError.rpc(
                code: envelope.error?.code ?? "UNKNOWN",
                message: envelope.error?.message ?? "云端返回错误",
                hint: envelope.error?.hint
            )
        }
        return value
    }

    private func rpcFailure(statusCode: Int, data: Data) -> BaseCloudAPIError {
        let envelope = try? decoder.decode(BackendErrorEnvelope.self, from: data)
        let message = envelope?.msg ?? envelope?.error ?? envelope?.code ?? ""
        return .server(statusCode: statusCode, message: message)
    }

    private struct BaseRPCEnvelope<T: Decodable>: Decodable {
        let ok: Bool
        let data: T?
        let error: BaseRPCErrorEnvelope?
    }

    private struct BaseRPCErrorEnvelope: Decodable {
        let code: String?
        let message: String?
        let hint: String?
        let retryable: Bool?
    }

    private struct BackendErrorEnvelope: Decodable {
        var code: String?
        var msg: String?
        var error: String?
    }
}

/// 云端小程序列表页。
public struct BaseAppListPage: Codable, Sendable, Equatable {
    public var items: [BaseCloudAppItem]
    public var page: Int
    public var limit: Int
    public var total: Int
    public var hasMore: Bool
}

/// 云端小程序列表项。
public struct BaseCloudAppItem: Codable, Sendable, Equatable {
    public var appId: String
    public var name: String
    public var domain: String
    public var purpose: String
    public var visibility: String
    public var ownerId: Int
    public var ownerName: String
    public var methodCount: Int
    public var tableCount: Int
    public var packageVersion: Int
    public var isOwner: Bool
    public var updatedAt: String
}

/// 云端小程序详情。
public struct BaseCloudAppDetail: Codable, Sendable, Equatable {
    public var appId: String
    public var name: String
    public var domain: String
    public var purpose: String
    public var visibility: String
    public var ownerId: Int
    public var ownerName: String
    public var methodCount: Int
    public var tableCount: Int
    public var packageVersion: Int
    public var isOwner: Bool
    public var riskLevel: String
    public var sdkVersion: Int
    public var capabilities: [String]
    public var methods: [String]
    public var guide: [String: ConnorJSONValue]?
    public var dataTableCount: Int
    public var updatedAt: String
}

public enum BaseCloudAPIError: Error, LocalizedError, CustomStringConvertible, Sendable {
    case server(statusCode: Int, message: String)
    case invalidResponse
    case rpc(code: String, message: String, hint: String?)

    public var description: String { message }
    public var errorDescription: String? { message }

    private var message: String {
        switch self {
        case .server(let statusCode, let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "云端服务错误（HTTP \(statusCode)）" : trimmed
        case .invalidResponse:
            return "云端小程序服务返回了无法解析的响应"
        case .rpc(let code, let message, let hint):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if let hint, !hint.isEmpty {
                return "\(trimmed.isEmpty ? "云端返回错误" : trimmed)（\(hint)）"
            }
            return trimmed.isEmpty ? "云端返回错误（\(code)）" : trimmed
        }
    }
}
