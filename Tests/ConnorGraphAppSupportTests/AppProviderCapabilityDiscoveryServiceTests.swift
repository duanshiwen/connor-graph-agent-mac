import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport

private final class DiscoverySettingsStore: LLMSettingsStore, @unchecked Sendable {
    var values: [String: String] = [:]
    func string(forKey key: String) -> String? { values[key] }
    func set(_ value: String, forKey key: String) { values[key] = value }
}
private final class DiscoveryCredentialStore: CredentialStore, @unchecked Sendable {
    var values: [String: String] = [:]
    func saveSecret(_ secret: String, service: String, account: String) throws { values["\(service):\(account)"] = secret }
    func readSecret(service: String, account: String) throws -> String? { values["\(service):\(account)"] }
    func deleteSecret(service: String, account: String) throws { values.removeValue(forKey: "\(service):\(account)") }
}

private func discoveryRepositories() throws -> (AppLLMSettingsRepository, AppProviderCapabilityEvidenceRepository, AppLLMConnectionConfig) {
    let store = DiscoverySettingsStore(), credentials = DiscoveryCredentialStore()
    let connection = AppLLMConnectionConfig(id: "compatible", name: "Compatible", providerMode: .openAICompatible, baseURLString: "https://example.com/v1", model: "model-a", selectedModel: "model-a")
    let settings = AppLLMSettingsRepository(settingsStore: store, credentialStore: credentials)
    try settings.save(settings: AppLLMSettings(connections: [connection], defaultConnectionID: connection.id), apiKey: "secret")
    return (settings, AppProviderCapabilityEvidenceRepository(settingsStore: store, credentialStore: credentials), connection)
}

@Test func discoveryVerifiesChatFunctionsAndResponsesForCompatibleConnection() async throws {
    let (settings, evidence, connection) = try discoveryRepositories()
    let service = AppProviderCapabilityDiscoveryService(
        settingsRepository: settings,
        evidenceRepository: evidence,
        openAICompatibleProbe: { config in LLMProviderHealthCheckResult(ok: true, model: config.model, message: "OK") },
        openAIResponsesProbe: { config in LLMProviderHealthCheckResult(ok: true, model: config.model, message: "OK") },
        functionCallingProbe: { _ in AgentModelResponse(text: "OK") }
    )

    let result = await service.discoverProtocolCapabilities(connectionID: connection.id)

    #expect(result.evidence.first { $0.capability == .chatCompletions }?.status == .verified)
    #expect(result.evidence.first { $0.capability == .functionCalling }?.status == .verified)
    #expect(result.evidence.first { $0.capability == .responses }?.status == .verified)
    #expect(try evidence.effectiveEvidence(for: .responses, connection: connection)?.status == .verified)
}

@Test func discoveryClassifiesPermanentAndTransientFailures() {
    let unsupported = AppProviderCapabilityDiscoveryService.classify(OpenAICompatibleProviderError.httpStatus(404, message: "not found"))
    let explicitUnsupported = AppProviderCapabilityDiscoveryService.classify(OpenAICompatibleProviderError.httpStatus(400, message: "unsupported endpoint"))
    let unauthorized = AppProviderCapabilityDiscoveryService.classify(OpenAICompatibleProviderError.httpStatus(401, message: "bad key"))
    let limited = AppProviderCapabilityDiscoveryService.classify(OpenAICompatibleProviderError.httpStatus(429, message: "rate limited"))
    let unavailable = AppProviderCapabilityDiscoveryService.classify(OpenAICompatibleProviderError.httpStatus(503, message: "upstream unavailable"))
    let timeout = AppProviderCapabilityDiscoveryService.classify(URLError(.timedOut))

    #expect(unsupported == .unsupported("not found"))
    #expect(explicitUnsupported == .unsupported("unsupported endpoint"))
    #expect(unauthorized == .unknown("bad key"))
    #expect(limited == .unknown("rate limited"))
    #expect(unavailable == .unknown("upstream unavailable"))
    #expect(timeout == .unknown("Network request did not complete"))
}

@Test func hostedImageDiscoveryRequiresVerifiedResponsesAndUserAuthorization() async throws {
    let (settings, evidence, connection) = try discoveryRepositories()
    let serviceWithoutResponses = AppProviderCapabilityDiscoveryService(
        settingsRepository: settings,
        evidenceRepository: evidence,
        hostedImageGenerationProbe: { _ in Issue.record("Image probe must not run before Responses is verified"); return true }
    )
    #expect(await serviceWithoutResponses.discoverHostedImageGeneration(connectionID: connection.id, authorization: .userInitiated) == nil)

    let protocolService = AppProviderCapabilityDiscoveryService(
        settingsRepository: settings,
        evidenceRepository: evidence,
        openAICompatibleProbe: { config in LLMProviderHealthCheckResult(ok: true, model: config.model, message: "OK") },
        openAIResponsesProbe: { config in LLMProviderHealthCheckResult(ok: true, model: config.model, message: "OK") },
        functionCallingProbe: { _ in AgentModelResponse(text: "OK") }
    )
    _ = await protocolService.discoverProtocolCapabilities(connectionID: connection.id)
    let imageService = AppProviderCapabilityDiscoveryService(
        settingsRepository: settings,
        evidenceRepository: evidence,
        hostedImageGenerationProbe: { config in
            #expect(config.model == "model-a")
            return true
        }
    )

    let result = await imageService.discoverHostedImageGeneration(connectionID: connection.id, authorization: .userInitiated)

    #expect(result?.status == .verified)
    #expect(try evidence.effectiveEvidence(for: .hostedImageGeneration, connection: connection)?.status == .verified)
}

@Test func hostedImageDiscoveryClassifiesExplicitUnsupportedFailure() async throws {
    let (settings, evidence, connection) = try discoveryRepositories()
    let protocolService = AppProviderCapabilityDiscoveryService(
        settingsRepository: settings,
        evidenceRepository: evidence,
        openAICompatibleProbe: { config in LLMProviderHealthCheckResult(ok: true, model: config.model, message: "OK") },
        openAIResponsesProbe: { config in LLMProviderHealthCheckResult(ok: true, model: config.model, message: "OK") },
        functionCallingProbe: { _ in AgentModelResponse(text: "OK") }
    )
    _ = await protocolService.discoverProtocolCapabilities(connectionID: connection.id)
    let imageService = AppProviderCapabilityDiscoveryService(
        settingsRepository: settings,
        evidenceRepository: evidence,
        hostedImageGenerationProbe: { _ in throw OpenAICompatibleProviderError.httpStatus(400, message: "unsupported tool image_generation") }
    )

    let result = await imageService.discoverHostedImageGeneration(connectionID: connection.id, authorization: .userInitiated)

    #expect(result?.status == .unsupported)
}

@Test func discoveryKeepsResponsesUnknownWhenServiceIsTemporarilyUnavailable() async throws {
    let (settings, evidence, connection) = try discoveryRepositories()
    let service = AppProviderCapabilityDiscoveryService(
        settingsRepository: settings,
        evidenceRepository: evidence,
        openAICompatibleProbe: { config in LLMProviderHealthCheckResult(ok: true, model: config.model, message: "OK") },
        openAIResponsesProbe: { _ in throw OpenAICompatibleProviderError.httpStatus(503, message: "upstream unavailable") },
        functionCallingProbe: { _ in AgentModelResponse(text: "OK") }
    )

    let result = await service.discoverProtocolCapabilities(connectionID: connection.id)

    #expect(result.evidence.first { $0.capability == .responses }?.status == .unknown)
}
