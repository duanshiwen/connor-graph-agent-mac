import Foundation
import CryptoKit
import Network

public struct MicrosoftMailOAuthCredentialPackage: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String?
    public var idToken: String?
    public var tokenType: String
    public var scope: String?
    public var expiresAt: Date?

    public init(accessToken: String, refreshToken: String? = nil, idToken: String? = nil, tokenType: String = "Bearer", scope: String? = nil, expiresAt: Date? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.idToken = idToken
        self.tokenType = tokenType
        self.scope = scope
        self.expiresAt = expiresAt
    }

    public var isAccessTokenUsable: Bool {
        guard !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard let expiresAt else { return true }
        return expiresAt > Date().addingTimeInterval(60)
    }

    public func encodedString() throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }

    public static func decode(from string: String) throws -> MicrosoftMailOAuthCredentialPackage {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MicrosoftMailOAuthCredentialPackage.self, from: Data(string.utf8))
    }
}

public struct MicrosoftMailOAuthConfiguration: Sendable, Equatable {
    public static let defaultCallbackPort: UInt16 = 1476
    public static let defaultCallbackPath = "/mail/microsoft/callback"

    public var clientID: String
    public var tenant: String
    public var redirectURI: String
    public var callbackPort: UInt16
    public var callbackPath: String

    public init(
        clientID: String,
        tenant: String = "common",
        redirectURI: String = "http://localhost:\(Self.defaultCallbackPort)\(Self.defaultCallbackPath)",
        callbackPort: UInt16 = Self.defaultCallbackPort,
        callbackPath: String = Self.defaultCallbackPath
    ) {
        self.clientID = clientID
        self.tenant = tenant
        self.redirectURI = redirectURI
        self.callbackPort = callbackPort
        self.callbackPath = callbackPath
    }

    public static func loadFromProcessAndDefaults() -> MicrosoftMailOAuthConfiguration? {
        let environment = ProcessInfo.processInfo.environment
        let defaults = UserDefaults.standard
        let clientID = environment["CONNOR_MICROSOFT_MAIL_CLIENT_ID"]
            ?? defaults.string(forKey: "ConnorMicrosoftMailOAuthClientID")
        guard let clientID = clientID?.trimmingCharacters(in: .whitespacesAndNewlines), !clientID.isEmpty else { return nil }
        let tenant = environment["CONNOR_MICROSOFT_MAIL_TENANT"]
            ?? defaults.string(forKey: "ConnorMicrosoftMailOAuthTenant")
            ?? "common"
        let redirectURI = environment["CONNOR_MICROSOFT_MAIL_REDIRECT_URI"]
            ?? defaults.string(forKey: "ConnorMicrosoftMailOAuthRedirectURI")
            ?? "http://localhost:\(defaultCallbackPort)\(defaultCallbackPath)"
        return MicrosoftMailOAuthConfiguration(
            clientID: clientID,
            tenant: tenant.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "common",
            redirectURI: redirectURI.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "http://localhost:\(defaultCallbackPort)\(defaultCallbackPath)",
            callbackPort: defaultCallbackPort,
            callbackPath: defaultCallbackPath
        )
    }

    public var authorizationScopes: String {
        [
            "openid",
            "offline_access",
            "email",
            "https://outlook.office.com/IMAP.AccessAsUser.All",
            "https://outlook.office.com/SMTP.Send"
        ].joined(separator: " ")
    }
}

public enum MicrosoftMailOAuthError: Error, Sendable, LocalizedError, Equatable {
    case missingClientID
    case invalidAuthorizationURL
    case callbackServerFailed(String)
    case missingAuthorizationCode
    case stateMismatch
    case tokenExchangeFailed(String)
    case missingAccessToken

    public var errorDescription: String? {
        switch self {
        case .missingClientID:
            "缺少 Microsoft 邮件 OAuth Client ID。请先注册 Microsoft Entra 应用，并配置环境变量 CONNOR_MICROSOFT_MAIL_CLIENT_ID，或 UserDefaults 键 ConnorMicrosoftMailOAuthClientID。"
        case .invalidAuthorizationURL:
            "无法创建 Microsoft OAuth 登录 URL。"
        case .callbackServerFailed(let message):
            "OAuth 回调服务失败：\(message)"
        case .missingAuthorizationCode:
            "Microsoft 登录没有返回 authorization code。"
        case .stateMismatch:
            "OAuth state 校验失败，请重新登录。"
        case .tokenExchangeFailed(let message):
            "Microsoft token 交换失败：\(message)"
        case .missingAccessToken:
            "Microsoft token 响应没有 access_token。"
        }
    }
}

public final class MicrosoftMailOAuthService: @unchecked Sendable {
    public static let shared = MicrosoftMailOAuthService()

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func authenticate(
        configuration: MicrosoftMailOAuthConfiguration,
        loginHint: String? = nil,
        openURL: @escaping @Sendable (URL) -> Void
    ) async throws -> MicrosoftMailOAuthCredentialPackage {
        let state = Self.randomBase64URL(byteCount: 32)
        let verifier = Self.randomBase64URL(byteCount: 32)
        let challenge = Self.sha256Base64URL(verifier)
        var components = URLComponents(string: "https://login.microsoftonline.com/\(configuration.tenant)/oauth2/v2.0/authorize")!
        var queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "response_mode", value: "query"),
            URLQueryItem(name: "scope", value: configuration.authorizationScopes),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "prompt", value: "select_account")
        ]
        if let loginHint = loginHint?.trimmingCharacters(in: .whitespacesAndNewlines), !loginHint.isEmpty {
            queryItems.append(URLQueryItem(name: "login_hint", value: loginHint))
        }
        components.queryItems = queryItems
        guard let authURL = components.url else { throw MicrosoftMailOAuthError.invalidAuthorizationURL }

        let callbackServer = MicrosoftMailOAuthCallbackServer(port: configuration.callbackPort, callbackPath: configuration.callbackPath)
        async let callbackTask = callbackServer.waitForCallback()
        openURL(authURL)
        let callback = try await callbackTask
        guard callback.state == state else { throw MicrosoftMailOAuthError.stateMismatch }
        guard let code = callback.code, !code.isEmpty else { throw MicrosoftMailOAuthError.missingAuthorizationCode }
        return try await exchangeCode(code, codeVerifier: verifier, configuration: configuration)
    }

    private func exchangeCode(_ code: String, codeVerifier: String, configuration: MicrosoftMailOAuthConfiguration) async throws -> MicrosoftMailOAuthCredentialPackage {
        var request = URLRequest(url: URL(string: "https://login.microsoftonline.com/\(configuration.tenant)/oauth2/v2.0/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Self.formURLEncodedBody([
            "client_id": configuration.clientID,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": configuration.redirectURI,
            "code_verifier": codeVerifier,
            "scope": configuration.authorizationScopes
        ])
        let response: MicrosoftTokenResponse = try await sendJSON(request)
        guard let accessToken = response.accessToken, !accessToken.isEmpty else { throw MicrosoftMailOAuthError.missingAccessToken }
        return MicrosoftMailOAuthCredentialPackage(
            accessToken: accessToken,
            refreshToken: response.refreshToken,
            idToken: response.idToken,
            tokenType: response.tokenType ?? "Bearer",
            scope: response.scope,
            expiresAt: response.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
        )
    }

    private func sendJSON<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? "HTTP \(statusCode)"
            throw MicrosoftMailOAuthError.tokenExchangeFailed("HTTP \(statusCode): \(text)")
        }
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(T.self, from: data)
        } catch {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw MicrosoftMailOAuthError.tokenExchangeFailed("Invalid JSON response: \(error). Body: \(text)")
        }
    }

    private static func formURLEncodedBody(_ values: [String: String]) -> Data {
        Data(values.map { "\(urlEncode($0.key))=\(urlEncode($0.value))" }.joined(separator: "&").utf8)
    }

    private static func urlEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func randomBase64URL(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func sha256Base64URL(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return Data(digest).base64URLEncodedString()
    }
}

private struct MicrosoftTokenResponse: Decodable {
    var accessToken: String?
    var refreshToken: String?
    var idToken: String?
    var tokenType: String?
    var scope: String?
    var expiresIn: Int?
}

private final class MicrosoftMailOAuthCallbackServer: @unchecked Sendable {
    struct Callback: Sendable, Equatable {
        var code: String?
        var state: String?
    }

    private let port: UInt16
    private let callbackPath: String

    init(port: UInt16, callbackPath: String) {
        self.port = port
        self.callbackPath = callbackPath
    }

    func waitForCallback() async throws -> Callback {
        let listener: NWListener
        do {
            listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            throw MicrosoftMailOAuthError.callbackServerFailed(error.localizedDescription)
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let state = CallbackState(continuation: continuation, callbackPath: callbackPath)
                listener.stateUpdateHandler = { newState in
                    if case .failed(let error) = newState {
                        state.resume(throwing: MicrosoftMailOAuthError.callbackServerFailed(error.localizedDescription))
                        listener.cancel()
                    }
                }
                listener.newConnectionHandler = { connection in
                    connection.start(queue: .main)
                    state.handle(connection: connection) { listener.cancel() }
                }
                listener.start(queue: .main)
            }
        } onCancel: {
            listener.cancel()
        }
    }

    private final class CallbackState: @unchecked Sendable {
        private let continuation: CheckedContinuation<Callback, Error>
        private let callbackPath: String
        private var didResume = false

        init(continuation: CheckedContinuation<Callback, Error>, callbackPath: String) {
            self.continuation = continuation
            self.callbackPath = callbackPath
        }

        func handle(connection: NWConnection, finish: @escaping @Sendable () -> Void) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, error in
                defer {
                    connection.cancel()
                    finish()
                }
                if let error {
                    self.resume(throwing: MicrosoftMailOAuthError.callbackServerFailed(error.localizedDescription))
                    return
                }
                guard let data, let request = String(data: data, encoding: .utf8) else {
                    self.resume(throwing: MicrosoftMailOAuthError.callbackServerFailed("Invalid callback request"))
                    return
                }
                let firstLine = request.components(separatedBy: "\r\n").first ?? ""
                let parts = firstLine.split(separator: " ")
                guard parts.count >= 2 else {
                    self.resume(throwing: MicrosoftMailOAuthError.callbackServerFailed("Malformed callback request"))
                    return
                }
                let target = String(parts[1])
                guard target.hasPrefix(self.callbackPath), let components = URLComponents(string: "http://localhost\(target)") else {
                    self.sendHTTP(connection: connection, status: "404 Not Found", body: "Not found")
                    self.resume(throwing: MicrosoftMailOAuthError.callbackServerFailed("Unexpected callback path"))
                    return
                }
                let code = components.queryItems?.first(where: { $0.name == "code" })?.value
                let state = components.queryItems?.first(where: { $0.name == "state" })?.value
                let errorDescription = components.queryItems?.first(where: { $0.name == "error_description" })?.value
                if let errorDescription {
                    self.sendHTTP(connection: connection, status: "400 Bad Request", body: errorDescription)
                    self.resume(throwing: MicrosoftMailOAuthError.tokenExchangeFailed(errorDescription))
                    return
                }
                self.sendHTTP(connection: connection, status: "200 OK", body: "Microsoft mail authentication complete. You can return to Connor.")
                self.resume(returning: Callback(code: code, state: state))
            }
        }

        private func sendHTTP(connection: NWConnection, status: String, body: String) {
            let response = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(Data(body.utf8).count)\r\nConnection: close\r\n\r\n\(body)"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in })
        }

        func resume(returning value: Callback) {
            guard !didResume else { return }
            didResume = true
            continuation.resume(returning: value)
        }

        func resume(throwing error: Error) {
            guard !didResume else { return }
            didResume = true
            continuation.resume(throwing: error)
        }
    }
}

private extension Optional where Wrapped == String {
    var nilIfEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

private extension String {
    var nilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
