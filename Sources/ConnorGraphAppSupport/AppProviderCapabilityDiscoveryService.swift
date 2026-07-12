import Foundation
import ConnorGraphAgent

public enum AppProviderCapabilityProbeOutcome: Sendable, Equatable {
    case verified(String)
    case unsupported(String)
    case unknown(String)
}

public struct AppProviderCapabilityDiscoveryResult: Sendable, Equatable {
    public var connectionID: String
    public var evidence: [AppProviderCapabilityEvidence]

    public init(connectionID: String, evidence: [AppProviderCapabilityEvidence]) {
        self.connectionID = connectionID
        self.evidence = evidence
    }
}

public typealias AppOpenAICompatibleProbe = @Sendable (OpenAICompatibleConfig) async throws -> LLMProviderHealthCheckResult
public typealias AppOpenAIResponsesProbe = @Sendable (OpenAIResponsesConfig) async throws -> LLMProviderHealthCheckResult
public typealias AppFunctionCallingProbe = @Sendable (OpenAICompatibleConfig) async throws -> AgentModelResponse

public struct AppProviderCapabilityDiscoveryService: Sendable {
    public var settingsRepository: AppLLMSettingsRepository
    public var evidenceRepository: AppProviderCapabilityEvidenceRepository
    public var openAICompatibleProbe: AppOpenAICompatibleProbe
    public var openAIResponsesProbe: AppOpenAIResponsesProbe
    public var functionCallingProbe: AppFunctionCallingProbe

    public init(
        settingsRepository: AppLLMSettingsRepository = AppLLMSettingsRepository(),
        evidenceRepository: AppProviderCapabilityEvidenceRepository = AppProviderCapabilityEvidenceRepository(),
        openAICompatibleProbe: @escaping AppOpenAICompatibleProbe = { try await OpenAICompatibleProvider(config: $0).healthCheck() },
        openAIResponsesProbe: @escaping AppOpenAIResponsesProbe = { try await OpenAIResponsesProvider(config: $0).healthCheck() },
        functionCallingProbe: @escaping AppFunctionCallingProbe = { config in
            try await OpenAICompatibleProvider(config: config).completeWithTools(AgentModelRequest(
                messages: [AgentModelMessage(role: .user, content: "Reply briefly without calling tools.")],
                tools: [AgentToolDefinition(
                    name: "capability_probe",
                    description: "A no-op capability probe.",
                    inputSchema: .closedObject(properties: ["value": .string(description: "Optional value")], required: [])
                )]
            ))
        }
    ) {
        self.settingsRepository = settingsRepository
        self.evidenceRepository = evidenceRepository
        self.openAICompatibleProbe = openAICompatibleProbe
        self.openAIResponsesProbe = openAIResponsesProbe
        self.functionCallingProbe = functionCallingProbe
    }

    public func discoverProtocolCapabilities(connectionID: String) async -> AppProviderCapabilityDiscoveryResult {
        guard let settings = try? settingsRepository.loadSettings(),
              let connection = settings.connection(id: connectionID),
              let credential = (try? settingsRepository.apiKey(for: connection.id)) ?? nil,
              !credential.isEmpty
        else { return AppProviderCapabilityDiscoveryResult(connectionID: connectionID, evidence: []) }
        let binding = AppProviderCapabilityEvidenceRepository.bindingFingerprint(connection: connection, credential: credential)
        var discovered: [AppProviderCapabilityEvidence] = []

        switch connection.providerMode {
        case .openAICompatible:
            if let config = try? settingsRepository.openAICompatibleConfig(connectionID: connection.id) {
                discovered.append(await evidence(.chatCompletions, family: "chat_completions", connection: connection, binding: binding) {
                    _ = try await openAICompatibleProbe(config)
                })
                discovered.append(await evidence(.functionCalling, family: "chat_completions", connection: connection, binding: binding) {
                    _ = try await functionCallingProbe(config)
                })
                if let url = URL(string: connection.baseURLString) {
                    let responses = OpenAIResponsesConfig(baseURL: url, apiKey: config.apiKey, model: connection.effectiveModel, extraHeaders: config.extraHeaders, apiKeyHeaderKind: config.apiKeyHeaderKind, requestTimeout: config.requestTimeout, explicitVisionSupport: connection.explicitVisionSupport)
                    discovered.append(await evidence(.responses, family: "openai_responses", connection: connection, binding: binding) {
                        _ = try await openAIResponsesProbe(responses)
                    })
                }
            }
        case .openAIResponses:
            if let config = try? settingsRepository.openAIResponsesConfig(connectionID: connection.id) {
                discovered.append(await evidence(.responses, family: "openai_responses", connection: connection, binding: binding) {
                    _ = try await openAIResponsesProbe(config)
                })
            }
        case .anthropicMessages:
            break
        }
        for item in discovered { try? evidenceRepository.replaceEvidence(item, connectionID: connection.id) }
        return AppProviderCapabilityDiscoveryResult(connectionID: connection.id, evidence: discovered)
    }

    private func evidence(
        _ capability: AppProviderCapabilityID,
        family: String,
        connection: AppLLMConnectionConfig,
        binding: String,
        operation: () async throws -> Void
    ) async -> AppProviderCapabilityEvidence {
        let outcome: AppProviderCapabilityProbeOutcome
        do {
            try await operation()
            outcome = .verified("Verified")
        } catch {
            outcome = Self.classify(error)
        }
        let status: AppProviderCapabilityStatus
        let diagnostic: String
        switch outcome {
        case .verified(let message): status = .verified; diagnostic = message
        case .unsupported(let message): status = .unsupported; diagnostic = message
        case .unknown(let message): status = .unknown; diagnostic = message
        }
        return AppProviderCapabilityEvidence(capability: capability, status: status, endpointFamily: family, modelID: connection.effectiveModel, bindingFingerprint: binding, sanitizedDiagnostic: diagnostic)
    }

    public static func classify(_ error: Error) -> AppProviderCapabilityProbeOutcome {
        if let providerError = error as? OpenAICompatibleProviderError,
           case let .httpStatus(code, message) = providerError {
            let safe = String((message ?? "HTTP \(code)").prefix(500))
            switch code {
            case 404, 405, 410: return .unsupported(safe)
            case 429, 500...599: return .unknown(safe)
            case 401, 403: return .unknown(safe)
            case 400, 422:
                let lower = safe.lowercased()
                if lower.contains("unsupported") || lower.contains("not support") || lower.contains("unknown endpoint") || lower.contains("unknown tool") { return .unsupported(safe) }
                return .unknown(safe)
            default: return .unknown(safe)
            }
        }
        if error is URLError { return .unknown("Network request did not complete") }
        return .unknown(String(String(describing: error).prefix(500)))
    }
}
