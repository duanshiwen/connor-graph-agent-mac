import Foundation
import Testing
import ConnorGraphAppSupport

@Suite("Local Encrypted Credential Store Tests")
struct LocalEncryptedCredentialStoreTests {
    @Test func encryptedStorePersistsSecretWithoutPlaintextOnDisk() throws {
        let directory = temporaryEncryptedCredentialDirectory()
        let store = LocalEncryptedCredentialStore(rootDirectory: directory)

        try store.saveSecret("sk-secret-local-key", service: "ConnorGraphAgent", account: "openai-compatible-api-key")

        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        #expect(files.contains { $0.lastPathComponent == "master.key" })
        #expect(files.contains { $0.pathExtension == "json" })
        let combined = try files.map { try String(data: Data(contentsOf: $0), encoding: .utf8) ?? "" }.joined(separator: "\n")
        #expect(!combined.contains("sk-secret-local-key"))
        #expect(try store.readSecret(service: "ConnorGraphAgent", account: "openai-compatible-api-key") == "sk-secret-local-key")
    }

    @Test func encryptedStoreCanReadSecretAcrossRepositoryInstances() throws {
        let directory = temporaryEncryptedCredentialDirectory()
        let first = LocalEncryptedCredentialStore(rootDirectory: directory)
        try first.saveSecret("secret-after-restart", service: "svc", account: "acct")

        let second = LocalEncryptedCredentialStore(rootDirectory: directory)

        #expect(try second.readSecret(service: "svc", account: "acct") == "secret-after-restart")
    }

    @Test func encryptedStoreDeletesSecret() throws {
        let directory = temporaryEncryptedCredentialDirectory()
        let store = LocalEncryptedCredentialStore(rootDirectory: directory)
        try store.saveSecret("delete-me", service: "svc", account: "acct")

        try store.deleteSecret(service: "svc", account: "acct")

        #expect(try store.readSecret(service: "svc", account: "acct") == nil)
    }

    @Test func llmSettingsRepositoryDefaultsToLocalEncryptedCredentialStore() {
        let repository = AppLLMSettingsRepository(settingsStore: LocalEncryptedFakeSettingsStore())
        #expect(repository.credentialStore is LocalEncryptedCredentialStore)
    }

    private func temporaryEncryptedCredentialDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-local-credentials-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}

private final class LocalEncryptedFakeSettingsStore: LLMSettingsStore, @unchecked Sendable {
    var values: [String: String] = [:]

    func string(forKey key: String) -> String? { values[key] }
    func set(_ value: String, forKey key: String) { values[key] = value }
}
