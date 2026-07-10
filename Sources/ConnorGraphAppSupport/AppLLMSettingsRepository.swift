import Foundation
import ConnorGraphAgent

public enum AppLLMProviderMode: String, Sendable, Equatable, CaseIterable, Codable {
    case openAIResponses = "openai_responses"
    case openAICompatible = "openai_compatible"
    case anthropicMessages = "anthropic_messages"

    public var displayName: String {
        switch self {
        case .openAIResponses:
            return "OpenAI Responses"
        case .openAICompatible:
            return "OpenAI Compatible"
        case .anthropicMessages:
            return "Anthropic Messages"
        }
    }
}

public enum AppLLMConnectionKind: String, Sendable, Equatable, CaseIterable, Codable {
    case openAIResponses = "openai_responses"
    case openAICompatible = "openai_compatible"
    case chatGPTCodex = "chatgpt_codex"
    case githubCopilot = "github_copilot"
    case anthropicCompatible = "anthropic_compatible"

    public var displayName: String {
        switch self {
        case .openAIResponses: return "OpenAI Responses"
        case .openAICompatible: return "OpenAI Compatible"
        case .chatGPTCodex: return "Codex · ChatGPT"
        case .githubCopilot: return "GitHub Copilot"
        case .anthropicCompatible: return "Anthropic Compatible"
        }
    }
}

public enum AppLLMThinkingLevel: String, Sendable, Equatable, CaseIterable, Codable, Identifiable {
    case off
    case low
    case medium
    case high
    case xhigh
    case max

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .off: return "无思考"
        case .low: return "低"
        case .medium: return "中等"
        case .high: return "高"
        case .xhigh: return "超高"
        case .max: return "最大"
        }
    }

    public var description: String {
        switch self {
        case .off: return "最快的响应，无推理"
        case .low: return "轻量推理，更快的响应"
        case .medium: return "平衡的速度和推理"
        case .high: return "深度推理用于复杂任务"
        case .xhigh: return "适用于长周期代理任务的更深入推理"
        case .max: return "最大努力推理"
        }
    }

    public var effortValue: String? {
        switch self {
        case .off: return nil
        case .low: return "low"
        case .medium: return "medium"
        case .high: return "high"
        case .xhigh: return "xhigh"
        case .max: return "max"
        }
    }

    public var openAIReasoningEffort: String? {
        switch self {
        case .off: return nil
        case .low: return "low"
        case .medium: return "medium"
        case .high, .xhigh, .max: return "high"
        }
    }

    public var anthropicThinking: AnthropicThinkingConfig? {
        switch self {
        case .off: return nil
        case .low: return .enabled(budgetTokens: 4_000, display: .omitted)
        case .medium: return .enabled(budgetTokens: 10_000, display: .omitted)
        case .high: return .enabled(budgetTokens: 20_000, display: .omitted)
        case .xhigh: return .enabled(budgetTokens: 26_000, display: .omitted)
        case .max: return .enabled(budgetTokens: 32_000, display: .omitted)
        }
    }

    public static let defaultLevel: AppLLMThinkingLevel = .medium

    public static func normalized(_ rawValue: String?) -> AppLLMThinkingLevel? {
        guard let rawValue else { return nil }
        if rawValue == "think" { return .medium }
        return AppLLMThinkingLevel(rawValue: rawValue)
    }
}

public struct AppLLMConnectionConfig: Sendable, Identifiable, Equatable, Codable {
    public var id: String
    public var name: String
    public var providerMode: AppLLMProviderMode
    public var connectionKind: AppLLMConnectionKind
    public var baseURLString: String
    public var model: String
    public var selectedModel: String
    public var hasAPIKey: Bool
    public var extraHTTPHeaders: [String: String]
    /// Explicit override for vision support. When nil, capability is inferred from model name heuristics.
    public var explicitVisionSupport: Bool?

    private enum CodingKeys: String, CodingKey {
        case id, name, providerMode, connectionKind, baseURLString, model, selectedModel, hasAPIKey
        case extraHTTPHeaders
        case explicitVisionSupport
    }

    public init(
        id: String,
        name: String,
        providerMode: AppLLMProviderMode,
        connectionKind: AppLLMConnectionKind? = nil,
        baseURLString: String = "",
        model: String = "",
        selectedModel: String = "",
        hasAPIKey: Bool = false,
        extraHTTPHeaders: [String: String] = [:],
        explicitVisionSupport: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.providerMode = providerMode
        self.connectionKind = connectionKind ?? Self.defaultConnectionKind(for: providerMode)
        self.baseURLString = baseURLString
        self.model = model
        let normalizedSelectedModel = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        self.selectedModel = normalizedSelectedModel.isEmpty ? Self.firstModel(in: model) : normalizedSelectedModel
        self.hasAPIKey = hasAPIKey
        self.extraHTTPHeaders = extraHTTPHeaders
        self.explicitVisionSupport = explicitVisionSupport
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let providerMode = try container.decode(AppLLMProviderMode.self, forKey: .providerMode)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            providerMode: providerMode,
            connectionKind: try container.decodeIfPresent(AppLLMConnectionKind.self, forKey: .connectionKind),
            baseURLString: try container.decodeIfPresent(String.self, forKey: .baseURLString) ?? "",
            model: try container.decodeIfPresent(String.self, forKey: .model) ?? "",
            selectedModel: try container.decodeIfPresent(String.self, forKey: .selectedModel) ?? "",
            hasAPIKey: try container.decodeIfPresent(Bool.self, forKey: .hasAPIKey) ?? false,
            extraHTTPHeaders: try container.decodeIfPresent([String: String].self, forKey: .extraHTTPHeaders) ?? [:],
            explicitVisionSupport: try container.decodeIfPresent(Bool.self, forKey: .explicitVisionSupport)
        )
    }

    public var modelOptions: [String] { Self.modelOptions(in: model) }

    public var effectiveModel: String {
        let selected = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !selected.isEmpty { return selected }
        return Self.firstModel(in: model)
    }

    public static func modelOptions(in rawValue: String) -> [String] {
        rawValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public static func firstModel(in rawValue: String) -> String {
        modelOptions(in: rawValue).first ?? rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func defaultConnectionKind(for providerMode: AppLLMProviderMode) -> AppLLMConnectionKind {
        switch providerMode {
        case .openAIResponses:
            return .openAIResponses
        case .openAICompatible:
            return .openAICompatible
        case .anthropicMessages:
            return .anthropicCompatible
        }
    }

    public static let defaultOpenAIResponses = AppLLMConnectionConfig(
        id: "openai-responses",
        name: "OpenAI Responses",
        providerMode: .openAIResponses,
        connectionKind: .openAIResponses,
        baseURLString: "https://api.openai.com/v1",
        model: "gpt-4.1",
        selectedModel: "gpt-4.1"
    )

    public static let defaultOpenAICompatible = AppLLMConnectionConfig(
        id: "openai-compatible",
        name: "OpenAI Compatible",
        providerMode: .openAICompatible,
        baseURLString: "https://api.openai.com/v1",
        model: "gpt-4o-mini",
        selectedModel: "gpt-4o-mini"
    )
}

public struct AppLLMModelOption: Sendable, Identifiable, Equatable {
    public var id: String
    public var displayName: String

    public init(id: String, displayName: String? = nil) {
        self.id = id
        self.displayName = displayName ?? id
    }
}

public struct AppLLMModelConnection: Sendable, Identifiable, Equatable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var providerMode: AppLLMProviderMode
    public var models: [AppLLMModelOption]
    public var isLiveCatalog: Bool

    public init(
        id: String,
        title: String,
        subtitle: String,
        providerMode: AppLLMProviderMode,
        models: [AppLLMModelOption],
        isLiveCatalog: Bool
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.providerMode = providerMode
        self.models = models
        self.isLiveCatalog = isLiveCatalog
    }
}

public struct AppLLMSettings: Sendable, Equatable {
    public var connections: [AppLLMConnectionConfig]
    public var defaultConnectionID: String
    public var defaultThinkingLevel: AppLLMThinkingLevel

    public init(
        connections: [AppLLMConnectionConfig],
        defaultConnectionID: String,
        defaultThinkingLevel: AppLLMThinkingLevel = .defaultLevel
    ) {
        self.connections = connections
        self.defaultConnectionID = defaultConnectionID
        self.defaultThinkingLevel = defaultThinkingLevel
    }

    public init(
        baseURLString: String,
        model: String,
        selectedModel: String = "",
        hasAPIKey: Bool,
        providerMode: AppLLMProviderMode,
    ) {
        let id: String
        let name: String
        switch providerMode {
        case .openAIResponses:
            id = "openai-responses"
            name = "OpenAI Responses"
        case .openAICompatible:
            id = "openai-compatible"
            name = "OpenAI Compatible"
        case .anthropicMessages:
            id = "anthropic"
            name = "Claude"
        }
        let connection = AppLLMConnectionConfig(
            id: id,
            name: name,
            providerMode: providerMode,
            baseURLString: baseURLString,
            model: model,
            selectedModel: selectedModel,
            hasAPIKey: hasAPIKey,
        )
        self.init(connections: [connection], defaultConnectionID: id)
    }

    public var defaultConnection: AppLLMConnectionConfig? {
        connections.first(where: { $0.id == defaultConnectionID }) ?? connections.first
    }

    public var baseURLString: String { defaultConnection?.baseURLString ?? "" }
    public var model: String { defaultConnection?.model ?? "" }
    public var selectedModel: String { defaultConnection?.selectedModel ?? "" }
    public var effectiveModel: String { defaultConnection?.effectiveModel ?? "" }
    public var hasAPIKey: Bool { defaultConnection?.hasAPIKey ?? false }
    public var providerMode: AppLLMProviderMode { defaultConnection?.providerMode ?? .openAICompatible }
    public var modelOptions: [String] { defaultConnection?.modelOptions ?? [] }

    public func connection(id: String?) -> AppLLMConnectionConfig? {
        guard let id, !id.isEmpty else { return defaultConnection }
        return connections.first(where: { $0.id == id })
    }

    public var effectiveThinkingLevel: AppLLMThinkingLevel { defaultThinkingLevel }

    public static func modelOptions(in rawValue: String) -> [String] { AppLLMConnectionConfig.modelOptions(in: rawValue) }
    public static func firstModel(in rawValue: String) -> String { AppLLMConnectionConfig.firstModel(in: rawValue) }

    public static let `default` = AppLLMSettings(
        connections: [],
        defaultConnectionID: ""
    )
}

public protocol LLMSettingsStore: Sendable {
    func string(forKey key: String) -> String?
    func set(_ value: String, forKey key: String)
}

public final class UserDefaultsLLMSettingsStore: LLMSettingsStore, @unchecked Sendable {
    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func string(forKey key: String) -> String? {
        userDefaults.string(forKey: key)
    }

    public func set(_ value: String, forKey key: String) {
        userDefaults.set(value, forKey: key)
    }
}

public struct AppLLMSettingsRepository: @unchecked Sendable {
    public static let credentialNamespace = "ConnorGraphAgent"
    public static let apiKeyAccount = "openai-compatible-api-key"
    public static let anthropicAuthHeaderKindMetadataKey = "x-connor-anthropic-auth-header-kind"
    public static let openAIAPIKeyHeaderKindMetadataKey = "x-connor-openai-api-key-header-kind"

    private enum Keys {
        static let connections = "llm.connections"
        static let defaultConnectionID = "llm.defaultConnectionID"
        static let providerMode = "llm.providerMode"
        static let baseURLString = "llm.baseURLString"
        static let model = "llm.model"
        static let selectedModel = "llm.selectedModel"
        static let defaultThinkingLevel = "llm.defaultThinkingLevel"
    }

    public var settingsStore: LLMSettingsStore
    public var credentialStore: CredentialStore

    public init(
        settingsStore: LLMSettingsStore = UserDefaultsLLMSettingsStore(),
        credentialStore: CredentialStore = LocalEncryptedCredentialStore()
    ) {
        self.settingsStore = settingsStore
        self.credentialStore = credentialStore
    }

    public static func apiKeyAccount(for connectionID: String) -> String {
        "llm-connection-\(connectionID)-api-key"
    }

    public static func oauthAccount(for connectionID: String) -> String {
        "llm-connection-\(connectionID)-oauth"
    }

    /// CLI 环境专用的 settingsRepository，使用正确的 suite name 访问应用的 LLM 配置
    public static func cliRepository() -> AppLLMSettingsRepository {
        let appDomain = Bundle.main.bundleIdentifier ?? "com.shiwen.connor-graph-agent-mac"
        let suite = UserDefaults(suiteName: appDomain) ?? .standard
        let settingsStore = UserDefaultsLLMSettingsStore(userDefaults: suite)
        return AppLLMSettingsRepository(settingsStore: settingsStore)
    }

    public func loadSettings() throws -> AppLLMSettings {
        if let raw = settingsStore.string(forKey: Keys.connections), let data = raw.data(using: .utf8) {
            let decoded = try JSONDecoder().decode([AppLLMConnectionConfig].self, from: data)
            if decoded.isEmpty {
                return try loadLegacySettings()
            }
            let hydrated = try decoded.map { connection in
                var copy = connection
                copy.hasAPIKey = try hasAPIKey(for: connection.id)
                return copy
            }
            return AppLLMSettings(
                connections: hydrated,
                defaultConnectionID: settingsStore.string(forKey: Keys.defaultConnectionID) ?? hydrated.first?.id ?? "",
                defaultThinkingLevel: AppLLMThinkingLevel.normalized(settingsStore.string(forKey: Keys.defaultThinkingLevel)) ?? .defaultLevel
            )
        }
        return try loadLegacySettings()
    }

    private func loadLegacySettings() throws -> AppLLMSettings {
        let legacyProviderMode = settingsStore.string(forKey: Keys.providerMode)
        let legacyBaseURL = settingsStore.string(forKey: Keys.baseURLString)
        let legacyModel = settingsStore.string(forKey: Keys.model)
        let legacySelectedModel = settingsStore.string(forKey: Keys.selectedModel)
        let legacyAPIKey = try credentialStore.readSecret(service: Self.credentialNamespace, account: Self.apiKeyAccount)

        let hasLegacyConnectionShape =
            legacyProviderMode?.isEmpty == false ||
            legacyBaseURL?.isEmpty == false ||
            legacyModel?.isEmpty == false ||
            legacySelectedModel?.isEmpty == false ||
            legacyAPIKey?.isEmpty == false

        guard hasLegacyConnectionShape else {
            return AppLLMSettings(
                connections: [],
                defaultConnectionID: "",
                defaultThinkingLevel: AppLLMThinkingLevel.normalized(settingsStore.string(forKey: Keys.defaultThinkingLevel)) ?? .defaultLevel
            )
        }

        let fallbackProviderMode: AppLLMProviderMode = .openAICompatible
        let fallbackBaseURL = "https://api.openai.com/v1"
        let fallbackModel = "gpt-4o-mini"
        let modeRaw = legacyProviderMode ?? fallbackProviderMode.rawValue
        let mode = AppLLMProviderMode(rawValue: modeRaw) ?? fallbackProviderMode
        let id: String
        let name: String
        switch mode {
        case .openAIResponses:
            id = "openai-responses"
            name = "OpenAI Responses"
        case .openAICompatible:
            id = "openai-compatible"
            name = "OpenAI Compatible"
        case .anthropicMessages:
            id = "anthropic"
            name = "Claude"
        }
        let connection = AppLLMConnectionConfig(
            id: id,
            name: name,
            providerMode: mode,
            baseURLString: legacyBaseURL ?? fallbackBaseURL,
            model: legacyModel ?? fallbackModel,
            selectedModel: legacySelectedModel ?? "",
            hasAPIKey: legacyAPIKey?.isEmpty == false,
        )
        return AppLLMSettings(
            connections: [connection],
            defaultConnectionID: id,
            defaultThinkingLevel: AppLLMThinkingLevel.normalized(settingsStore.string(forKey: Keys.defaultThinkingLevel)) ?? .defaultLevel
        )
    }

    public func save(settings: AppLLMSettings, apiKey: String?) throws {
        let effectiveDefaultConnectionID: String = {
            if settings.connections.contains(where: { $0.id == settings.defaultConnectionID }) {
                return settings.defaultConnectionID
            }
            return settings.connections.first?.id ?? ""
        }()
        let sanitized = AppLLMSettings(
            connections: settings.connections.map { connection in
                var copy = connection
                copy.hasAPIKey = false
                return copy
            },
            defaultConnectionID: effectiveDefaultConnectionID,
            defaultThinkingLevel: settings.defaultThinkingLevel
        )
        settingsStore.set(sanitized.defaultThinkingLevel.rawValue, forKey: Keys.defaultThinkingLevel)
        let data = try JSONEncoder().encode(sanitized.connections)
        settingsStore.set(String(decoding: data, as: UTF8.self), forKey: Keys.connections)
        settingsStore.set(sanitized.defaultConnectionID, forKey: Keys.defaultConnectionID)

        if let defaultConnection = sanitized.defaultConnection {
            settingsStore.set(defaultConnection.providerMode.rawValue, forKey: Keys.providerMode)
            settingsStore.set(defaultConnection.baseURLString, forKey: Keys.baseURLString)
            settingsStore.set(defaultConnection.model, forKey: Keys.model)
            settingsStore.set(defaultConnection.effectiveModel, forKey: Keys.selectedModel)
            if let apiKey, !apiKey.isEmpty {
                try credentialStore.saveSecret(apiKey, service: Self.credentialNamespace, account: Self.apiKeyAccount(for: defaultConnection.id))
                if defaultConnection.id == "openai-compatible" || defaultConnection.id == "openai-responses" {
                    try credentialStore.saveSecret(apiKey, service: Self.credentialNamespace, account: Self.apiKeyAccount)
                }
            }
        } else {
            settingsStore.set("", forKey: Keys.providerMode)
            settingsStore.set("", forKey: Keys.baseURLString)
            settingsStore.set("", forKey: Keys.model)
            settingsStore.set("", forKey: Keys.selectedModel)
        }
    }

    public func clearAPIKey() throws {
        let settings = try loadSettings()
        try clearAPIKey(connectionID: settings.defaultConnectionID)
    }

    public func clearAPIKey(connectionID: String) throws {
        try credentialStore.deleteSecret(service: Self.credentialNamespace, account: Self.apiKeyAccount(for: connectionID))
        try credentialStore.deleteSecret(service: Self.credentialNamespace, account: Self.oauthAccount(for: connectionID))
        if connectionID == "openai-compatible" || connectionID == "openai-responses" {
            try credentialStore.deleteSecret(service: Self.credentialNamespace, account: Self.apiKeyAccount)
        }
    }

    public func saveOAuthTokens(_ tokens: AppLLMOAuthTokens, connectionID: String) throws {
        let data = try JSONEncoder().encode(tokens)
        try credentialStore.saveSecret(String(decoding: data, as: UTF8.self), service: Self.credentialNamespace, account: Self.oauthAccount(for: connectionID))
    }

    public func saveAPIKey(_ apiKey: String, connectionID: String) throws {
        guard !apiKey.isEmpty else { return }
        try credentialStore.saveSecret(apiKey, service: Self.credentialNamespace, account: Self.apiKeyAccount(for: connectionID))
        if connectionID == "openai-compatible" || connectionID == "openai-responses" {
            try credentialStore.saveSecret(apiKey, service: Self.credentialNamespace, account: Self.apiKeyAccount)
        }
    }

    public func updateConnection(_ connection: AppLLMConnectionConfig) throws {
        var settings = try loadSettings()
        guard let index = settings.connections.firstIndex(where: { $0.id == connection.id }) else { return }
        var sanitized = connection
        sanitized.hasAPIKey = try hasAPIKey(for: connection.id)
        settings.connections[index] = sanitized
        try save(settings: settings, apiKey: nil)
    }

    public func oauthTokens(for connectionID: String) throws -> AppLLMOAuthTokens? {
        guard let raw = try credentialStore.readSecret(service: Self.credentialNamespace, account: Self.oauthAccount(for: connectionID)),
              let data = raw.data(using: .utf8) else { return nil }
        return try JSONDecoder().decode(AppLLMOAuthTokens.self, from: data)
    }

    public func hasAPIKey(for connectionID: String) throws -> Bool {
        if let key = try credentialStore.readSecret(service: Self.credentialNamespace, account: Self.apiKeyAccount(for: connectionID)), !key.isEmpty {
            return true
        }
        if let oauth = try credentialStore.readSecret(service: Self.credentialNamespace, account: Self.oauthAccount(for: connectionID)), !oauth.isEmpty {
            return true
        }
        if (connectionID == "openai-compatible" || connectionID == "openai-responses"), let key = try credentialStore.readSecret(service: Self.credentialNamespace, account: Self.apiKeyAccount), !key.isEmpty {
            return true
        }
        return false
    }

    public func apiKey(for connectionID: String) throws -> String? {
        if let key = try credentialStore.readSecret(service: Self.credentialNamespace, account: Self.apiKeyAccount(for: connectionID)), !key.isEmpty {
            return key
        }
        if connectionID == "openai-compatible" || connectionID == "openai-responses" {
            return try credentialStore.readSecret(service: Self.credentialNamespace, account: Self.apiKeyAccount)
        }
        return nil
    }

    public func openAIResponsesConfig(
        connectionID: String? = nil,
        modelOverride: String? = nil,
        baseURLOverride: String? = nil,
        thinkingLevelOverride: AppLLMThinkingLevel? = nil
    ) throws -> OpenAIResponsesConfig? {
        let settings = try loadSettings()
        guard let connection = settings.connection(id: connectionID), connection.providerMode == .openAIResponses else { return nil }
        guard let apiKey = try apiKey(for: connection.id), !apiKey.isEmpty else { return nil }
        let urlString = baseURLOverride ?? connection.baseURLString
        guard let baseURL = URL(string: urlString) else {
            throw OpenAICompatibleProviderError.invalidBaseURL(urlString)
        }
        let apiKeyHeaderKind = OpenAICompatibleAPIKeyHeaderKind(rawValue: connection.extraHTTPHeaders[Self.openAIAPIKeyHeaderKindMetadataKey] ?? "") ?? .bearer
        var extraHeaders = connection.extraHTTPHeaders
        extraHeaders.removeValue(forKey: Self.openAIAPIKeyHeaderKindMetadataKey)
        let thinkingLevel = thinkingLevelOverride ?? settings.defaultThinkingLevel
        return OpenAIResponsesConfig(
            baseURL: baseURL,
            apiKey: apiKey,
            model: modelOverride ?? connection.effectiveModel,
            extraHeaders: extraHeaders,
            apiKeyHeaderKind: apiKeyHeaderKind,
            reasoningEffort: thinkingLevel.openAIReasoningEffort,
            includeEncryptedReasoning: thinkingLevel.openAIReasoningEffort != nil,
            explicitVisionSupport: connection.explicitVisionSupport
        )
    }

    public func openAICompatibleConfig(
        connectionID: String? = nil,
        modelOverride: String? = nil,
        baseURLOverride: String? = nil,
        thinkingLevelOverride: AppLLMThinkingLevel? = nil
    ) throws -> OpenAICompatibleConfig? {
        let settings = try loadSettings()
        guard let connection = settings.connection(id: connectionID), connection.providerMode == .openAICompatible else { return nil }
        guard connection.connectionKind != .anthropicCompatible else { return nil }
        guard let apiKey = try apiKey(for: connection.id), !apiKey.isEmpty else { return nil }
        let urlString = baseURLOverride ?? connection.baseURLString
        guard let baseURL = URL(string: urlString) else {
            throw OpenAICompatibleProviderError.invalidBaseURL(urlString)
        }
        let apiKeyHeaderKind = OpenAICompatibleAPIKeyHeaderKind(rawValue: connection.extraHTTPHeaders[Self.openAIAPIKeyHeaderKindMetadataKey] ?? "") ?? .bearer
        var extraHeaders = connection.extraHTTPHeaders
        extraHeaders.removeValue(forKey: Self.openAIAPIKeyHeaderKindMetadataKey)
        return OpenAICompatibleConfig(
            baseURL: baseURL,
            apiKey: apiKey,
            model: modelOverride ?? connection.effectiveModel,
            extraHeaders: extraHeaders,
            apiKeyHeaderKind: apiKeyHeaderKind,
            reasoningEffort: nil,
            explicitVisionSupport: connection.explicitVisionSupport
        )
    }

    public func anthropicCompatibleConfig(
        connectionID: String? = nil,
        modelOverride: String? = nil,
        baseURLOverride: String? = nil,
        thinkingLevelOverride: AppLLMThinkingLevel? = nil
    ) throws -> AnthropicCompatibleConfig? {
        let settings = try loadSettings()
        guard let connection = settings.connection(id: connectionID), connection.connectionKind == .anthropicCompatible else { return nil }
        guard connection.providerMode == .anthropicMessages || connection.providerMode == .openAICompatible else { return nil }
        guard let apiKey = try apiKey(for: connection.id), !apiKey.isEmpty else { return nil }
        let urlString = baseURLOverride ?? connection.baseURLString
        guard let baseURL = URL(string: urlString) else {
            throw OpenAICompatibleProviderError.invalidBaseURL(urlString)
        }
        let authHeaderKind = AnthropicCompatibleAuthHeaderKind(rawValue: connection.extraHTTPHeaders[Self.anthropicAuthHeaderKindMetadataKey] ?? "") ?? .xAPIKey
        var extraHeaders = connection.extraHTTPHeaders
        extraHeaders.removeValue(forKey: Self.anthropicAuthHeaderKindMetadataKey)
        let thinkingLevel = thinkingLevelOverride ?? settings.defaultThinkingLevel
        return AnthropicCompatibleConfig(
            baseURL: baseURL,
            apiKey: apiKey,
            model: modelOverride ?? connection.effectiveModel,
            authHeaderKind: authHeaderKind,
            extraHeaders: extraHeaders,
            featureOptions: AnthropicCompatibleFeatureOptions(thinking: thinkingLevel.anthropicThinking),
            explicitVisionSupport: connection.explicitVisionSupport
        )
    }
}

public struct AppLLMModelCatalog<Client: AgentHTTPClient>: Sendable {
    public var settingsRepository: AppLLMSettingsRepository
    public var httpClient: Client

    public init(settingsRepository: AppLLMSettingsRepository, httpClient: Client) {
        self.settingsRepository = settingsRepository
        self.httpClient = httpClient
    }

    public func loadConnections() async -> [AppLLMModelConnection] {
        do {
            let settings = try settingsRepository.loadSettings()
            var result: [AppLLMModelConnection] = []
            for connection in settings.connections {
                switch connection.providerMode {
                case .openAIResponses:
                    result.append(await openAICompatibleConnection(connection: connection, isDefault: connection.id == settings.defaultConnectionID))
                case .openAICompatible:
                    if connection.connectionKind == .anthropicCompatible {
                        result.append(anthropicCompatibleConnection(connection: connection, isDefault: connection.id == settings.defaultConnectionID))
                    } else {
                        result.append(await openAICompatibleConnection(connection: connection, isDefault: connection.id == settings.defaultConnectionID))
                    }
                case .anthropicMessages:
                    result.append(anthropicCompatibleConnection(connection: connection, isDefault: connection.id == settings.defaultConnectionID))
                }
            }
            return result
        } catch {
            return fallbackConnections(error: error)
        }
    }

    private func anthropicCompatibleConnection(connection: AppLLMConnectionConfig, isDefault: Bool) -> AppLLMModelConnection {
        AppLLMModelConnection(
            id: connection.id,
            title: connection.name + (isDefault ? " · 默认" : ""),
            subtitle: "Anthropic Compatible · \(connection.baseURLString)",
            providerMode: connection.providerMode,
            models: configuredOptions(from: connection),
            isLiveCatalog: false
        )
    }

    private func openAICompatibleConnection(connection: AppLLMConnectionConfig, isDefault: Bool) async -> AppLLMModelConnection {
        guard let baseURL = URL(string: connection.baseURLString) else {
            return AppLLMModelConnection(id: connection.id, title: connection.name + (isDefault ? " · 默认" : ""), subtitle: "OpenAI Compatible · Base URL 无效", providerMode: .openAICompatible, models: configuredOptions(from: connection), isLiveCatalog: false)
        }
        guard let apiKey = try? settingsRepository.apiKey(for: connection.id), !apiKey.isEmpty else {
            return AppLLMModelConnection(id: connection.id, title: connection.name + (isDefault ? " · 默认" : ""), subtitle: "OpenAI Compatible · 缺少 API Key", providerMode: .openAICompatible, models: configuredOptions(from: connection), isLiveCatalog: false)
        }
        var client = httpClient
        let request = AgentHTTPRequest(
            url: baseURL.appendingPathComponent("models"),
            method: "GET",
            headers: ["Authorization": "Bearer \(apiKey)"],
            body: Data()
        )
        do {
            let response = try await client.send(request)
            guard response.statusCode >= 200, response.statusCode < 300 else {
                return AppLLMModelConnection(id: connection.id, title: connection.name + (isDefault ? " · 默认" : ""), subtitle: "OpenAI Compatible · 模型列表请求失败（HTTP \(response.statusCode)）", providerMode: .openAICompatible, models: configuredOptions(from: connection), isLiveCatalog: false)
            }
            let modelIDs = try Self.parseModelIDs(response.body)
            let options = modelIDs.map { AppLLMModelOption(id: $0) }
            return AppLLMModelConnection(id: connection.id, title: connection.name + (isDefault ? " · 默认" : ""), subtitle: "OpenAI Compatible · \(baseURL.absoluteString)", providerMode: .openAICompatible, models: options, isLiveCatalog: true)
        } catch {
            return AppLLMModelConnection(id: connection.id, title: connection.name + (isDefault ? " · 默认" : ""), subtitle: "OpenAI Compatible · 模型列表解析失败", providerMode: .openAICompatible, models: configuredOptions(from: connection), isLiveCatalog: false)
        }
    }

    private func fallbackConnections(error: Error) -> [AppLLMModelConnection] {
        let settings = (try? settingsRepository.loadSettings()) ?? .default
        guard let connection = settings.defaultConnection else { return [] }
        return [AppLLMModelConnection(id: connection.id, title: connection.name, subtitle: "模型目录不可用：\(error.localizedDescription)", providerMode: connection.providerMode, models: configuredOptions(from: connection), isLiveCatalog: false)]
    }

    private func configuredOptions(from connection: AppLLMConnectionConfig) -> [AppLLMModelOption] {
        var ids = connection.modelOptions
        let selected = connection.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !selected.isEmpty, !ids.contains(selected) { ids.insert(selected, at: 0) }
        return ids.map { AppLLMModelOption(id: $0) }
    }

    private static func parseModelIDs(_ data: Data) throws -> [String] {
        let decoded = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        return decoded.data
            .map(\.id)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

private struct OpenAIModelsResponse: Decodable {
    var data: [OpenAIModel]
}

private struct OpenAIModel: Decodable {
    var id: String
}
