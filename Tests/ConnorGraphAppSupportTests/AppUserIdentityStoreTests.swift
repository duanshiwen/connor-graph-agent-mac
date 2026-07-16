import Foundation
import Testing
import ConnorGraphAppSupport

@Suite("App User Identity Store Tests")
struct AppUserIdentityStoreTests {
    @Test func remoteIdentityUsesNicknameThenUsernameAsDisplayName() {
        let date = Date(timeIntervalSince1970: 0)
        let named = ConnorRemoteUserIdentity(id: 1, username: "shiwen", nickname: "诗闻", email: "s@example.com", avatarURL: nil, role: "user", createdAt: date, updatedAt: date)
        let unnamed = ConnorRemoteUserIdentity(id: 1, username: "shiwen", nickname: "  ", email: "s@example.com", avatarURL: nil, role: "user", createdAt: date, updatedAt: date)

        #expect(named.displayName == "诗闻")
        #expect(unnamed.displayName == "shiwen")
    }

    @Test func accountCredentialStoreEncryptsAndDeletesTokenPair() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ConnorIdentityCredentialTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AppConnorAccountCredentialStore(store: LocalEncryptedCredentialStore(rootDirectory: root))
        let tokens = ConnorAuthenticationTokens(accessToken: "private-access-token", refreshToken: "private-refresh-token")

        try store.saveTokens(tokens)
        #expect(try store.tokens() == tokens)

        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        let contents = try files.filter { $0.pathExtension == "json" }.map { try String(contentsOf: $0, encoding: .utf8) }.joined()
        #expect(!contents.contains("private-access-token"))
        #expect(!contents.contains("private-refresh-token"))

        try store.clearTokens()
        #expect(try store.tokens() == nil)
    }

    @Test @MainActor func restoreRefreshesLibrariesAndCoalescesConcurrentTokenRefresh() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ConnorIdentityRestoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let credentials = AppConnorAccountCredentialStore(store: LocalEncryptedCredentialStore(rootDirectory: root))
        try credentials.saveTokens(.init(accessToken: "expired-access", refreshToken: "valid-refresh"))
        let transport = IdentityTestTransport()
        let store = AppUserIdentityStore(baseURL: URL(string: "https://backend.example")!, credentials: credentials, transport: transport)

        await store.restoreSession()

        #expect(store.currentUser?.username == "shiwen")
        #expect(store.ownedKnowledgeBases.map(\.kbId) == ["owned-kb"])
        #expect(store.subscribedKnowledgeBases.map(\.knowledgeBase.kbId) == ["subscribed-kb"])
        #expect(try credentials.tokens() == .init(accessToken: "fresh-access", refreshToken: "fresh-refresh"))
        #expect(await transport.refreshRequestCount == 1)
        #expect(await transport.requestCount(pathSuffix: "/knowledge-bases") == 2)
        #expect(await transport.requestCount(pathSuffix: "/knowledge-bases/subscriptions") == 2)
    }

    @Test @MainActor func logoutClearsCredentialsAndLibraries() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ConnorIdentityLogoutTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let credentials = AppConnorAccountCredentialStore(store: LocalEncryptedCredentialStore(rootDirectory: root))
        try credentials.saveTokens(.init(accessToken: "expired-access", refreshToken: "valid-refresh"))
        let transport = IdentityTestTransport()
        let store = AppUserIdentityStore(baseURL: URL(string: "https://backend.example")!, credentials: credentials, transport: transport)
        await store.restoreSession()

        await store.logout()

        #expect(store.authenticationState == .signedOut)
        #expect(store.ownedKnowledgeBases.isEmpty)
        #expect(store.subscribedKnowledgeBases.isEmpty)
        #expect(try credentials.tokens() == nil)
        #expect(await transport.logoutRequestCount == 1)
    }

    @Test @MainActor func failedRestoreKeepsCredentialsAvailableForRetry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ConnorIdentityRetryTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let credentials = AppConnorAccountCredentialStore(store: LocalEncryptedCredentialStore(rootDirectory: root))
        try credentials.saveTokens(.init(accessToken: "valid-access", refreshToken: "valid-refresh"))
        let transport = IdentityTestTransport(currentUserFailureCount: 1)
        let store = AppUserIdentityStore(baseURL: URL(string: "https://backend.example")!, credentials: credentials, transport: transport)

        await store.restoreSession()
        #expect(store.authenticationState == .signedOut)
        #expect(store.hasStoredSession)
        #expect(store.errorMessage != nil)

        await store.restoreSession()
        #expect(store.currentUser?.username == "shiwen")
        #expect(store.errorMessage == nil)
    }
}

private actor IdentityTestTransport: ConnorBackendHTTPTransport {
    private var requests: [URLRequest] = []
    private var currentUserFailureCount: Int

    init(currentUserFailureCount: Int = 0) {
        self.currentUserFailureCount = currentUserFailureCount
    }

    var refreshRequestCount: Int { requests.filter { $0.url?.path.hasSuffix("/users/public/refresh") == true }.count }
    var logoutRequestCount: Int { requests.filter { $0.url?.path.hasSuffix("/users/auth/logout") == true }.count }

    func requestCount(pathSuffix: String) -> Int {
        requests.filter { $0.url?.path.hasSuffix(pathSuffix) == true }.count
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let path = request.url?.path ?? ""
        let bearer = request.value(forHTTPHeaderField: "Authorization")
        switch path {
        case let value where value.hasSuffix("/users/auth/me"):
            if currentUserFailureCount > 0 {
                currentUserFailureCount -= 1
                throw URLError(.networkConnectionLost)
            }
            return response(request, status: 200, json: Self.userEnvelope)
        case let value where value.hasSuffix("/users/public/refresh"):
            return response(request, status: 200, json: Self.authEnvelope)
        case let value where value.hasSuffix("/knowledge-bases/subscriptions"):
            if bearer == "Bearer expired-access" { return response(request, status: 401, json: Self.errorEnvelope) }
            return response(request, status: 200, json: Self.subscriptionsEnvelope)
        case let value where value.hasSuffix("/knowledge-bases"):
            if bearer == "Bearer expired-access" { return response(request, status: 401, json: Self.errorEnvelope) }
            return response(request, status: 200, json: Self.ownedEnvelope)
        case let value where value.hasSuffix("/users/auth/logout"):
            return response(request, status: 200, json: #"{"code":0,"msg":"ok"}"#)
        default:
            return response(request, status: 404, json: Self.errorEnvelope)
        }
    }

    private func response(_ request: URLRequest, status: Int, json: String) -> (Data, URLResponse) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        return (Data(json.utf8), response)
    }

    private static let userJSON = #"{"id":1,"username":"shiwen","nickname":"诗闻","email":"s@example.com","role":"user","createdAt":"2026-07-13T04:00:00Z","updatedAt":"2026-07-13T04:00:00Z"}"#
    private static let userEnvelope = #"{"code":0,"data":\#(userJSON)}"#
    private static let authEnvelope = #"{"code":0,"data":{"user":\#(userJSON),"token":"fresh-access","refreshToken":"fresh-refresh"}}"#
    private static let summaryOwned = #"{"kbId":"owned-kb","name":"Owned","visibility":"private","subscriptionMode":"free","l2NodeCount":0,"l2StatementCount":0,"l3BeliefCount":0,"l4EntityCount":0,"l4RelationCount":0,"subscriberCount":0,"createdAt":"2026-07-13T04:00:00Z","updatedAt":"2026-07-13T04:00:00Z"}"#
    private static let summarySubscribed = #"{"kbId":"subscribed-kb","name":"Subscribed","visibility":"public","subscriptionMode":"free","l2NodeCount":0,"l2StatementCount":0,"l3BeliefCount":0,"l4EntityCount":0,"l4RelationCount":0,"subscriberCount":1,"createdAt":"2026-07-13T04:00:00Z","updatedAt":"2026-07-13T04:00:00Z"}"#
    private static let ownedEnvelope = #"{"code":0,"data":{"items":[\#(summaryOwned)],"total":1,"page":1,"pageSize":100}}"#
    private static let subscriptionsEnvelope = #"{"code":0,"data":{"items":[{"knowledgeBase":\#(summarySubscribed),"status":"active","subscribedAt":"2026-07-13T04:00:00Z"}],"total":1,"page":1,"pageSize":100}}"#
    private static let errorEnvelope = #"{"code":401,"msg":"expired"}"#
}
