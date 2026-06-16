import Foundation
import CryptoKit
import Network

public enum AppLLMOAuthProvider: Sendable, Equatable {
    case claude
    case chatGPT
    case githubCopilot
}

public struct AppLLMOAuthTokens: Codable, Sendable, Equatable {
    public var accessToken: String
    public var idToken: String?
    public var refreshToken: String?
    public var expiresAt: Double?

    public init(accessToken: String, idToken: String? = nil, refreshToken: String? = nil, expiresAt: Double? = nil) {
        self.accessToken = accessToken
        self.idToken = idToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}

public struct AppLLMGitHubDeviceCode: Sendable, Equatable {
    public var deviceCode: String
    public var userCode: String
    public var verificationURI: String
    public var expiresIn: Int
    public var interval: Int
}

public enum AppLLMOAuthError: Error, Sendable, LocalizedError, Equatable {
    case invalidURL(String)
    case missingAuthorizationCode
    case missingOAuthState
    case oauthStateExpired
    case stateMismatch
    case callbackServerFailed(String)
    case tokenExchangeFailed(String)
    case deviceAuthorizationPending
    case deviceAuthorizationDenied
    case deviceAuthorizationExpired
    case missingToken(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let value): "Invalid OAuth URL: \(value)"
        case .missingAuthorizationCode: "No authorization code was received."
        case .missingOAuthState: "OAuth session was not started. Please start again."
        case .oauthStateExpired: "OAuth session expired. Please start again."
        case .stateMismatch: "OAuth state mismatch. Please start again."
        case .callbackServerFailed(let message): "Callback server failed: \(message)"
        case .tokenExchangeFailed(let message): "Token exchange failed: \(message)"
        case .deviceAuthorizationPending: "Device authorization is still pending."
        case .deviceAuthorizationDenied: "Device authorization was denied."
        case .deviceAuthorizationExpired: "Device authorization expired."
        case .missingToken(let name): "Token response did not include \(name)."
        }
    }
}

public final class AppLLMOAuthService: @unchecked Sendable {
    public struct ClaudePreparedFlow: Sendable, Equatable {
        public var authURL: URL
        public var state: String
        public var codeVerifier: String
        public var expiresAt: Date
    }

    public struct ChatGPTPreparedFlow: Sendable, Equatable {
        public var authURL: URL
        public var state: String
        public var codeVerifier: String
        public var expiresAt: Date
    }

    public struct ChatGPTAuthenticationResult: Sendable, Equatable {
        public var tokens: AppLLMOAuthTokens
        public var apiKey: String
    }

    public static let shared = AppLLMOAuthService()

    private let session: URLSession
    private var currentClaudeFlow: ClaudePreparedFlow?
    private var currentChatGPTFlow: ChatGPTPreparedFlow?

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Claude OAuth

    public func prepareClaudeOAuth() throws -> ClaudePreparedFlow {
        let state = Self.randomBase64URL(byteCount: 32)
        let verifier = Self.randomBase64URL(byteCount: 32)
        let challenge = Self.sha256Base64URL(verifier)
        let expiresAt = Date().addingTimeInterval(10 * 60)
        var components = URLComponents(string: "https://claude.ai/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: "9d1c250a-e61b-44d9-88ed-5944d1962f5e"),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: "https://console.anthropic.com/oauth/code/callback"),
            URLQueryItem(name: "scope", value: "org:create_api_key user:profile user:inference"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]
        guard let url = components.url else { throw AppLLMOAuthError.invalidURL("Claude auth URL") }
        let flow = ClaudePreparedFlow(authURL: url, state: state, codeVerifier: verifier, expiresAt: expiresAt)
        currentClaudeFlow = flow
        return flow
    }

    public func exchangeClaudeCode(_ authorizationCode: String) async throws -> AppLLMOAuthTokens {
        guard let flow = currentClaudeFlow else { throw AppLLMOAuthError.missingOAuthState }
        guard Date() < flow.expiresAt else {
            currentClaudeFlow = nil
            throw AppLLMOAuthError.oauthStateExpired
        }
        let cleanedCode = authorizationCode
            .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
            .split(separator: "&", maxSplits: 1, omittingEmptySubsequences: false)[0]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedCode.isEmpty else { throw AppLLMOAuthError.missingAuthorizationCode }

        let body: [String: String] = [
            "grant_type": "authorization_code",
            "client_id": "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
            "code": cleanedCode,
            "redirect_uri": "https://console.anthropic.com/oauth/code/callback",
            "code_verifier": flow.codeVerifier,
            "state": flow.state
        ]
        var request = URLRequest(url: URL(string: "https://platform.claude.com/v1/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ConnorGraphAgent/1", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(body)
        let response: ClaudeTokenResponse = try await sendJSON(request)
        guard let accessToken = response.accessToken, !accessToken.isEmpty else { throw AppLLMOAuthError.missingToken("access_token") }
        currentClaudeFlow = nil
        return AppLLMOAuthTokens(
            accessToken: accessToken,
            refreshToken: response.refreshToken,
            expiresAt: response.expiresIn.map { Date().timeIntervalSince1970 * 1000 + Double($0) * 1000 }
        )
    }

    // MARK: - ChatGPT / Codex OAuth

    public func authenticateChatGPT(openURL: @escaping @Sendable (URL) -> Void) async throws -> ChatGPTAuthenticationResult {
        let flow = try prepareChatGPTOAuth()
        let callbackServer = AppOAuthCallbackServer(port: 1455, callbackPath: "/auth/callback")
        async let callbackTask = callbackServer.waitForCallback()
        openURL(flow.authURL)
        let callback = try await callbackTask
        guard callback.state == flow.state else { throw AppLLMOAuthError.stateMismatch }
        guard let code = callback.code, !code.isEmpty else { throw AppLLMOAuthError.missingAuthorizationCode }
        let tokens = try await exchangeChatGPTCode(code, codeVerifier: flow.codeVerifier)
        guard let idToken = tokens.idToken, !idToken.isEmpty else { throw AppLLMOAuthError.missingToken("id_token") }
        let apiKey = try await exchangeChatGPTIDTokenForAPIKey(idToken)
        return ChatGPTAuthenticationResult(tokens: tokens, apiKey: apiKey)
    }

    public func prepareChatGPTOAuth() throws -> ChatGPTPreparedFlow {
        let state = Self.randomBase64URL(byteCount: 32)
        let verifier = Self.randomBase64URL(byteCount: 32)
        let challenge = Self.sha256Base64URL(verifier)
        let expiresAt = Date().addingTimeInterval(5 * 60)
        var components = URLComponents(string: "https://auth.openai.com/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: "app_EMoamEEZ73f0CkXaXp7hrann"),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: "http://localhost:1455/auth/callback"),
            URLQueryItem(name: "scope", value: "openid profile email offline_access"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
            URLQueryItem(name: "id_token_add_organizations", value: "true")
        ]
        guard let url = components.url else { throw AppLLMOAuthError.invalidURL("ChatGPT auth URL") }
        let flow = ChatGPTPreparedFlow(authURL: url, state: state, codeVerifier: verifier, expiresAt: expiresAt)
        currentChatGPTFlow = flow
        return flow
    }

    public func exchangeChatGPTCode(_ code: String, codeVerifier: String) async throws -> AppLLMOAuthTokens {
        var request = URLRequest(url: URL(string: "https://auth.openai.com/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Self.formURLEncodedBody([
            "grant_type": "authorization_code",
            "client_id": "app_EMoamEEZ73f0CkXaXp7hrann",
            "code": code,
            "redirect_uri": "http://localhost:1455/auth/callback",
            "code_verifier": codeVerifier
        ])
        let response: ChatGPTTokenResponse = try await sendJSON(request)
        guard let accessToken = response.accessToken, !accessToken.isEmpty else { throw AppLLMOAuthError.missingToken("access_token") }
        return AppLLMOAuthTokens(
            accessToken: accessToken,
            idToken: response.idToken,
            refreshToken: response.refreshToken,
            expiresAt: response.expiresIn.map { Date().timeIntervalSince1970 * 1000 + Double($0) * 1000 }
        )
    }

    public func exchangeChatGPTIDTokenForAPIKey(_ idToken: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://auth.openai.com/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Self.formURLEncodedBody([
            "grant_type": "urn:ietf:params:oauth:grant-type:token-exchange",
            "client_id": "app_EMoamEEZ73f0CkXaXp7hrann",
            "subject_token": idToken,
            "subject_token_type": "urn:ietf:params:oauth:token-type:id_token",
            "requested_token": "openai-api-key"
        ])
        let response: APIKeyExchangeResponse = try await sendJSON(request)
        guard let apiKey = response.accessToken, !apiKey.isEmpty else { throw AppLLMOAuthError.missingToken("openai-api-key") }
        return apiKey
    }

    // MARK: - GitHub Copilot OAuth

    public func startGitHubCopilotDeviceFlow() async throws -> AppLLMGitHubDeviceCode {
        var request = URLRequest(url: URL(string: "https://github.com/login/device/code")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formURLEncodedBody([
            "client_id": "Iv1.b507a08c87ecfe98",
            "scope": "read:user"
        ])
        let response: GitHubDeviceCodeResponse = try await sendJSON(request)
        guard let deviceCode = response.deviceCode, let userCode = response.userCode else { throw AppLLMOAuthError.missingToken("device_code") }
        return AppLLMGitHubDeviceCode(
            deviceCode: deviceCode,
            userCode: userCode,
            verificationURI: response.verificationURI ?? "https://github.com/login/device",
            expiresIn: response.expiresIn ?? 900,
            interval: response.interval ?? 5
        )
    }

    public func pollGitHubCopilotTokens(deviceCode: AppLLMGitHubDeviceCode) async throws -> AppLLMOAuthTokens {
        let deadline = Date().addingTimeInterval(TimeInterval(deviceCode.expiresIn))
        var interval = max(deviceCode.interval, 5)
        while Date() < deadline {
            try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            do {
                let githubAccessToken = try await exchangeGitHubDeviceCode(deviceCode.deviceCode)
                return try await exchangeGitHubTokenForCopilotTokens(githubAccessToken)
            } catch AppLLMOAuthError.deviceAuthorizationPending {
                continue
            } catch AppLLMOAuthError.tokenExchangeFailed(let message) where message.contains("slow_down") {
                interval += 5
                continue
            }
        }
        throw AppLLMOAuthError.deviceAuthorizationExpired
    }

    private func exchangeGitHubDeviceCode(_ deviceCode: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formURLEncodedBody([
            "client_id": "Iv1.b507a08c87ecfe98",
            "device_code": deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
        ])
        let response: GitHubDeviceTokenResponse = try await sendJSON(request)
        if let error = response.error {
            switch error {
            case "authorization_pending": throw AppLLMOAuthError.deviceAuthorizationPending
            case "slow_down": throw AppLLMOAuthError.tokenExchangeFailed("slow_down")
            case "expired_token": throw AppLLMOAuthError.deviceAuthorizationExpired
            case "access_denied": throw AppLLMOAuthError.deviceAuthorizationDenied
            default: throw AppLLMOAuthError.tokenExchangeFailed(response.errorDescription ?? error)
            }
        }
        guard let token = response.accessToken, !token.isEmpty else { throw AppLLMOAuthError.missingToken("github access_token") }
        return token
    }

    public static func copilotBaseURL(from token: String) -> String? {
        guard let range = token.range(of: #"proxy-ep=([^;]+)"#, options: .regularExpression) else { return nil }
        let segment = String(token[range])
        let host = segment
            .replacingOccurrences(of: "proxy-ep=", with: "")
            .replacingOccurrences(of: "proxy.", with: "api.")
        guard !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return "https://\(host)"
    }

    private func exchangeGitHubTokenForCopilotTokens(_ githubAccessToken: String) async throws -> AppLLMOAuthTokens {
        var request = URLRequest(url: URL(string: "https://api.github.com/copilot_internal/v2/token")!)
        request.httpMethod = "GET"
        request.setValue("token \(githubAccessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("copilot-chat/0.35.0", forHTTPHeaderField: "Editor-Plugin-Version")
        request.setValue("vscode-chat", forHTTPHeaderField: "Copilot-Integration-Id")
        let response: CopilotTokenResponse = try await sendJSON(request)
        guard let token = response.token, !token.isEmpty else { throw AppLLMOAuthError.missingToken("copilot token") }
        return AppLLMOAuthTokens(
            accessToken: token,
            refreshToken: githubAccessToken,
            expiresAt: response.expiresAt.map { Double($0) * 1000 }
        )
    }

    // MARK: - HTTP helpers

    private func sendJSON<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode >= 200, statusCode < 300 else {
            let text = String(data: data, encoding: .utf8) ?? "HTTP \(statusCode)"
            throw AppLLMOAuthError.tokenExchangeFailed("HTTP \(statusCode): \(text)")
        }
        do {
            return try JSONDecoder.oauthDecoder.decode(T.self, from: data)
        } catch {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw AppLLMOAuthError.tokenExchangeFailed("Invalid JSON response: \(error). Body: \(text)")
        }
    }

    private static func formURLEncodedBody(_ values: [String: String]) -> Data {
        let body = values
            .map { key, value in "\(urlEncode(key))=\(urlEncode(value))" }
            .joined(separator: "&")
        return Data(body.utf8)
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

private final class AppOAuthCallbackServer: @unchecked Sendable {
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
            throw AppLLMOAuthError.callbackServerFailed(error.localizedDescription)
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let state = CallbackState(continuation: continuation, callbackPath: callbackPath)
                listener.stateUpdateHandler = { newState in
                    if case .failed(let error) = newState {
                        state.resume(throwing: AppLLMOAuthError.callbackServerFailed(error.localizedDescription))
                        listener.cancel()
                    }
                }
                listener.newConnectionHandler = { connection in
                    connection.start(queue: .main)
                    state.handle(connection: connection) {
                        listener.cancel()
                    }
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
                    self.resume(throwing: AppLLMOAuthError.callbackServerFailed(error.localizedDescription))
                    return
                }
                guard let data, let request = String(data: data, encoding: .utf8) else {
                    self.resume(throwing: AppLLMOAuthError.callbackServerFailed("Invalid callback request"))
                    return
                }
                let firstLine = request.components(separatedBy: "\r\n").first ?? ""
                let parts = firstLine.split(separator: " ")
                guard parts.count >= 2 else {
                    self.resume(throwing: AppLLMOAuthError.callbackServerFailed("Malformed callback request"))
                    return
                }
                let target = String(parts[1])
                guard target.hasPrefix(self.callbackPath), let components = URLComponents(string: "http://localhost\(target)") else {
                    self.sendHTTP(connection: connection, status: "404 Not Found", body: "Not found")
                    self.resume(throwing: AppLLMOAuthError.callbackServerFailed("Unexpected callback path"))
                    return
                }
                let code = components.queryItems?.first(where: { $0.name == "code" })?.value
                let state = components.queryItems?.first(where: { $0.name == "state" })?.value
                self.sendHTTP(connection: connection, status: "200 OK", body: "Authentication complete. You can return to Connor.")
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

private extension JSONDecoder {
    static var oauthDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
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

private struct ClaudeTokenResponse: Decodable {
    var accessToken: String?
    var refreshToken: String?
    var expiresIn: Int?
}

private struct ChatGPTTokenResponse: Decodable {
    var idToken: String?
    var accessToken: String?
    var refreshToken: String?
    var expiresIn: Int?
}

private struct APIKeyExchangeResponse: Decodable {
    var accessToken: String?
    var tokenType: String?
}

private struct GitHubDeviceCodeResponse: Decodable {
    var deviceCode: String?
    var userCode: String?
    var verificationURI: String?
    var expiresIn: Int?
    var interval: Int?
}

private struct GitHubDeviceTokenResponse: Decodable {
    var accessToken: String?
    var tokenType: String?
    var scope: String?
    var error: String?
    var errorDescription: String?
}

private struct CopilotTokenResponse: Decodable {
    var token: String?
    var expiresAt: Int?
}
