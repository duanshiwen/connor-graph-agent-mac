import Foundation
import Testing
@testable import ConnorGraphAppSupport

@Suite("TokenDance PKCE authorization")
@MainActor struct TokenDanceAPIKeyAuthTests {
    @Test func authorizationUsesFixedOriginAndKeepsVerifierLocal() throws {
        let flow = TokenDanceAPIKeyAuth()
        let url = try #require(URLComponents(url: flow.authorizationURL, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (url.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(url.scheme == "https")
        #expect(url.host == "tokendance.space")
        #expect(url.path == "/auth")
        #expect(items["code_challenge_method"] == "S256")
        #expect(items["app_url"] == TokenDanceAPIKeyAuth.appURL)
        let challenge = try #require(items["code_challenge"])
        #expect(challenge.count == 43)
        #expect(!challenge.contains("="))
        #expect(items["code_verifier"] == nil)
        #expect(items["callback_url"] == nil)
        #expect(flow.authorizationURL != TokenDanceAPIKeyAuth().authorizationURL)
    }
    @Test func emptyCodeRejectedWithoutNetwork() async {
        await #expect(throws: TokenDanceAPIKeyAuth.AuthError.self) { try await TokenDanceAPIKeyAuth().exchange(code: " ") }
    }
}
