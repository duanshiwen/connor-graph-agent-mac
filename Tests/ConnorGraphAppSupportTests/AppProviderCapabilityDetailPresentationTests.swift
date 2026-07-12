import Foundation
import Testing
@testable import ConnorGraphAppSupport

@Suite("Provider Capability Detail Presentation Tests")
struct AppProviderCapabilityDetailPresentationTests {
    @Test func presentsSortedSanitizedEffectiveCapabilitySnapshot() throws {
        let settings = DetailSettingsStore()
        let credentials = DetailCredentialStore()
        let repository = AppProviderCapabilityEvidenceRepository(settingsStore: settings, credentialStore: credentials)
        let connection = detailConnection(baseURL: "https://user:pass@example.com/v1?token=secret#fragment")
        try credentials.saveSecret("key-a", service: AppLLMSettingsRepository.credentialNamespace, account: AppLLMSettingsRepository.apiKeyAccount(for: connection.id))
        let binding = AppProviderCapabilityEvidenceRepository.bindingFingerprint(connection: connection, credential: "key-a")
        try repository.save(AppProviderCapabilitySnapshot(connectionID: connection.id, evidence: [
            AppProviderCapabilityEvidence(capability: .hostedImageGeneration, status: .unknown, endpointFamily: "openai_responses", modelID: "gpt-test", bindingFingerprint: binding, sanitizedDiagnostic: "temporary upstream failure"),
            AppProviderCapabilityEvidence(capability: .chatCompletions, status: .verified, endpointFamily: "openai_chat_completions", modelID: "gpt-test", bindingFingerprint: binding, sanitizedDiagnostic: "Authorization: Bearer secret")
        ]))

        let presentation = repository.detailPresentation(for: connection)

        #expect(presentation.endpoint == "https://example.com/v1")
        #expect(presentation.capabilities.map(\.capability) == [.chatCompletions, .hostedImageGeneration])
        #expect(presentation.capabilities[0].statusTitle == "已验证支持")
        #expect(presentation.capabilities[0].note == nil)
        #expect(presentation.capabilities[1].note == "temporary upstream failure")
    }

    @Test func reportsExpiredEvidenceWithoutMutatingStoredSnapshot() throws {
        let settings = DetailSettingsStore()
        let credentials = DetailCredentialStore()
        let repository = AppProviderCapabilityEvidenceRepository(settingsStore: settings, credentialStore: credentials)
        let connection = detailConnection()
        try credentials.saveSecret("new-key", service: AppLLMSettingsRepository.credentialNamespace, account: AppLLMSettingsRepository.apiKeyAccount(for: connection.id))
        try repository.save(AppProviderCapabilitySnapshot(connectionID: connection.id, evidence: [
            AppProviderCapabilityEvidence(capability: .responses, status: .verified, endpointFamily: "openai_responses", modelID: "gpt-test", bindingFingerprint: "old-binding")
        ]))

        let presentation = repository.detailPresentation(for: connection)

        #expect(presentation.capabilities.first?.status == .expired)
        #expect(presentation.capabilities.first?.statusTitle == "证据已失效")
        #expect(repository.loadAll().first?.evidence.first?.status == .verified)
    }

    @Test func legacyConnectionWithoutSnapshotProducesEmptyReadonlyPresentation() {
        let repository = AppProviderCapabilityEvidenceRepository(settingsStore: DetailSettingsStore(), credentialStore: DetailCredentialStore())

        let presentation = repository.detailPresentation(for: detailConnection())

        #expect(!presentation.hasSnapshot)
        #expect(presentation.capabilities.isEmpty)
    }
}

private func detailConnection(baseURL: String = "https://example.com/v1") -> AppLLMConnectionConfig {
    AppLLMConnectionConfig(id: "detail-connection", name: "Detail Provider", providerMode: .openAICompatible, baseURLString: baseURL, model: "gpt-test")
}

private final class DetailSettingsStore: LLMSettingsStore, @unchecked Sendable {
    private var values: [String: String] = [:]
    func string(forKey key: String) -> String? { values[key] }
    func set(_ value: String, forKey key: String) { values[key] = value }
}

private final class DetailCredentialStore: CredentialStore, @unchecked Sendable {
    private var values: [String: String] = [:]
    func saveSecret(_ secret: String, service: String, account: String) throws { values["\(service):\(account)"] = secret }
    func readSecret(service: String, account: String) throws -> String? { values["\(service):\(account)"] }
    func deleteSecret(service: String, account: String) throws { values.removeValue(forKey: "\(service):\(account)") }
}
