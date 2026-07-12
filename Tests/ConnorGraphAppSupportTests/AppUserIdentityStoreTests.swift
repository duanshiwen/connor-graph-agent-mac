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

    @Test func accountCredentialStoreEncryptsAndDeletesToken() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ConnorIdentityCredentialTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AppConnorAccountCredentialStore(store: LocalEncryptedCredentialStore(rootDirectory: root))

        try store.saveToken("private-jwt-token")
        #expect(try store.token() == "private-jwt-token")

        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        let contents = try files.filter { $0.pathExtension == "json" }.map { try String(contentsOf: $0, encoding: .utf8) }.joined()
        #expect(!contents.contains("private-jwt-token"))

        try store.clearToken()
        #expect(try store.token() == nil)
    }
}
