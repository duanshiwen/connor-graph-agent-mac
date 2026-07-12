import Foundation
import Combine

public struct ConnorRemoteUserIdentity: Codable, Sendable, Equatable, Identifiable {
    public var id: UInt
    public var username: String
    public var nickname: String?
    public var email: String
    public var avatarURL: String?
    public var role: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UInt, username: String, nickname: String?, email: String, avatarURL: String?, role: String, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.username = username
        self.nickname = nickname
        self.email = email
        self.avatarURL = avatarURL
        self.role = role
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var displayName: String {
        let nickname = nickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return nickname.isEmpty ? username : nickname
    }
}

public struct ConnorPublicUser: Codable, Sendable, Equatable, Identifiable {
    public var id: UInt
    public var username: String
    public var nickname: String?
    public var avatarURL: String?
    public var displayName: String { nickname?.isEmpty == false ? nickname! : username }
}

public struct ConnorKnowledgeBaseSummary: Codable, Sendable, Equatable, Identifiable {
    public var kbId: String
    public var name: String
    public var description: String?
    public var iconUrl: String?
    public var visibility: String
    public var subscriptionMode: String
    public var category: String?
    public var l2NodeCount: Int
    public var l2StatementCount: Int
    public var l3BeliefCount: Int
    public var l4EntityCount: Int
    public var l4RelationCount: Int
    public var subscriberCount: Int
    public var owner: ConnorPublicUser?
    public var createdAt: Date
    public var updatedAt: Date
    public var id: String { kbId }
}

public struct ConnorKnowledgeBaseSubscription: Codable, Sendable, Equatable, Identifiable {
    public var knowledgeBase: ConnorKnowledgeBaseSummary
    public var status: String
    public var subscribedAt: Date
    public var expiresAt: Date?
    public var id: String { knowledgeBase.kbId }
}

public struct ConnorPage<Item: Codable & Sendable & Equatable>: Codable, Sendable, Equatable {
    public var items: [Item]
    public var total: Int
    public var page: Int
    public var pageSize: Int
}

public enum ConnorAuthenticationState: Sendable, Equatable {
    case signedOut
    case restoring
    case signedIn(ConnorRemoteUserIdentity)
    case expired
}

public enum ConnorBackendAPIError: Error, Sendable, Equatable, LocalizedError {
    case invalidResponse
    case server(status: Int, message: String)
    case unauthorized

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: "服务器返回了无法识别的数据。"
        case let .server(_, message): message
        case .unauthorized: "登录已失效，请重新登录。"
        }
    }
}

private struct APIEnvelope<T: Decodable>: Decodable { var code: Int; var msg: String?; var data: T }
private struct AuthPayload: Decodable { var user: ConnorRemoteUserIdentity; var token: String }
private struct LoginRequest: Encodable { var username: String; var password: String }
private struct RegisterRequest: Encodable { var username: String; var email: String; var password: String }

public struct ConnorBackendAPIClient: Sendable {
    public var baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder = JSONEncoder()

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func login(username: String, password: String) async throws -> (ConnorRemoteUserIdentity, String) {
        let payload: AuthPayload = try await request("users/public/login", method: "POST", body: LoginRequest(username: username, password: password))
        return (payload.user, payload.token)
    }

    public func register(username: String, email: String, password: String) async throws -> (ConnorRemoteUserIdentity, String) {
        let payload: AuthPayload = try await request("users/public/register", method: "POST", body: RegisterRequest(username: username, email: email, password: password))
        return (payload.user, payload.token)
    }

    public func currentUser(token: String) async throws -> ConnorRemoteUserIdentity {
        try await request("users/auth/me", token: token)
    }

    public func ownedKnowledgeBases(token: String) async throws -> ConnorPage<ConnorKnowledgeBaseSummary> {
        try await request("knowledge-bases?page=1&page_size=100", token: token)
    }

    public func subscriptions(token: String) async throws -> ConnorPage<ConnorKnowledgeBaseSubscription> {
        try await request("knowledge-bases/subscriptions?page=1&page_size=100", token: token)
    }

    public func logout(token: String) async throws {
        let _: EmptyResponse = try await request("users/auth/logout", method: "POST", token: token)
    }

    private struct EmptyResponse: Decodable {}

    private func request<T: Decodable>(_ path: String, method: String = "GET", token: String? = nil) async throws -> T {
        try await request(path, method: method, token: token, bodyData: nil)
    }

    private func request<T: Decodable, Body: Encodable>(_ path: String, method: String, token: String? = nil, body: Body) async throws -> T {
        try await request(path, method: method, token: token, bodyData: try encoder.encode(body))
    }

    private func request<T: Decodable>(_ path: String, method: String, token: String?, bodyData: Data?) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL.appendingPathComponent("api/v1/")) else { throw ConnorBackendAPIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ConnorBackendAPIError.invalidResponse }
        if http.statusCode == 401 { throw ConnorBackendAPIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["msg"] as? String ?? "请求失败（\(http.statusCode)）"
            throw ConnorBackendAPIError.server(status: http.statusCode, message: message)
        }
        if T.self == EmptyResponse.self, data.isEmpty || (try? JSONSerialization.jsonObject(with: data)) != nil {
            return EmptyResponse() as! T
        }
        return try decoder.decode(APIEnvelope<T>.self, from: data).data
    }
}

public struct AppConnorAccountCredentialStore: Sendable {
    private static let service = "ConnorGraphAgent.RemoteIdentity"
    private static let account = "access-token"
    private let store: any CredentialStore
    public init(store: any CredentialStore = LocalEncryptedCredentialStore()) { self.store = store }
    public func saveToken(_ token: String) throws { try store.saveSecret(token, service: Self.service, account: Self.account) }
    public func token() throws -> String? { try store.readSecret(service: Self.service, account: Self.account) }
    public func clearToken() throws { try store.deleteSecret(service: Self.service, account: Self.account) }
}

@MainActor
public final class AppUserIdentityStore: ObservableObject {
    @Published public private(set) var authenticationState: ConnorAuthenticationState = .signedOut
    @Published public private(set) var ownedKnowledgeBases: [ConnorKnowledgeBaseSummary] = []
    @Published public private(set) var subscribedKnowledgeBases: [ConnorKnowledgeBaseSubscription] = []
    @Published public private(set) var isLoadingLibraries = false
    @Published public private(set) var errorMessage: String?

    private let api: ConnorBackendAPIClient
    private let credentials: AppConnorAccountCredentialStore

    public init(baseURL: URL = URL(string: ProcessInfo.processInfo.environment["CONNOR_BACKEND_BASE_URL"] ?? "http://127.0.0.1:8080")!, credentials: AppConnorAccountCredentialStore = .init()) {
        self.api = ConnorBackendAPIClient(baseURL: baseURL)
        self.credentials = credentials
    }

    public var currentUser: ConnorRemoteUserIdentity? {
        if case let .signedIn(user) = authenticationState { return user }
        return nil
    }

    public func restoreSession() async {
        authenticationState = .restoring
        do {
            guard let token = try credentials.token() else { authenticationState = .signedOut; return }
            authenticationState = .signedIn(try await api.currentUser(token: token))
        } catch ConnorBackendAPIError.unauthorized {
            try? credentials.clearToken(); authenticationState = .expired
        } catch {
            authenticationState = .signedOut; errorMessage = error.localizedDescription
        }
    }

    public func login(username: String, password: String) async {
        await authenticate { try await self.api.login(username: username, password: password) }
    }

    public func register(username: String, email: String, password: String) async {
        await authenticate { try await self.api.register(username: username, email: email, password: password) }
    }

    private func authenticate(_ action: () async throws -> (ConnorRemoteUserIdentity, String)) async {
        errorMessage = nil
        do {
            let (user, token) = try await action()
            try credentials.saveToken(token)
            authenticationState = .signedIn(user)
            await refreshLibraries()
        } catch { errorMessage = error.localizedDescription }
    }

    public func refreshLibraries() async {
        guard let token = try? credentials.token() else { return }
        isLoadingLibraries = true; errorMessage = nil
        defer { isLoadingLibraries = false }
        do {
            async let owned = api.ownedKnowledgeBases(token: token)
            async let subscriptions = api.subscriptions(token: token)
            ownedKnowledgeBases = try await owned.items
            subscribedKnowledgeBases = try await subscriptions.items
        } catch ConnorBackendAPIError.unauthorized {
            try? credentials.clearToken(); authenticationState = .expired
        } catch { errorMessage = error.localizedDescription }
    }

    public func logout() async {
        if let token = try? credentials.token() { try? await api.logout(token: token) }
        try? credentials.clearToken()
        authenticationState = .signedOut
        ownedKnowledgeBases = []; subscribedKnowledgeBases = []; errorMessage = nil
    }
}
