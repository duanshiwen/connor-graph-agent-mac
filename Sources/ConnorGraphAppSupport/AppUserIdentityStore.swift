import Foundation
import Combine
import ImageIO
import UniformTypeIdentifiers

public struct ConnorRemoteUserIdentity: Codable, Sendable, Equatable, Identifiable {
    public var id: UInt
    public var username: String
    public var nickname: String?
    public var email: String
    public var avatarURL: String?
    public var role: String
    public var createdAt: Date
    public var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, username, nickname, email, role, createdAt, updatedAt
        case avatarURL = "avatarUrl"
    }

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

public enum ConnorAccountSyncStatus: Sendable, Equatable {
    case disabled
    case waitingForLogin
    case offline
    case connecting
    case syncing
    case upToDate(Date)
    case failed(String)
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
private struct AvatarUploadResponse: Decodable { var objectName: String }
private struct SyncHeartbeatRequest: Encodable { var deviceId: String; var platform: String; var name: String; var appVersion: String }
private struct L1LeaseRequest: Encodable { var deviceId: String }

public struct ConnorSyncDevice: Codable, Sendable, Equatable {
    public var deviceId: String
    public var platform: String
    public var name: String
    public var appVersion: String
    public var lastSeenAt: Date
}

public struct ConnorSyncChange: Codable, Sendable, Equatable {
    public var cursor: Int64?
    public var mutationId: String?
    public var collection: String
    public var recordId: String
    public var baseVersion: Int64?
    public var payload: ConnorJSONValue
    public var deleted: Bool
    public var version: Int64?
    public var sourceDeviceId: String?
    public var changedAt: Date?

    enum CodingKeys: String, CodingKey {
        case cursor, mutationId, collection, recordId, baseVersion, payload, deleted, version, sourceDeviceId, changedAt
    }

    public init(mutationId: String = UUID().uuidString, collection: String, recordId: String, baseVersion: Int64 = 0, payload: ConnorJSONValue = .object([:]), deleted: Bool = false) throws {
        guard Self.isSyncable(collection: collection) else { throw ConnorSyncError.excludedCollection(collection) }
        self.cursor = nil; self.mutationId = mutationId; self.collection = collection; self.recordId = recordId
        self.baseVersion = baseVersion; self.payload = payload; self.deleted = deleted
        self.version = nil; self.sourceDeviceId = nil; self.changedAt = nil
    }

    public static func isSyncable(collection: String) -> Bool {
        let excluded: Set<String> = ["mail", "mail_accounts", "mail_messages", "calendar", "calendar_events", "rss", "rss_feeds", "rss_items", "scheduled_tasks", "event_driven_tasks"]
        return collection.range(of: "^[a-z][a-z0-9_]{0,63}$", options: .regularExpression) != nil && !excluded.contains(collection)
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        cursor = try values.decodeIfPresent(Int64.self, forKey: .cursor)
        mutationId = try values.decodeIfPresent(String.self, forKey: .mutationId)
        collection = try values.decode(String.self, forKey: .collection)
        recordId = try values.decode(String.self, forKey: .recordId)
        baseVersion = try values.decodeIfPresent(Int64.self, forKey: .baseVersion)
        payload = try values.decodeIfPresent(ConnorJSONValue.self, forKey: .payload) ?? .object([:])
        deleted = try values.decodeIfPresent(Bool.self, forKey: .deleted) ?? false
        version = try values.decodeIfPresent(Int64.self, forKey: .version)
        sourceDeviceId = try values.decodeIfPresent(String.self, forKey: .sourceDeviceId)
        changedAt = try values.decodeIfPresent(Date.self, forKey: .changedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(cursor, forKey: .cursor); try values.encodeIfPresent(mutationId, forKey: .mutationId)
        try values.encode(collection, forKey: .collection); try values.encode(recordId, forKey: .recordId)
        try values.encodeIfPresent(baseVersion, forKey: .baseVersion); try values.encode(payload, forKey: .payload)
        try values.encode(deleted, forKey: .deleted); try values.encodeIfPresent(version, forKey: .version)
        try values.encodeIfPresent(sourceDeviceId, forKey: .sourceDeviceId); try values.encodeIfPresent(changedAt, forKey: .changedAt)
    }
}

public enum ConnorJSONValue: Codable, Sendable, Equatable {
    case object([String: ConnorJSONValue])
    case array([ConnorJSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([ConnorJSONValue].self) { self = .array(value) }
        else if let value = try? container.decode([String: ConnorJSONValue].self) { self = .object(value) }
        else { throw ConnorBackendAPIError.invalidResponse }
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

public enum ConnorSyncError: Error, LocalizedError, Equatable {
    case excludedCollection(String)
    public var errorDescription: String? {
        switch self { case let .excludedCollection(collection): "集合 \(collection) 不允许跨设备同步。" }
    }
}

public struct ConnorSyncPullPage: Codable, Sendable, Equatable { public var changes: [ConnorSyncChange]; public var nextCursor: Int64; public var hasMore: Bool }
public struct ConnorL1Lease: Codable, Sendable, Equatable { public var granted: Bool; public var token: String?; public var expiresAt: Date?; public var reason: String? }
private struct SyncPushRequest: Encodable { var deviceId: String; var changes: [ConnorSyncChange] }
private struct SyncPushResponse: Decodable, Sendable { var results: [SyncPushResult] }
public struct SyncPushResult: Decodable, Sendable, Equatable { public var mutationId: String; public var applied: Bool; public var cursor: Int64? }

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

    public func uploadAvatar(token: String, fileURL: URL) async throws {
        let normalized = try Self.normalizedAvatarUpload(fileURL: fileURL)
        let data = normalized.data
        guard !data.isEmpty, data.count <= 5 * 1024 * 1024 else {
            throw ConnorBackendAPIError.server(status: 400, message: "头像图片不能超过 5 MB。")
        }
        let boundary = "ConnorAvatar-\(UUID().uuidString)"
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"avatar\"; filename=\"\(normalized.filename)\"\r\n".utf8))
        body.append(Data("Content-Type: \(normalized.mimeType)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        let _: AvatarUploadResponse = try await request(
            "users/auth/avatar",
            method: "POST",
            token: token,
            bodyData: body,
            contentType: "multipart/form-data; boundary=\(boundary)"
        )
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

    public func syncHeartbeat(token: String, deviceID: String, name: String, appVersion: String) async throws -> ConnorSyncDevice {
        try await request("sync/devices/heartbeat", method: "POST", token: token, body: SyncHeartbeatRequest(deviceId: deviceID, platform: "macos", name: name, appVersion: appVersion))
    }

    public func pushSyncChanges(token: String, deviceID: String, changes: [ConnorSyncChange]) async throws -> [SyncPushResult] {
        let response: SyncPushResponse = try await request("sync/push", method: "POST", token: token, body: SyncPushRequest(deviceId: deviceID, changes: changes))
        return response.results
    }

    public func pullSyncChanges(token: String, cursor: Int64, limit: Int = 200) async throws -> ConnorSyncPullPage {
        try await request("sync/pull?cursor=\(cursor)&limit=\(limit)", token: token)
    }

    public func acquireL1Lease(token: String, deviceID: String) async throws -> ConnorL1Lease {
        try await request("sync/l1-lease/acquire", method: "POST", token: token, body: L1LeaseRequest(deviceId: deviceID))
    }

    private struct EmptyResponse: Decodable {}

    private func request<T: Decodable>(_ path: String, method: String = "GET", token: String? = nil) async throws -> T {
        try await request(path, method: method, token: token, bodyData: nil)
    }

    private func request<T: Decodable, Body: Encodable>(_ path: String, method: String, token: String? = nil, body: Body) async throws -> T {
        try await request(path, method: method, token: token, bodyData: try encoder.encode(body))
    }

    private func request<T: Decodable>(
        _ path: String,
        method: String,
        token: String?,
        bodyData: Data?,
        contentType: String = "application/json"
    ) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL.appendingPathComponent("api/v1/")) else {
            throw ConnorBackendAPIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = bodyData
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
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

    /// Normalizes the selected image before upload so the backend always stores a
    /// decodable avatar: PNG/GIF/WebP pass through, everything else (including HEIC
    /// from the macOS Photos picker) is re-encoded as JPEG.
    private static func normalizedAvatarUpload(fileURL: URL) throws -> (data: Data, mimeType: String, filename: String) {
        let `extension` = fileURL.pathExtension.lowercased()
        switch `extension` {
        case "png", "gif", "webp":
            return (try Data(contentsOf: fileURL, options: .mappedIfSafe), "image/\(`extension`)", "avatar.\(`extension`)")
        default:
            guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
                throw ConnorBackendAPIError.server(status: 400, message: "无法读取所选图片")
            }
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
                throw ConnorBackendAPIError.server(status: 400, message: "无法转换所选图片")
            }
            CGImageDestinationAddImageFromSource(destination, source, 0, nil)
            guard CGImageDestinationFinalize(destination) else {
                throw ConnorBackendAPIError.server(status: 400, message: "无法转换所选图片")
            }
            return (output as Data, "image/jpeg", "avatar.jpg")
        }
    }
}

public struct AppConnorAccountCredentialStore: Sendable {
    private static let service = "ConnorGraphAgent.RemoteIdentity"
    private static let tokenPairAccount = "token-pair"
    private static let legacyAccessTokenAccount = "access-token"
    private static let syncKeyPrefix = "account-sync-key."
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

    public func saveSyncKey(_ key: Data, userID: String) throws {
        guard key.count == 32 else { throw AccountSyncCryptoError.invalidKey }
        try store.saveSecret(key.base64EncodedString(), service: Self.service, account: Self.syncKeyPrefix + userID)
    }

    public func syncKey(userID: String) throws -> Data? {
        guard let encoded = try store.readSecret(service: Self.service, account: Self.syncKeyPrefix + userID) else { return nil }
        guard let key = Data(base64Encoded: encoded), key.count == 32 else { throw AccountSyncCryptoError.invalidKey }
        return key
    }

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

    public func uploadAvatar(fileURL: URL) async throws -> ConnorRemoteUserIdentity {
        try await authenticated {
            try await api.uploadAvatar(token: $0, fileURL: fileURL)
            return try await api.currentUser(token: $0)
        }
    }

    public func ownedKnowledgeBases() async throws -> ConnorPage<ConnorKnowledgeBaseSummary> {
        try await authenticated { try await api.ownedKnowledgeBases(token: $0) }
    }

    public func subscriptions() async throws -> ConnorPage<ConnorKnowledgeBaseSubscription> {
        try await authenticated { try await api.subscriptions(token: $0) }
    }

    public func syncHeartbeat(deviceID: String, name: String, appVersion: String) async throws -> ConnorSyncDevice {
        try await authenticated { try await api.syncHeartbeat(token: $0, deviceID: deviceID, name: name, appVersion: appVersion) }
    }

    public func pushSyncChanges(deviceID: String, changes: [ConnorSyncChange]) async throws -> [SyncPushResult] {
        try await authenticated { try await api.pushSyncChanges(token: $0, deviceID: deviceID, changes: changes) }
    }

    public func pullSyncChanges(cursor: Int64, limit: Int = 200) async throws -> ConnorSyncPullPage {
        try await authenticated { try await api.pullSyncChanges(token: $0, cursor: cursor, limit: limit) }
    }

    public func acquireL1Lease(deviceID: String) async throws -> ConnorL1Lease {
        try await authenticated { try await api.acquireL1Lease(token: $0, deviceID: deviceID) }
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

/// Routing decision for a `/ws/device` frame. Sync frames wake the device-sync
/// pass; control frames are consumed; everything else — including typeless bare
/// ack payloads from `chat_send`/`group_send` — is an IM frame.
public enum ConnorDeviceSocketFrameRoute: Equatable, Sendable {
    case syncWake
    case control
    case im(type: String?)

    public static func classify(type: String?) -> ConnorDeviceSocketFrameRoute {
        switch type {
        case "connected", "sync_changed", "sync_peer_online": return .syncWake
        case "heartbeat_ack": return .control
        default: return .im(type: type)
        }
    }
}

private actor ConnorAccountSyncEventSocket {
    private struct EventEnvelope: Decodable { var type: String? }

    private let baseURL: URL
    private var webSocket: URLSessionWebSocketTask?

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    /// Writes an IM up-frame; returns false when the socket is not ready.
    func send(_ text: String) async -> Bool {
        guard let webSocket else { return false }
        do {
            try await webSocket.send(.string(text))
            return true
        } catch {
            return false
        }
    }

    func listen(
        accessToken: String,
        deviceID: String,
        onWake: @escaping @Sendable () async -> Void,
        onConnected: (@Sendable () async -> Void)? = nil,
        onImFrame: (@Sendable (_ type: String?, _ rawText: String) async -> Void)? = nil
    ) async throws {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        components?.path = "/ws/device"
        components?.queryItems = [URLQueryItem(name: "device_id", value: deviceID)]
        guard let url = components?.url else { throw ConnorBackendAPIError.invalidResponse }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let socket = URLSession.shared.webSocketTask(with: request)
        webSocket = socket
        socket.resume()

        let heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                try await self?.sendHeartbeat()
            }
        }
        defer {
            heartbeatTask.cancel()
            socket.cancel(with: .goingAway, reason: nil)
            if webSocket === socket { webSocket = nil }
        }

        while !Task.isCancelled {
            let message = try await socket.receive()
            let text: String
            switch message {
            case .data(let value): text = String(decoding: value, as: UTF8.self)
            case .string(let value): text = value
            @unknown default: continue
            }
            let type = (try? JSONDecoder().decode(EventEnvelope.self, from: Data(text.utf8)))?.type
            switch ConnorDeviceSocketFrameRoute.classify(type: type) {
            case .syncWake:
                if type == "connected" { await onConnected?() }
                await onWake()
            case .control:
                continue
            case .im(let frameType):
                await onImFrame?(frameType, text)
            }
        }
    }

    func stop() {
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
    }

    private func sendHeartbeat() async throws {
        try await webSocket?.send(.string("{\"type\":\"heartbeat\"}"))
    }
}

@MainActor
public final class AppUserIdentityStore: ObservableObject {
    @Published public private(set) var authenticationState: ConnorAuthenticationState = .signedOut
    @Published public private(set) var avatarRevision: UInt = 0
    @Published public private(set) var ownedKnowledgeBases: [ConnorKnowledgeBaseSummary] = []
    @Published public private(set) var subscribedKnowledgeBases: [ConnorKnowledgeBaseSubscription] = []
    @Published public private(set) var isLoadingLibraries = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var isDeviceSyncEnabled: Bool
    @Published public private(set) var deviceSyncStatus: ConnorAccountSyncStatus
    /// Live `/ws/device` connectivity for the IM feature (drives the reconnect banner).
    @Published public private(set) var isImSocketConnected = false

    private let api: ConnorBackendAPIClient
    private let baseURL: URL
    private let credentials: AppConnorAccountCredentialStore
    private let authenticatedSession: ConnorBackendAuthenticatedSession
    private let networkIsAvailable: @MainActor () -> Bool
    private let serverIsReachable: @MainActor () -> Bool
    private let syncDefaults: UserDefaults
    private var syncAvailabilityCancellable: AnyCancellable?
    private var l1CoordinationTask: Task<Void, Never>?
    private var syncSocketTask: Task<Void, Never>?
    private var syncPassTask: Task<Void, Never>?
    private var localChangeDebounceTask: Task<Void, Never>?
    private var localChangeObserver: NSObjectProtocol?
    private var syncEventSocket: ConnorAccountSyncEventSocket?
    private var syncPassRequested = false
    private let deviceID: String
    public var onDeviceSyncPass: (@MainActor () async throws -> Void)?
    /// IM frames from `/ws/device` (chat_* / group_* / friend_* and bare typeless acks).
    public var onImFrame: (@Sendable (_ type: String?, _ rawText: String) async -> Void)?
    /// Socket connectivity transitions; each reconnect should trigger an IM refreshAll.
    public var onImSocketStateChange: (@Sendable (_ connected: Bool) async -> Void)?

    public init(
        baseURL: URL = URL(string: ProcessInfo.processInfo.environment["CONNOR_BACKEND_BASE_URL"] ?? "http://localhost:8080")!,
        credentials: AppConnorAccountCredentialStore = .init(),
        transport: any ConnorBackendHTTPTransport = URLSession.shared,
        networkIsAvailable: @escaping @MainActor () -> Bool = { true },
        serverIsReachable: @escaping @MainActor () -> Bool = { true },
        syncAvailability: AnyPublisher<Bool, Never>? = nil,
        syncDefaults: UserDefaults = .standard
    ) {
        let api = ConnorBackendAPIClient(baseURL: baseURL, transport: transport)
        self.api = api
        self.baseURL = baseURL
        self.credentials = credentials
        self.authenticatedSession = ConnorBackendAuthenticatedSession(api: api, credentials: credentials)
        self.networkIsAvailable = networkIsAvailable
        self.serverIsReachable = serverIsReachable
        self.syncDefaults = syncDefaults
        self.isDeviceSyncEnabled = syncDefaults.bool(forKey: "ConnorDeviceSyncEnabled")
        self.deviceSyncStatus = syncDefaults.bool(forKey: "ConnorDeviceSyncEnabled") ? .waitingForLogin : .disabled
        let storedDeviceID = syncDefaults.string(forKey: "ConnorSyncDeviceID")
        self.deviceID = storedDeviceID ?? UUID().uuidString
        if storedDeviceID == nil { syncDefaults.set(self.deviceID, forKey: "ConnorSyncDeviceID") }
        localChangeObserver = NotificationCenter.default.addObserver(
            forName: AppAccountSyncSignal.localDataDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.scheduleLocalChangeSync() }
        }
        syncAvailabilityCancellable = syncAvailability?
            .removeDuplicates()
            .sink { [weak self] available in
                Task { @MainActor [weak self] in self?.syncAvailabilityDidChange(available) }
            }
    }

    public var currentUser: ConnorRemoteUserIdentity? {
        if case let .signedIn(user) = authenticationState { return user }
        return nil
    }

    public var hasStoredSession: Bool {
        (try? credentials.tokens()) != nil
    }

    public var syncDeviceID: String { deviceID }

    public func setDeviceSyncEnabled(_ enabled: Bool) {
        guard enabled != isDeviceSyncEnabled else { return }
        isDeviceSyncEnabled = enabled
        syncDefaults.set(enabled, forKey: "ConnorDeviceSyncEnabled")
        if enabled {
            guard currentUser != nil else {
                deviceSyncStatus = .waitingForLogin
                return
            }
            startDeviceSync()
        } else {
            stopDeviceSync()
            deviceSyncStatus = .disabled
        }
    }

    public func syncNow() {
        guard isDeviceSyncEnabled else {
            deviceSyncStatus = .disabled
            return
        }
        guard currentUser != nil else {
            deviceSyncStatus = .waitingForLogin
            return
        }
        guard networkIsAvailable(), serverIsReachable() else {
            deviceSyncStatus = .offline
            return
        }
        requestDeviceSyncPass()
    }

    public func accountSyncKey(userID: String) throws -> Data {
        guard let key = try credentials.syncKey(userID: userID) else { throw AccountSyncCryptoError.invalidKey }
        return key
    }

    public func pullSyncChanges(cursor: Int64, limit: Int = 200) async throws -> ConnorSyncPullPage {
        try await authenticatedSession.pullSyncChanges(cursor: cursor, limit: limit)
    }

    public func pushSyncChanges(_ changes: [ConnorSyncChange]) async throws -> [SyncPushResult] {
        try await authenticatedSession.pushSyncChanges(deviceID: deviceID, changes: changes)
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
            startEventSocketIfNeeded()
            startL1Coordination()
            if isDeviceSyncEnabled { startDeviceSync() }
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
        await authenticate(password: password) { try await self.api.login(username: username, password: password) }
    }

    public func register(username: String, email: String, password: String) async {
        guard requireNetwork() else { return }
        await authenticate(password: password) { try await self.api.register(username: username, email: email, password: password) }
    }

    public func uploadAvatar(fileURL: URL) async {
        guard requireNetwork() else { return }
        errorMessage = nil
        do {
            let user = try await authenticatedSession.uploadAvatar(fileURL: fileURL)
            authenticationState = .signedIn(user)
            avatarRevision &+= 1
        } catch ConnorBackendAPIError.unauthorized, ConnorBackendAPIError.missingRefreshToken {
            clearLocalSession(state: .expired)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func authenticate(password: String, _ action: () async throws -> ConnorAuthenticatedIdentity) async {
        errorMessage = nil
        do {
            let identity = try await action()
            guard !identity.tokens.refreshToken.isEmpty else { throw ConnorBackendAPIError.invalidResponse }
            let userID = String(identity.user.id)
            let syncKey = await Task.detached(priority: .userInitiated) {
                AccountSyncPayloadCipher.deriveKey(password: password, userID: userID)
            }.value
            try credentials.saveTokens(identity.tokens)
            try credentials.saveSyncKey(syncKey, userID: userID)
            authenticationState = .signedIn(identity.user)
            startEventSocketIfNeeded()
            startL1Coordination()
            if isDeviceSyncEnabled { startDeviceSync() }
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
        stopDeviceSync()
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
        stopDeviceSync()
        stopL1Coordination()
        stopEventSocket()
        try? credentials.clearTokens()
        authenticationState = state
        ownedKnowledgeBases = []
        subscribedKnowledgeBases = []
        isLoadingLibraries = false
        deviceSyncStatus = isDeviceSyncEnabled ? .waitingForLogin : .disabled
    }

    private func syncAvailabilityDidChange(_ available: Bool) {
        guard currentUser != nil else { return }
        if available {
            startL1Coordination()
            if isDeviceSyncEnabled { startDeviceSync() }
        } else {
            stopDeviceSync()
            stopL1Coordination()
            deviceSyncStatus = .offline
        }
    }

    private func startDeviceSync() {
        stopDeviceSync()
        guard isDeviceSyncEnabled, currentUser != nil else {
            deviceSyncStatus = isDeviceSyncEnabled ? .waitingForLogin : .disabled
            return
        }
        guard networkIsAvailable(), serverIsReachable() else {
            deviceSyncStatus = .offline
            return
        }
        deviceSyncStatus = .connecting
        startEventSocketIfNeeded()
        startL1Coordination()
        requestDeviceSyncPass()
    }

    private func startL1Coordination() {
        guard l1CoordinationTask == nil, currentUser != nil,
              networkIsAvailable(), serverIsReachable() else { return }
        let session = authenticatedSession
        let deviceID = deviceID
        l1CoordinationTask = Task {
            while !Task.isCancelled {
                do {
                    _ = try await session.syncHeartbeat(deviceID: deviceID, name: Host.current().localizedName ?? "Mac", appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                    let lease = try await session.acquireL1Lease(deviceID: deviceID)
                    L1ExtractionEligibility.shared.update(granted: lease.granted, expiresAt: lease.expiresAt)
                } catch {
                    L1ExtractionEligibility.shared.update(granted: false, expiresAt: nil)
                    if isDeviceSyncEnabled && (!networkIsAvailable() || !serverIsReachable()) {
                        deviceSyncStatus = .offline
                    }
                }
                try? await Task.sleep(for: .seconds(45))
            }
        }
    }

    /// Stops sync passes only; the event socket stays up because IM depends on it
    /// for as long as the user remains signed in.
    private func stopDeviceSync() {
        syncPassTask?.cancel(); syncPassTask = nil
        localChangeDebounceTask?.cancel(); localChangeDebounceTask = nil
        syncPassRequested = false
    }

    private func stopL1Coordination() {
        l1CoordinationTask?.cancel(); l1CoordinationTask = nil
        L1ExtractionEligibility.shared.update(granted: false, expiresAt: nil)
    }

    private func stopEventSocket() {
        syncSocketTask?.cancel(); syncSocketTask = nil
        if let syncEventSocket { Task { await syncEventSocket.stop() } }
        syncEventSocket = nil
        isImSocketConnected = false
    }

    /// Runs the `/ws/device` socket for the lifetime of the signed-in session:
    /// sync frames wake sync passes (when enabled), IM frames flow to `onImFrame`,
    /// and connectivity transitions feed the IM reconnect logic.
    private func startEventSocketIfNeeded() {
        guard syncSocketTask == nil, currentUser != nil else { return }
        let session = authenticatedSession
        let deviceID = deviceID
        let socket = ConnorAccountSyncEventSocket(baseURL: baseURL)
        syncEventSocket = socket
        syncSocketTask = Task { [weak self] in
            guard let self else { return }
            var retryDelay = 1
            while !Task.isCancelled {
                do {
                    let token = try await session.accessToken()
                    try await socket.listen(
                        accessToken: token,
                        deviceID: deviceID,
                        onWake: { [weak self] in
                            await MainActor.run { self?.requestDeviceSyncPass() }
                        },
                        onConnected: { [weak self] in
                            await self?.setImSocketConnected(true)
                        },
                        onImFrame: { [weak self] type, rawText in
                            guard let handler = await self?.onImFrame else { return }
                            await handler(type, rawText)
                        }
                    )
                    await setImSocketConnected(false)
                    retryDelay = 1
                } catch {
                    guard !Task.isCancelled else { return }
                    await setImSocketConnected(false)
                    if isDeviceSyncEnabled {
                        deviceSyncStatus = networkIsAvailable() && serverIsReachable()
                            ? .failed(error.localizedDescription)
                            : .offline
                    }
                    try? await Task.sleep(for: .seconds(retryDelay))
                    retryDelay = min(retryDelay * 2, 30)
                }
            }
        }
    }

    /// IM REST endpoints bound to this store's token-refresh session
    /// (`authenticatedSession` is private, hence this factory).
    public func makeImBackendService() -> ImBackendService {
        ImBackendService(api: ImAPIClient(baseURL: baseURL), session: authenticatedSession)
    }

    /// Writes an IM up-frame to the device socket; returns false when not connected.
    public func sendImFrame(_ text: String) async -> Bool {
        guard let syncEventSocket else { return false }
        return await syncEventSocket.send(text)
    }

    private func setImSocketConnected(_ connected: Bool) async {
        let changed = isImSocketConnected != connected
        isImSocketConnected = connected
        guard changed else { return }
        await onImSocketStateChange?(connected)
    }

    private func scheduleLocalChangeSync() {
        guard isDeviceSyncEnabled, currentUser != nil else { return }
        localChangeDebounceTask?.cancel()
        localChangeDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(750))
            guard !Task.isCancelled else { return }
            self?.requestDeviceSyncPass()
        }
    }

    private func requestDeviceSyncPass() {
        guard isDeviceSyncEnabled else { return }
        guard currentUser != nil else {
            deviceSyncStatus = .waitingForLogin
            return
        }
        guard networkIsAvailable(), serverIsReachable() else {
            deviceSyncStatus = .offline
            return
        }
        syncPassRequested = true
        guard syncPassTask == nil else { return }
        syncPassTask = Task { [weak self] in
            guard let self else { return }
            var retryDelay = 1
            while syncPassRequested, !Task.isCancelled {
                syncPassRequested = false
                deviceSyncStatus = .syncing
                do {
                    try await onDeviceSyncPass?()
                    guard !Task.isCancelled else { return }
                    deviceSyncStatus = .upToDate(Date())
                    retryDelay = 1
                } catch ConnorBackendAPIError.unauthorized {
                    clearLocalSession(state: .expired)
                    return
                } catch ConnorBackendAPIError.missingRefreshToken {
                    clearLocalSession(state: .expired)
                    return
                } catch {
                    guard !Task.isCancelled else { return }
                    deviceSyncStatus = networkIsAvailable() && serverIsReachable()
                        ? .failed(error.localizedDescription)
                        : .offline
                    if networkIsAvailable(), serverIsReachable(), isDeviceSyncEnabled, currentUser != nil {
                        syncPassRequested = true
                        try? await Task.sleep(for: .seconds(retryDelay))
                        retryDelay = min(retryDelay * 2, 30)
                    }
                }
            }
            syncPassTask = nil
        }
    }
}
