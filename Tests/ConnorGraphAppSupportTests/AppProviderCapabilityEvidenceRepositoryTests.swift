import Foundation
import Testing
import ConnorGraphAppSupport

private final class CapabilityEvidenceSettingsStore: LLMSettingsStore, @unchecked Sendable {
    var values: [String: String] = [:]
    func string(forKey key: String) -> String? { values[key] }
    func set(_ value: String, forKey key: String) { values[key] = value }
}

private final class CapabilityEvidenceCredentialStore: CredentialStore, @unchecked Sendable {
    var values: [String: String] = [:]
    func saveSecret(_ secret: String, service: String, account: String) throws { values["\(service):\(account)"] = secret }
    func readSecret(service: String, account: String) throws -> String? { values["\(service):\(account)"] }
    func deleteSecret(service: String, account: String) throws { values.removeValue(forKey: "\(service):\(account)") }
}

private func capabilityConnection(model: String = "model-a", baseURL: String = "https://example.com/v1") -> AppLLMConnectionConfig {
    AppLLMConnectionConfig(
        id: "connection-a",
        name: "Example",
        providerMode: .openAICompatible,
        baseURLString: baseURL,
        model: model,
        selectedModel: model,
        hasAPIKey: true
    )
}

@Test func capabilityEvidencePersistsWithoutPlaintextCredential() throws {
    let settings = CapabilityEvidenceSettingsStore()
    let credentials = CapabilityEvidenceCredentialStore()
    let repository = AppProviderCapabilityEvidenceRepository(settingsStore: settings, credentialStore: credentials)
    let connection = capabilityConnection()
    try credentials.saveSecret("super-secret", service: AppLLMSettingsRepository.credentialNamespace, account: AppLLMSettingsRepository.apiKeyAccount(for: connection.id))
    let fingerprint = AppProviderCapabilityEvidenceRepository.bindingFingerprint(connection: connection, credential: "super-secret")

    try repository.replaceEvidence(AppProviderCapabilityEvidence(
        capability: .responses,
        status: .verified,
        endpointFamily: "openai_responses",
        modelID: connection.effectiveModel,
        bindingFingerprint: fingerprint,
        sanitizedDiagnostic: "HTTP 200"
    ), connectionID: connection.id)

    let effective = try repository.effectiveEvidence(for: .responses, connection: connection)
    #expect(effective?.status == .verified)
    #expect(effective?.sanitizedDiagnostic == "HTTP 200")
    #expect(settings.values.values.joined().contains("super-secret") == false)
}

@Test func capabilityEvidenceExpiresWhenConnectionBindingChanges() throws {
    let settings = CapabilityEvidenceSettingsStore()
    let credentials = CapabilityEvidenceCredentialStore()
    let repository = AppProviderCapabilityEvidenceRepository(settingsStore: settings, credentialStore: credentials)
    let original = capabilityConnection()
    try credentials.saveSecret("key-a", service: AppLLMSettingsRepository.credentialNamespace, account: AppLLMSettingsRepository.apiKeyAccount(for: original.id))
    try repository.replaceEvidence(AppProviderCapabilityEvidence(
        capability: .hostedImageGeneration,
        status: .verified,
        endpointFamily: "openai_responses",
        modelID: original.effectiveModel,
        bindingFingerprint: AppProviderCapabilityEvidenceRepository.bindingFingerprint(connection: original, credential: "key-a")
    ), connectionID: original.id)

    #expect(try repository.effectiveEvidence(for: .hostedImageGeneration, connection: original)?.status == .verified)
    #expect(try repository.effectiveEvidence(for: .hostedImageGeneration, connection: capabilityConnection(model: "model-b"))?.status == .expired)
    #expect(try repository.effectiveEvidence(for: .hostedImageGeneration, connection: capabilityConnection(baseURL: "https://other.example/v1"))?.status == .expired)

    try credentials.saveSecret("key-b", service: AppLLMSettingsRepository.credentialNamespace, account: AppLLMSettingsRepository.apiKeyAccount(for: original.id))
    #expect(try repository.effectiveEvidence(for: .hostedImageGeneration, connection: original)?.status == .expired)
}

@Test func legacyConnectionWithoutEvidenceRemainsUnverifiedWithoutMutation() throws {
    let settings = CapabilityEvidenceSettingsStore()
    let credentials = CapabilityEvidenceCredentialStore()
    let repository = AppProviderCapabilityEvidenceRepository(settingsStore: settings, credentialStore: credentials)
    let connection = capabilityConnection()
    try credentials.saveSecret("legacy-key", service: AppLLMSettingsRepository.credentialNamespace, account: AppLLMSettingsRepository.apiKeyAccount(for: connection.id))

    let effective = try repository.effectiveEvidence(for: .hostedImageGeneration, connection: connection)

    #expect(effective == nil)
    #expect(repository.loadAll().isEmpty)
}

@Test func evidenceFromOlderProbeProtocolExpiresLocally() throws {
    let settings = CapabilityEvidenceSettingsStore()
    let credentials = CapabilityEvidenceCredentialStore()
    let repository = AppProviderCapabilityEvidenceRepository(settingsStore: settings, credentialStore: credentials)
    let connection = capabilityConnection()
    try credentials.saveSecret("key-a", service: AppLLMSettingsRepository.credentialNamespace, account: AppLLMSettingsRepository.apiKeyAccount(for: connection.id))
    try repository.replaceEvidence(AppProviderCapabilityEvidence(
        capability: .hostedImageGeneration,
        status: .verified,
        endpointFamily: "openai_responses",
        modelID: connection.effectiveModel,
        bindingFingerprint: AppProviderCapabilityEvidenceRepository.bindingFingerprint(connection: connection, credential: "key-a"),
        protocolVersion: AppProviderCapabilityEvidenceRepository.currentProtocolVersion - 1
    ), connectionID: connection.id)

    let effective = try repository.effectiveEvidence(for: .hostedImageGeneration, connection: connection)

    #expect(effective?.status == .expired)
    #expect(repository.loadAll().first?.evidence.first?.status == .verified)
}

@Test func capabilityEvidenceCanBeInvalidatedWithoutDeletingOtherConnections() throws {
    let settings = CapabilityEvidenceSettingsStore()
    let credentials = CapabilityEvidenceCredentialStore()
    let repository = AppProviderCapabilityEvidenceRepository(settingsStore: settings, credentialStore: credentials)
    try repository.save(AppProviderCapabilitySnapshot(connectionID: "a", evidence: []))
    try repository.save(AppProviderCapabilitySnapshot(connectionID: "b", evidence: []))

    try repository.invalidate(connectionID: "a")

    #expect(repository.loadAll().map(\.connectionID).sorted() == ["a", "b"])
    #expect(repository.loadAll().first { $0.connectionID == "a" }?.evidence.isEmpty == true)
}
