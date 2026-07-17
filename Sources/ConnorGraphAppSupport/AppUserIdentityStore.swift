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

public struct ConnorAuthenticationTokens: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String

    public init(accessToken: String, refreshToken: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }
}

public struct ConnorAuthenticatedIdentity: Sendable, Equatable {
    public var user: ConnorRemoteUserIdentity
    public var tokens: ConnorAuthenticationTokens

    public init(user: ConnorRemoteUserIdentity, tokens: ConnorAuthenticationTokens) {
        self.user = user
        self.tokens = tokens
    }
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
    case missingRefreshToken

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: "服务器返回了无法识别的数据。"
        case let .server(_, message): message
        case .unauthorized: "登录已失效，请重新登录。"
        case .missingRefreshToken: "当前登录凭据无法刷新，请重新登录。"
        }
    }
}

public protocol ConnorBackendHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: ConnorBackendHTTPTransport {}

private struct APIEnvelope<T: Decodable>: Decodable { var code: Int; var msg: String?; var data: T }
private struct AuthPayload: Decodable {
    var user: ConnorRemoteUserIdentity
    var token: String
    var refreshToken: String?

    var authenticatedIdentity: ConnorAuthenticatedIdentity {
        ConnorAuthenticatedIdentity(
            user: user,
            tokens: ConnorAuthenticationTokens(accessToken: token, refreshToken: refreshToken ?? "")
        )
    }
}
private struct LoginRequest: Encodable { var username: String; var password: String }
private struct RegisterRequest: Encodable { var username: String; var email: String; var password: String }
private struct RefreshRequest: Encodable { var refreshToken: String }
private struct LogoutRequest: Encodable { var refreshToken: String }

public struct ConnorBackendAPIClient: Sendable {
    public var baseURL: URL
    private let transport: any ConnorBackendHTTPTransport
    private let decoder: JSONDecoder
    private let encoder = JSONEncoder()

    public init(baseURL: URL, transport: any ConnorBackendHTTPTransport = URLSession.shared) {
        self.baseURL = baseURL
        self.transport = transport
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func login(username: String, password: String) async throws -> ConnorAuthenticatedIdentity {
        let payload: AuthPayload = try await request("users/public/login", method: "POST", body: LoginRequest(username: username, password: password))
        return payload.authenticatedIdentity
    }

    public func register(username: String, email: String, password: String) async throws -> ConnorAuthenticatedIdentity {
        let payload: AuthPayload = try await request("users/public/register", method: "POST", body: RegisterRequest(username: username, email: email, password: password))
        return payload.authenticatedIdentity
    }

    public func refresh(refreshToken: String) async throws -> ConnorAuthenticatedIdentity {
        let payload: AuthPayload = try await request("users/public/refresh", method: "POST", body: RefreshRequest(refreshToken: refreshToken))
        return payload.authenticatedIdentity
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

    public func logout(accessToken: String, refreshToken: String?) async throws {
        let _: EmptyResponse = try await request(
            "users/auth/logout",
            method: "POST",
            token: accessToken,
            body: LogoutRequest(refreshToken: refreshToken ?? "")
        )
    }

    private struct EmptyResponse: Decodable {}

    private func request<T: Decodable>(_ path: String, method: String = "GET", token: String? = nil) async throws -> T {
        try await request(path, method: method, token: token, bodyData: nil)
    }

    private func request<T: Decodable, Body: Encodable>(_ path: String, method: String, token: String? = nil, body: Body) async throws -> T {
        try await request(path, method: method, token: token, bodyData: try encoder.encode(body))
    }

    private func request<T: Decodable>(_ path: String, method: String, token: String?, bodyData: Data?) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL.appendingPathComponent("api/v1/")) else {
            throw ConnorBackendAPIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await transport.data(for: request)
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
    private static let tokenPairAccount = "token-pair"
    private static let legacyAccessTokenAccount = "access-token"
    private let store: any CredentialStore

    public init(store: any CredentialStore = LocalEncryptedCredentialStore()) { self.store = store }

    public func saveTokens(_ tokens: ConnorAuthenticationTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        guard let value = String(data: data, encoding: .utf8) else { throw ConnorBackendAPIError.invalidResponse }
        try store.saveSecret(value, service: Self.service, account: Self.tokenPairAccount)
        try? store.deleteSecret(service: Self.service, account: Self.legacyAccessTokenAccount)
    }

    public func tokens() throws -> ConnorAuthenticationTokens? {
        if let value = try store.readSecret(service: Self.service, account: Self.tokenPairAccount),
           let data = value.data(using: .utf8) {
            return try JSONDecoder().decode(ConnorAuthenticationTokens.self, from: data)
        }
        if let legacy = try store.readSecret(service: Self.service, account: Self.legacyAccessTokenAccount) {
            return ConnorAuthenticationTokens(accessToken: legacy, refreshToken: "")
        }
        return nil
    }

    // Compatibility helpers for callers and stored credentials created before token pairs.
    public func saveToken(_ token: String) throws {
        try store.saveSecret(token, service: Self.service, account: Self.legacyAccessTokenAccount)
        try? store.deleteSecret(service: Self.service, account: Self.tokenPairAccount)
    }
    public func token() throws -> String? { try tokens()?.accessToken }

    public func clearTokens() throws {
        try store.deleteSecret(service: Self.service, account: Self.tokenPairAccount)
        try store.deleteSecret(service: Self.service, account: Self.legacyAccessTokenAccount)
    }
    public func clearToken() throws { try clearTokens() }
}

public actor ConnorBackendAuthenticatedSession {
    private let api: ConnorBackendAPIClient
    private let credentials: AppConnorAccountCredentialStore
    private var refreshTask: Task<ConnorAuthenticationTokens, Error>?

    public init(api: ConnorBackendAPIClient, credentials: AppConnorAccountCredentialStore) {
        self.api = api
        self.credentials = credentials
    }

    public func accessToken() throws -> String {
        guard let token = try credentials.tokens()?.accessToken, !token.isEmpty else { throw ConnorBackendAPIError.unauthorized }
        return token
    }

    public func refreshAccessToken(afterRejectedToken rejectedToken: String) async throws -> String {
        guard let tokens = try credentials.tokens() else { throw ConnorBackendAPIError.unauthorized }
        if tokens.accessToken != rejectedToken { return tokens.accessToken }
        return try await refreshTokens(from: tokens).accessToken
    }

    public func currentUser() async throws -> ConnorRemoteUserIdentity {
        try await authenticated { try await api.currentUser(token: $0) }
    }

    public func ownedKnowledgeBases() async throws -> ConnorPage<ConnorKnowledgeBaseSummary> {
        try await authenticated { try await api.ownedKnowledgeBases(token: $0) }
    }

    public func subscriptions() async throws -> ConnorPage<ConnorKnowledgeBaseSubscription> {
        try await authenticated { try await api.subscriptions(token: $0) }
    }

    public func clearRefreshState() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func authenticated<Value: Sendable>(
        _ operation: @Sendable (String) async throws -> Value
    ) async throws -> Value {
        guard let initialTokens = try credentials.tokens() else { throw ConnorBackendAPIError.unauthorized }
        do {
            return try await operation(initialTokens.accessToken)
        } catch ConnorBackendAPIError.unauthorized {
            let refreshed = try await refreshTokens(from: initialTokens)
            // Retry exactly once. A second 401 is returned to the store as an expired session.
            return try await operation(refreshed.accessToken)
        }
    }

    private func refreshTokens(from staleTokens: ConnorAuthenticationTokens) async throws -> ConnorAuthenticationTokens {
        if let refreshTask { return try await refreshTask.value }
        // A faster concurrent request may have completed rotation before this request observed its 401.
        if let currentTokens = try credentials.tokens(), currentTokens != staleTokens {
            return currentTokens
        }
        guard !staleTokens.refreshToken.isEmpty else { throw ConnorBackendAPIError.missingRefreshToken }

        let api = self.api
        let credentials = self.credentials
        let task = Task<ConnorAuthenticationTokens, Error> {
            let identity = try await api.refresh(refreshToken: staleTokens.refreshToken)
            guard !identity.tokens.refreshToken.isEmpty else { throw ConnorBackendAPIError.invalidResponse }
            try credentials.saveTokens(identity.tokens)
            return identity.tokens
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }
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
    private let authenticatedSession: ConnorBackendAuthenticatedSession
    private let networkIsAvailable: @MainActor () -> Bool
    private let serverIsReachable: @MainActor () -> Bool

    public init(
        baseURL: URL = URL(string: ProcessInfo.processInfo.environment["CONNOR_BACKEND_BASE_URL"] ?? "http://localhost:8080")!,
        credentials: AppConnorAccountCredentialStore = .init(),
        transport: any ConnorBackendHTTPTransport = URLSession.shared,
        networkIsAvailable: @escaping @MainActor () -> Bool = { true },
        serverIsReachable: @escaping @MainActor () -> Bool = { true }
    ) {
        let api = ConnorBackendAPIClient(baseURL: baseURL, transport: transport)
        self.api = api
        self.credentials = credentials
        self.authenticatedSession = ConnorBackendAuthenticatedSession(api: api, credentials: credentials)
        self.networkIsAvailable = networkIsAvailable
        self.serverIsReachable = serverIsReachable
    }

    public var currentUser: ConnorRemoteUserIdentity? {
        if case let .signedIn(user) = authenticationState { return user }
        return nil
    }

    public var hasStoredSession: Bool {
        (try? credentials.tokens()) != nil
    }

    public func restoreSession() async {
        authenticationState = .restoring
        errorMessage = nil
        do {
            guard try credentials.tokens() != nil else {
                clearLocalSession(state: .signedOut)
                return
            }
            let user = try await authenticatedSession.currentUser()
            authenticationState = .signedIn(user)
            await refreshLibraries()
        } catch ConnorBackendAPIError.unauthorized, ConnorBackendAPIError.missingRefreshToken {
            clearLocalSession(state: .expired)
        } catch {
            authenticationState = .signedOut
            errorMessage = error.localizedDescription
        }
    }

    public func login(username: String, password: String) async {
        guard requireNetwork() else { return }
        await authenticate { try await self.api.login(username: username, password: password) }
    }

    public func register(username: String, email: String, password: String) async {
        guard requireNetwork() else { return }
        await authenticate { try await self.api.register(username: username, email: email, password: password) }
    }

    private func authenticate(_ action: () async throws -> ConnorAuthenticatedIdentity) async {
        errorMessage = nil
        do {
            let identity = try await action()
            guard !identity.tokens.refreshToken.isEmpty else { throw ConnorBackendAPIError.invalidResponse }
            try credentials.saveTokens(identity.tokens)
            authenticationState = .signedIn(identity.user)
            await refreshLibraries()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func refreshLibraries() async {
        guard (try? credentials.tokens()) != nil else { return }
        isLoadingLibraries = true
        errorMessage = nil
        defer { isLoadingLibraries = false }
        do {
            async let owned = authenticatedSession.ownedKnowledgeBases()
            async let subscriptions = authenticatedSession.subscriptions()
            ownedKnowledgeBases = try await owned.items
            subscribedKnowledgeBases = try await subscriptions.items
        } catch ConnorBackendAPIError.unauthorized, ConnorBackendAPIError.missingRefreshToken {
            clearLocalSession(state: .expired)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func logout() async {
        guard requireNetwork() else { return }
        let tokens = try? credentials.tokens()
        if let tokens {
            try? await api.logout(
                accessToken: tokens.accessToken,
                refreshToken: tokens.refreshToken.isEmpty ? nil : tokens.refreshToken
            )
        }
        await authenticatedSession.clearRefreshState()
        clearLocalSession(state: .signedOut)
        errorMessage = nil
    }

    @discardableResult
    private func requireNetwork() -> Bool {
        guard networkIsAvailable() else {
            errorMessage = "当前没有网络连接。"
            return false
        }
        guard serverIsReachable() else {
            errorMessage = "当前无法连接到康纳服务器。"
            return false
        }
        return true
    }

    private func clearLocalSession(state: ConnorAuthenticationState) {
        try? credentials.clearTokens()
        authenticationState = state
        ownedKnowledgeBases = []
        subscribedKnowledgeBases = []
        isLoadingLibraries = false
    }
}
