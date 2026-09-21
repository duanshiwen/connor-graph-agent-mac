import Foundation
import CryptoKit

/// TokenDance's documented headless Authorization Code + S256 flow.
@MainActor
public final class TokenDanceAPIKeyAuth {
    public static let appURL = "https://duanshiwen.github.io/connor-graph-agent-mac/"
    private let verifier: String
    private let started = Date()
    private var consumed = false
    public let authorizationURL: URL

    public init() {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        let verifier = Self.base64URL(Data(bytes))
        self.verifier = verifier
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        var url = URLComponents(string: "https://tokendance.space/auth")!
        url.queryItems = [URLQueryItem(name: "code_challenge", value: challenge),
                         URLQueryItem(name: "code_challenge_method", value: "S256"),
                         URLQueryItem(name: "app_url", value: Self.appURL),
                         URLQueryItem(name: "key_name", value: "康纳同学")]
        authorizationURL = url.url!
    }

    public func exchange(code: String) async throws -> String {
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !consumed, Date().timeIntervalSince(started) < 600, !code.isEmpty, code.count <= 4096 else {
            throw AuthError.invalidFlow
        }
        consumed = true
        var request = URLRequest(url: URL(string: "https://tokendance.space/portal/api/v1/auth/keys")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["code": code, "code_verifier": verifier, "code_challenge_method": "S256"])
        let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw AuthError.exchangeFailed }
        struct Payload: Decodable { let key: String }
        guard let result = try? JSONDecoder().decode(Payload.self, from: data), !result.key.isEmpty else { throw AuthError.exchangeFailed }
        return result.key
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
    }
    public enum AuthError: LocalizedError {
        case invalidFlow, exchangeFailed
        public var errorDescription: String? { "TokenDance 授权未完成或已过期，请重新授权。若服务端已创建 Key，可在控制台撤销旧 Key。" }
    }
}
