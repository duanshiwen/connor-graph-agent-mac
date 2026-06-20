import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport

private final class HealthCheckFakeCredentialStore: CredentialStore, @unchecked Sendable {
    var secrets: [String: String] = [:]

    func saveSecret(_ secret: String, service: String, account: String) throws {
        secrets["\(service):\(account)"] = secret
    }

    func readSecret(service: String, account: String) throws -> String? {
        secrets["\(service):\(account)"]
    }

    func deleteSecret(service: String, account: String) throws {
        secrets.removeValue(forKey: "\(service):\(account)")
    }
}

private final class HealthCheckFakeSettingsStore: LLMSettingsStore, @unchecked Sendable {
    var values: [String: String] = [:]

    func string(forKey key: String) -> String? { values[key] }
    func set(_ value: String, forKey key: String) { values[key] = value }
}

@Test func healthCheckerReportsDefaultOpenAIResponsesProviderNeedsConfiguration() async throws {
    let settingsRepository = AppLLMSettingsRepository(
        settingsStore: HealthCheckFakeSettingsStore(),
        credentialStore: HealthCheckFakeCredentialStore()
    )
    let checker = AppLLMProviderHealthChecker(settingsRepository: settingsRepository)

    let result = await checker.testConnection()

    #expect(result.status == .notConfigured)
    #expect(result.message.contains("API Key"))
}

@Test func healthCheckerReportsMissingOpenAICompatibleConfig() async throws {
    let settingsRepository = AppLLMSettingsRepository(
        settingsStore: HealthCheckFakeSettingsStore(),
        credentialStore: HealthCheckFakeCredentialStore()
    )
    try settingsRepository.save(
        settings: AppLLMSettings(baseURLString: "https://example.com/v1", model: "model-a", hasAPIKey: false, providerMode: .openAICompatible),
        apiKey: nil
    )
    let checker = AppLLMProviderHealthChecker(settingsRepository: settingsRepository)

    let result = await checker.testConnection()

    #expect(result.status == .notConfigured)
    #expect(result.message.contains("API Key"))
}

@Test func healthCheckerReportsOpenAICompatibleSuccess() async throws {
    let settingsRepository = AppLLMSettingsRepository(
        settingsStore: HealthCheckFakeSettingsStore(),
        credentialStore: HealthCheckFakeCredentialStore()
    )
    try settingsRepository.save(
        settings: AppLLMSettings(baseURLString: "https://example.com/v1", model: "model-a", hasAPIKey: false, providerMode: .openAICompatible),
        apiKey: "secret-key"
    )
    let checker = AppLLMProviderHealthChecker(
        settingsRepository: settingsRepository,
        openAICompatibleHealthCheck: { config in
            #expect(config.apiKey == "secret-key")
            return LLMProviderHealthCheckResult(ok: true, model: config.model, message: "Connection OK: \(config.model)")
        }
    )

    let result = await checker.testConnection()

    #expect(result.status == .success)
    #expect(result.message == "Connection OK: model-a")
}

@Test func healthCheckerMapsProviderErrorToFailureMessageWithoutSecret() async throws {
    let settingsRepository = AppLLMSettingsRepository(
        settingsStore: HealthCheckFakeSettingsStore(),
        credentialStore: HealthCheckFakeCredentialStore()
    )
    try settingsRepository.save(
        settings: AppLLMSettings(baseURLString: "https://example.com/v1", model: "model-a", hasAPIKey: false, providerMode: .openAICompatible),
        apiKey: "secret-key"
    )
    let checker = AppLLMProviderHealthChecker(
        settingsRepository: settingsRepository,
        openAICompatibleHealthCheck: { _ in
            throw OpenAICompatibleProviderError.httpStatus(401)
        }
    )

    let result = await checker.testConnection()

    #expect(result.status == .failed)
    #expect(result.message.contains("401"))
    #expect(result.message.contains("secret-key") == false)
}
