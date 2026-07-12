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

/// An in-memory capability probe target. The credential is never persisted by the
/// discovery service and must not be included in diagnostics.
public struct AppProviderCapabilityProbeContext: Sendable, Equatable {
    public var connection: AppLLMConnectionConfig
    public var credential: String

    public init(connection: AppLLMConnectionConfig, credential: String) {
        self.connection = connection
        self.credential = credential
    }
}

public typealias AppOpenAICompatibleProbe = @Sendable (OpenAICompatibleConfig) async throws -> LLMProviderHealthCheckResult
public typealias AppOpenAIResponsesProbe = @Sendable (OpenAIResponsesConfig) async throws -> LLMProviderHealthCheckResult
public typealias AppFunctionCallingProbe = @Sendable (OpenAICompatibleConfig) async throws -> AgentModelResponse
public typealias AppHostedImageGenerationProbe = @Sendable (OpenAIResponsesConfig) async throws -> Bool

public enum AppHostedImageGenerationProbeAuthorization: Sendable, Equatable {
    case userInitiated
}

public struct AppProviderCapabilityValidationPolicy: Sendable, Equatable {
    public var protocolCapabilities: [AppProviderCapabilityID]
    public var probesHostedImageGenerationWhenResponsesVerified: Bool

    public init(
        protocolCapabilities: [AppProviderCapabilityID],
        probesHostedImageGenerationWhenResponsesVerified: Bool
    ) {
        self.protocolCapabilities = protocolCapabilities
        self.probesHostedImageGenerationWhenResponsesVerified = probesHostedImageGenerationWhenResponsesVerified
    }

    public static func forConnection(_ connection: AppLLMConnectionConfig) -> Self {
        switch connection.providerMode {
        case .openAICompatible:
            return Self(
                protocolCapabilities: [.chatCompletions, .functionCalling, .responses],
                probesHostedImageGenerationWhenResponsesVerified: true
            )
        case .openAIResponses:
            return Self(
                protocolCapabilities: [.responses],
                probesHostedImageGenerationWhenResponsesVerified: true
            )
        case .anthropicMessages:
            return Self(protocolCapabilities: [], probesHostedImageGenerationWhenResponsesVerified: false)
        }
    }
}

public struct AppProviderCapabilityDiscoveryService: Sendable {
    public var settingsRepository: AppLLMSettingsRepository
    public var evidenceRepository: AppProviderCapabilityEvidenceRepository
    public var openAICompatibleProbe: AppOpenAICompatibleProbe
    public var openAIResponsesProbe: AppOpenAIResponsesProbe
    public var functionCallingProbe: AppFunctionCallingProbe
    public var hostedImageGenerationProbe: AppHostedImageGenerationProbe

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
        },
        hostedImageGenerationProbe: @escaping AppHostedImageGenerationProbe = { config in
            let provider = OpenAIResponsesProvider(config: config)
            for try await event in provider.generateMedia(AgentGeneratedMediaRequest(
                kind: .image,
                prompt: "Create a minimal solid blue square on a plain white background."
            )) {
                if case .completed(let artifact) = event {
                    defer { try? FileManager.default.removeItem(at: artifact.temporaryFileURL) }
                    return artifact.byteCount > 0
                }
            }
            return false
        }
    ) {
        self.settingsRepository = settingsRepository
        self.evidenceRepository = evidenceRepository
        self.openAICompatibleProbe = openAICompatibleProbe
        self.openAIResponsesProbe = openAIResponsesProbe
        self.functionCallingProbe = functionCallingProbe
        self.hostedImageGenerationProbe = hostedImageGenerationProbe
    }

    public func discoverHostedImageGeneration(
        connectionID: String,
        authorization: AppHostedImageGenerationProbeAuthorization
    ) async -> AppProviderCapabilityEvidence? {
        guard authorization == .userInitiated,
              let settings = try? settingsRepository.loadSettings(),
              let connection = settings.connection(id: connectionID),
              let credential = (try? settingsRepository.apiKey(for: connection.id)) ?? nil,
              !credential.isEmpty,
              let baseURL = URL(string: connection.baseURLString)
        else { return nil }
        let existingResponses = try? evidenceRepository.effectiveEvidence(for: .responses, connection: connection)
        guard existingResponses?.status == .verified else { return nil }
        let apiKeyHeaderKind = OpenAICompatibleAPIKeyHeaderKind(rawValue: connection.extraHTTPHeaders[AppLLMSettingsRepository.openAIAPIKeyHeaderKindMetadataKey] ?? "") ?? .bearer
        var headers = connection.extraHTTPHeaders
        headers.removeValue(forKey: AppLLMSettingsRepository.openAIAPIKeyHeaderKindMetadataKey)
        let config = OpenAIResponsesConfig(baseURL: baseURL, apiKey: credential, model: connection.effectiveModel, extraHeaders: headers, apiKeyHeaderKind: apiKeyHeaderKind)
        let binding = AppProviderCapabilityEvidenceRepository.bindingFingerprint(connection: connection, credential: credential)
        let evidence = await evidence(.hostedImageGeneration, family: "openai_responses", connection: connection, binding: binding) {
            guard try await hostedImageGenerationProbe(config) else {
                throw OpenAICompatibleProviderError.invalidResponse
            }
        }
        try? evidenceRepository.replaceEvidence(evidence, connectionID: connection.id)
        return evidence
    }

    public func discoverProtocolCapabilities(connectionID: String) async -> AppProviderCapabilityDiscoveryResult {
        guard let settings = try? settingsRepository.loadSettings(),
              let connection = settings.connection(id: connectionID),
              let credential = (try? settingsRepository.apiKey(for: connection.id)) ?? nil,
              !credential.isEmpty
        else { return AppProviderCapabilityDiscoveryResult(connectionID: connectionID, evidence: []) }
        let result = await probeProtocolCapabilities(context: AppProviderCapabilityProbeContext(connection: connection, credential: credential))
        persist(result)
        return result
    }

    /// Probes a draft or persisted connection without writing settings, credentials,
    /// or capability evidence. Call `persist(_:)` only after the connection itself
    /// has been saved successfully.
    public func probeProtocolCapabilities(context: AppProviderCapabilityProbeContext) async -> AppProviderCapabilityDiscoveryResult {
        let connection = context.connection
        let credential = context.credential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !credential.isEmpty, let baseURL = URL(string: connection.baseURLString) else {
            return AppProviderCapabilityDiscoveryResult(connectionID: connection.id, evidence: [])
        }
        let binding = AppProviderCapabilityEvidenceRepository.bindingFingerprint(connection: connection, credential: credential)
        let apiKeyHeaderKind = OpenAICompatibleAPIKeyHeaderKind(rawValue: connection.extraHTTPHeaders[AppLLMSettingsRepository.openAIAPIKeyHeaderKindMetadataKey] ?? "") ?? .bearer
        var headers = connection.extraHTTPHeaders
        headers.removeValue(forKey: AppLLMSettingsRepository.openAIAPIKeyHeaderKindMetadataKey)
        var discovered: [AppProviderCapabilityEvidence] = []
        let policy = AppProviderCapabilityValidationPolicy.forConnection(connection)

        switch connection.providerMode {
        case .openAICompatible:
            let config = OpenAICompatibleConfig(baseURL: baseURL, apiKey: credential, model: connection.effectiveModel, extraHeaders: headers, apiKeyHeaderKind: apiKeyHeaderKind)
            if policy.protocolCapabilities.contains(.chatCompletions) {
                discovered.append(await evidence(.chatCompletions, family: "chat_completions", connection: connection, binding: binding) {
                    _ = try await openAICompatibleProbe(config)
                })
            }
            if policy.protocolCapabilities.contains(.functionCalling) {
                discovered.append(await evidence(.functionCalling, family: "chat_completions", connection: connection, binding: binding) {
                    _ = try await functionCallingProbe(config)
                })
            }
            let responses = OpenAIResponsesConfig(baseURL: baseURL, apiKey: credential, model: connection.effectiveModel, extraHeaders: headers, apiKeyHeaderKind: apiKeyHeaderKind)
            if policy.protocolCapabilities.contains(.responses) {
                discovered.append(await evidence(.responses, family: "openai_responses", connection: connection, binding: binding) {
                    _ = try await openAIResponsesProbe(responses)
                })
            }
        case .openAIResponses:
            let config = OpenAIResponsesConfig(baseURL: baseURL, apiKey: credential, model: connection.effectiveModel, extraHeaders: headers, apiKeyHeaderKind: apiKeyHeaderKind)
            if policy.protocolCapabilities.contains(.responses) {
                discovered.append(await evidence(.responses, family: "openai_responses", connection: connection, binding: binding) {
                    _ = try await openAIResponsesProbe(config)
                })
            }
        case .anthropicMessages:
            break
        }
        return AppProviderCapabilityDiscoveryResult(connectionID: connection.id, evidence: discovered)
    }

    public func persist(_ result: AppProviderCapabilityDiscoveryResult) {
        for item in result.evidence {
            try? evidenceRepository.replaceEvidence(item, connectionID: result.connectionID)
        }
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
