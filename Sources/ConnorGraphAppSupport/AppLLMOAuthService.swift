import Foundation
import CryptoKit
import Network
import os

public enum AppLLMOAuthProvider: Sendable, Equatable {
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
    private var currentChatGPTFlow: ChatGPTPreparedFlow?
    private static let logger = Logger(subsystem: "com.shiwen.connor-graph-agent-mac", category: "LLMOAuth")

    /// The single in-flight local callback server. Keeping one reference and
    /// cancelling the previous instance before every new attempt guarantees the
    /// callback port is released on retry, so a failed or abandoned attempt can
    /// never leave port 1455 bound and silently break every later login.
    private let callbackLock = NSLock()
    private var activeCallbackServer: AppOAuthCallbackServer?

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - ChatGPT / Codex OAuth

    public func authenticateChatGPT(openURL: @escaping @Sendable (URL) -> Void) async throws -> ChatGPTAuthenticationResult {
        let flow = try prepareChatGPTOAuth()
        let callbackServer = beginCallbackServerSession()
        defer { endCallbackServerSession(callbackServer) }
        Self.logger.info("ChatGPT OAuth: opening browser, waiting for localhost:1455 callback (state=\(flow.state.prefix(8)))")
        openURL(flow.authURL)
        let callback: AppOAuthCallbackServer.Callback
        do {
            callback = try await callbackServer.waitForCallback(timeout: 5 * 60)
        } catch {
            Self.logger.error("ChatGPT OAuth: callback phase failed: \(error.localizedDescription)")
            throw error
        }
        guard callback.state == flow.state else {
            let expectedPrefix = flow.state.prefix(8)
            let receivedPrefix = callback.state.map { String($0.prefix(8)) } ?? "nil"
            Self.logger.error("ChatGPT OAuth: state mismatch (expected \(expectedPrefix), got \(receivedPrefix))")
            throw AppLLMOAuthError.stateMismatch
        }
        guard let code = callback.code, !code.isEmpty else {
            Self.logger.error("ChatGPT OAuth: callback arrived without an authorization code")
            throw AppLLMOAuthError.missingAuthorizationCode
        }
        Self.logger.info("ChatGPT OAuth: received authorization code, exchanging for tokens…")
        let tokens = try await exchangeChatGPTCode(code, codeVerifier: flow.codeVerifier)
        guard let idToken = tokens.idToken, !idToken.isEmpty else { throw AppLLMOAuthError.missingToken("id_token") }
        Self.logger.info("ChatGPT OAuth: tokens exchanged, exchanging id_token for API key…")
        let apiKey = try await exchangeChatGPTIDTokenForAPIKey(idToken)
        Self.logger.info("ChatGPT OAuth: login completed successfully")
        return ChatGPTAuthenticationResult(tokens: tokens, apiKey: apiKey)
    }

    /// Cancels any callback listener a previous attempt may have left running
    /// (abandoned sheet, closed tab, timed-out wait) and hands back the fresh
    /// server for this attempt. Retrying login must never hit "address already in use".
    private func beginCallbackServerSession() -> AppOAuthCallbackServer {
        callbackLock.lock()
        defer { callbackLock.unlock() }
        activeCallbackServer?.cancel()
        let server = AppOAuthCallbackServer(port: 1455, callbackPath: "/auth/callback")
        activeCallbackServer = server
        return server
    }

    private func endCallbackServerSession(_ server: AppOAuthCallbackServer) {
        callbackLock.lock()
        defer { callbackLock.unlock() }
        if activeCallbackServer === server {
            activeCallbackServer = nil
        }
        server.cancel()
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
            URLQueryItem(name: "scope", value: "openid profile email offline_access api.connectors.read api.connectors.invoke"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "originator", value: "codex_cli_rs")
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

    public func refreshGitHubCopilotTokens(githubAccessToken: String) async throws -> AppLLMOAuthTokens {
        try await exchangeGitHubTokenForCopilotTokens(githubAccessToken)
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
    private let lock = NSLock()
    private var listeners: [NWListener] = []

    init(port: UInt16, callbackPath: String) {
        self.port = port
        self.callbackPath = callbackPath
    }

    func waitForCallback(timeout: TimeInterval) async throws -> Callback {
        // Race the callback wait against a deadline so a lost callback (closed
        // tab, browser hiccup, localhost swallowed by a proxy) can never leave
        // the UI hanging in "等待浏览器回调…" forever.
        try await withThrowingTaskGroup(of: Callback.self) { group in
            group.addTask { try await self.waitForCallbackCore() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw AppLLMOAuthError.oauthStateExpired
            }
            do {
                let callback = try await group.next()!
                group.cancelAll()
                return callback
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    /// Cancels every active listener and releases the callback port. Safe to
    /// call from any thread; used to clean up abandoned or retried attempts.
    func cancel() {
        lock.lock()
        let toCancel = listeners
        listeners.removeAll()
        lock.unlock()
        for listener in toCancel {
            listener.cancel()
        }
    }

    private func installListeners(_ newListeners: [NWListener]) {
        lock.lock()
        listeners = newListeners
        lock.unlock()
    }

    private func waitForCallbackCore() async throws -> Callback {
        let listeners = makeLoopbackListeners()
        guard !listeners.isEmpty else {
            throw AppLLMOAuthError.callbackServerFailed("无法创建本地回调服务器（端口 \(port)）。")
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Callback, Error>) in
                let state = CallbackState(continuation: continuation, callbackPath: callbackPath)
                installListeners(listeners)
                let status = ListenerStatus(total: listeners.count) { error in
                    state.resume(throwing: AppLLMOAuthError.callbackServerFailed(Self.describeBindError(error, port: self.port)))
                }
                for listener in listeners {
                    listener.stateUpdateHandler = { newState in
                        switch newState {
                        case .ready:
                            status.becameReady()
                        case .failed(let error):
                            status.failedWith(error)
                        case .cancelled:
                            state.resume(throwing: AppLLMOAuthError.callbackServerFailed("Callback server was cancelled."))
                        default:
                            break
                        }
                    }
                    listener.newConnectionHandler = { connection in
                        connection.start(queue: .main)
                        state.handle(connection: connection) {
                            self.cancel()
                        }
                    }
                    listener.start(queue: .main)
                }
            }
        } onCancel: {
            cancel()
        }
    }

    /// Listens on the loopback interfaces only (127.0.0.1 and ::1), exactly like
    /// the Codex CLI, instead of the wildcard address. Binding both families is
    /// tolerated: on some macOS versions the second bind reports EADDRINUSE, and
    /// either family alone still serves "localhost" callbacks.
    private func makeLoopbackListeners() -> [NWListener] {
        var result: [NWListener] = []
        let loopbackHosts: [NWEndpoint.Host] = [
            .ipv4(IPv4Address("127.0.0.1")!),
            .ipv6(IPv6Address("::1")!)
        ]
        for host in loopbackHosts {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: host, port: NWEndpoint.Port(rawValue: port)!)
            if let listener = try? NWListener(using: parameters) {
                result.append(listener)
            }
        }
        return result
    }

    private static func describeBindError(_ error: Error, port: UInt16) -> String {
        let detail = error.localizedDescription
        if detail.localizedCaseInsensitiveContains("address already in use") || detail.localizedCaseInsensitiveContains("占用") {
            return "本地回调端口 \(port) 被其他程序占用（\(detail)）。请关闭占用 \(port) 端口的程序（例如 Codex CLI）后重试。"
        }
        return "本地回调服务器启动失败：\(detail)"
    }

    /// Tracks per-listener startup status. Only fails the login when every
    /// loopback family failed to bind and none became ready; a single family is
    /// enough because "localhost" resolves to either 127.0.0.1 or ::1.
    private final class ListenerStatus: @unchecked Sendable {
        private let total: Int
        private var readyCount = 0
        private var failedCount = 0
        private let onAllFailed: @Sendable (Error) -> Void

        init(total: Int, onAllFailed: @escaping @Sendable (Error) -> Void) {
            self.total = total
            self.onAllFailed = onAllFailed
        }

        func becameReady() {
            readyCount += 1
        }

        func failedWith(_ error: Error) {
            failedCount += 1
            if readyCount == 0, failedCount >= total {
                onAllFailed(error)
            }
        }
    }

    private final class CallbackState: @unchecked Sendable {
        private static let headerTerminator = Data("\r\n\r\n".utf8)

        private let continuation: CheckedContinuation<Callback, Error>
        private let callbackPath: String
        private var didResume = false

        init(continuation: CheckedContinuation<Callback, Error>, callbackPath: String) {
            self.continuation = continuation
            self.callbackPath = callbackPath
        }

        func handle(connection: NWConnection, finish: @escaping @Sendable () -> Void) {
            receive(connection: connection, buffer: Data(), finish: finish)
        }

        // Browsers open speculative preconnections that never carry a request, and a
        // single receive() can return a partial HTTP request head, so the server must
        // keep reading until the full head arrives and drop empty connections instead
        // of failing the whole login flow.
        private func receive(connection: NWConnection, buffer: Data, finish: @escaping @Sendable () -> Void) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [self] data, _, isComplete, error in
                guard !didResume else {
                    connection.cancel()
                    return
                }
                var accumulated = buffer
                if let data { accumulated.append(data) }

                if error == nil, !isComplete, accumulated.range(of: Self.headerTerminator) == nil {
                    receive(connection: connection, buffer: accumulated, finish: finish)
                    return
                }
                if accumulated.isEmpty {
                    connection.cancel()
                    return
                }
                guard let request = String(data: accumulated, encoding: .utf8) else {
                    sendHTTP(connection: connection, status: "400 Bad Request", body: "Invalid callback request")
                    return
                }
                let firstLine = request.components(separatedBy: "\r\n").first ?? ""
                let parts = firstLine.split(separator: " ")
                guard parts.count >= 2, let components = URLComponents(string: "http://localhost\(parts[1])"), components.path == callbackPath else {
                    sendHTTP(connection: connection, status: "404 Not Found", body: "Not found")
                    return
                }
                let queryItems = components.queryItems ?? []
                if let oauthError = queryItems.first(where: { $0.name == "error" })?.value {
                    let description = queryItems.first(where: { $0.name == "error_description" })?.value
                    sendHTTP(connection: connection, status: "200 OK", body: "Authentication failed: \(oauthError). You can close this page and retry in Connor.")
                    resume(throwing: AppLLMOAuthError.tokenExchangeFailed(description.map { "\(oauthError): \($0)" } ?? oauthError))
                    finish()
                    return
                }
                guard let code = queryItems.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
                    sendHTTP(connection: connection, status: "400 Bad Request", body: "Missing authorization code.")
                    return
                }
                let state = queryItems.first(where: { $0.name == "state" })?.value
                sendHTTP(connection: connection, status: "200 OK", body: "Authentication complete. You can return to Connor.")
                resume(returning: Callback(code: code, state: state))
                finish()
            }
        }

        private func sendHTTP(connection: NWConnection, status: String, body: String) {
            let response = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(Data(body.utf8).count)\r\nConnection: close\r\n\r\n\(body)"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
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
