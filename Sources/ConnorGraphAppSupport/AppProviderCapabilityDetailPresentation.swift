import Foundation

public struct AppProviderCapabilityDetailPresentation: Sendable, Equatable, Identifiable {
    public var connectionID: String
    public var connectionName: String
    public var providerName: String
    public var endpoint: String
    public var modelID: String
    public var capabilities: [AppProviderCapabilityRowPresentation]

    public var id: String { connectionID }
    public var hasSnapshot: Bool { !capabilities.isEmpty }

    public init(
        connectionID: String,
        connectionName: String,
        providerName: String,
        endpoint: String,
        modelID: String,
        capabilities: [AppProviderCapabilityRowPresentation]
    ) {
        self.connectionID = connectionID
        self.connectionName = connectionName
        self.providerName = providerName
        self.endpoint = endpoint
        self.modelID = modelID
        self.capabilities = capabilities
    }
}

public struct AppProviderCapabilityRowPresentation: Sendable, Equatable, Identifiable {
    public var capability: AppProviderCapabilityID
    public var title: String
    public var status: AppProviderCapabilityStatus
    public var statusTitle: String
    public var apiFamily: String
    public var modelID: String
    public var verifiedAt: Date
    public var note: String?

    public var id: String { capability.rawValue }

    public init(
        capability: AppProviderCapabilityID,
        title: String,
        status: AppProviderCapabilityStatus,
        statusTitle: String,
        apiFamily: String,
        modelID: String,
        verifiedAt: Date,
        note: String?
    ) {
        self.capability = capability
        self.title = title
        self.status = status
        self.statusTitle = statusTitle
        self.apiFamily = apiFamily
        self.modelID = modelID
        self.verifiedAt = verifiedAt
        self.note = note
    }
}

public extension AppProviderCapabilityEvidenceRepository {
    func detailPresentation(for connection: AppLLMConnectionConfig) -> AppProviderCapabilityDetailPresentation {
        let snapshot = loadAll().first { $0.connectionID == connection.id }
        let rows = (snapshot?.evidence ?? [])
            .sorted { Self.capabilityOrder($0.capability) < Self.capabilityOrder($1.capability) }
            .map { stored in
                let effective = (try? effectiveEvidence(for: stored.capability, connection: connection)) ?? stored
                return AppProviderCapabilityRowPresentation(
                    capability: stored.capability,
                    title: Self.capabilityTitle(stored.capability),
                    status: effective.status,
                    statusTitle: Self.statusTitle(effective.status),
                    apiFamily: Self.apiFamilyTitle(stored.endpointFamily),
                    modelID: stored.modelID,
                    verifiedAt: stored.verifiedAt,
                    note: Self.safeNote(stored.sanitizedDiagnostic)
                )
            }
        return AppProviderCapabilityDetailPresentation(
            connectionID: connection.id,
            connectionName: connection.name,
            providerName: Self.providerTitle(connection.providerMode),
            endpoint: Self.safeEndpoint(connection.baseURLString),
            modelID: connection.effectiveModel,
            capabilities: rows
        )
    }

    private static func capabilityOrder(_ capability: AppProviderCapabilityID) -> Int {
        switch capability {
        case .chatCompletions: 0
        case .functionCalling: 1
        case .responses: 2
        case .hostedImageGeneration: 3
        }
    }

    private static func capabilityTitle(_ capability: AppProviderCapabilityID) -> String {
        switch capability {
        case .chatCompletions: "Chat Completions"
        case .functionCalling: "Function Calling"
        case .responses: "OpenAI Responses"
        case .hostedImageGeneration: "托管图片生成"
        }
    }

    private static func statusTitle(_ status: AppProviderCapabilityStatus) -> String {
        switch status {
        case .verified: "已验证支持"
        case .unsupported: "不支持"
        case .unknown: "未能确认"
        case .expired: "证据已失效"
        }
    }

    private static func apiFamilyTitle(_ family: String) -> String {
        switch family {
        case "openai_chat_completions": "OpenAI Chat Completions"
        case "openai_responses": "OpenAI Responses"
        case "anthropic_messages": "Anthropic Messages"
        default: "提供商 API"
        }
    }

    private static func providerTitle(_ mode: AppLLMProviderMode) -> String {
        switch mode {
        case .openAICompatible: "OpenAI Compatible"
        case .openAIResponses: "OpenAI Responses"
        case .anthropicMessages: "Anthropic Messages"
        }
    }

    private static func safeEndpoint(_ raw: String) -> String {
        guard var components = URLComponents(string: raw) else { return "无效地址" }
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        return components.string ?? "无效地址"
    }

    private static func safeNote(_ note: String?) -> String? {
        guard let note else { return nil }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.localizedCaseInsensitiveContains("authorization"),
              !trimmed.localizedCaseInsensitiveContains("api key"),
              !trimmed.localizedCaseInsensitiveContains("api-key"),
              !trimmed.localizedCaseInsensitiveContains("bearer ")
        else { return nil }
        return String(trimmed.prefix(200))
    }
}
