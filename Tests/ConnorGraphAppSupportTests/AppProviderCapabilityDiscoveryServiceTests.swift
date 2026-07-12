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

@Test func setupValidationPolicyIsDrivenByProviderMode() {
    let compatible = AppLLMConnectionConfig(id: "compatible", name: "Compatible", providerMode: .openAICompatible, baseURLString: "https://example.com/v1", model: "model-a")
    let responses = AppLLMConnectionConfig(id: "responses", name: "Responses", providerMode: .openAIResponses, baseURLString: "https://example.com/v1", model: "model-a")
    let anthropic = AppLLMConnectionConfig(id: "anthropic", name: "Anthropic", providerMode: .anthropicMessages, baseURLString: "https://example.com/v1", model: "model-a")

    #expect(AppProviderCapabilityValidationPolicy.forConnection(compatible) == .init(
        protocolCapabilities: [.chatCompletions, .functionCalling, .responses],
        probesHostedImageGenerationWhenResponsesVerified: true
    ))
    #expect(AppProviderCapabilityValidationPolicy.forConnection(responses) == .init(
        protocolCapabilities: [.responses],
        probesHostedImageGenerationWhenResponsesVerified: true
    ))
    #expect(AppProviderCapabilityValidationPolicy.forConnection(anthropic) == .init(
        protocolCapabilities: [],
        probesHostedImageGenerationWhenResponsesVerified: false
    ))
}

@Test func setupValidationPolicyDoesNotInferFromModelOrHost() {
    let misleading = AppLLMConnectionConfig(
        id: "anthropic",
        name: "Anthropic",
        providerMode: .anthropicMessages,
        baseURLString: "https://api.openai.com/v1",
        model: "gpt-5.6"
    )

    let policy = AppProviderCapabilityValidationPolicy.forConnection(misleading)

    #expect(policy.protocolCapabilities.isEmpty)
    #expect(policy.probesHostedImageGenerationWhenResponsesVerified == false)
}

@Test func draftProbeDoesNotPersistUntilExplicitlyRequested() async throws {
    let (settings, evidence, connection) = try discoveryRepositories()
    try evidence.invalidate(connectionID: connection.id)
    let service = AppProviderCapabilityDiscoveryService(
        settingsRepository: settings,
        evidenceRepository: evidence,
        openAICompatibleProbe: { config in LLMProviderHealthCheckResult(ok: true, model: config.model, message: "OK") },
        openAIResponsesProbe: { config in LLMProviderHealthCheckResult(ok: true, model: config.model, message: "OK") },
        functionCallingProbe: { _ in AgentModelResponse(text: "OK") }
    )

    let result = await service.probeProtocolCapabilities(context: AppProviderCapabilityProbeContext(connection: connection, credential: "secret"))

    #expect(result.connectionID == connection.id)
    #expect(result.evidence.count == 3)
    #expect(evidence.loadAll().first?.evidence.isEmpty == true)

    service.persist(result)
    #expect(evidence.loadAll().first?.evidence.count == 3)
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

@Test func capabilityDiagnosticExcludesSecretsAndContent() throws {
    let connection = AppLLMConnectionConfig(id: "relay", name: "Relay", providerMode: .openAICompatible, baseURLString: "https://user:password@example.com/v1?api_key=secret", model: "model-a")
    let evidence = AppProviderCapabilityEvidence(capability: .responses, status: .verified, verifiedAt: Date(timeIntervalSince1970: 100), endpointFamily: "openai_responses", modelID: "model-a", bindingFingerprint: "fingerprint", sanitizedDiagnostic: "HTTP 200")

    let diagnostic = AppProviderCapabilityDiagnostic(connection: connection, evidence: evidence, now: Date(timeIntervalSince1970: 130))
    let rendered = String(describing: diagnostic)

    #expect(diagnostic.host == "example.com")
    #expect(diagnostic.evidenceAgeSeconds == 30)
    #expect(rendered.contains("password") == false)
    #expect(rendered.contains("api_key") == false)
    #expect(rendered.contains("secret") == false)
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
