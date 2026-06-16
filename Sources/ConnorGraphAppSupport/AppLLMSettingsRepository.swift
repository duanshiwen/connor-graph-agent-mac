import Foundation
import ConnorGraphAgent

public enum AppLLMProviderMode: String, Sendable, Equatable, CaseIterable, Codable {
    case openAICompatible = "openai_compatible"
    case governedClaudeSidecar = "governed_claude_sidecar"

    public var displayName: String {
        switch self {
        case .openAICompatible:
            return "OpenAI Compatible"
        case .governedClaudeSidecar:
            return "Claude"
        }
    }
}

public enum AppLLMConnectionKind: String, Sendable, Equatable, CaseIterable, Codable {
    case openAICompatible = "openai_compatible"
    case claudeSidecar = "claude_sidecar"
    case chatGPTCodex = "chatgpt_codex"
    case githubCopilot = "github_copilot"

    public var displayName: String {
        switch self {
        case .openAICompatible: return "OpenAI Compatible"
        case .claudeSidecar: return "Claude SDK Sidecar"
        case .chatGPTCodex: return "Codex · ChatGPT"
        case .githubCopilot: return "GitHub Copilot"
        }
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
    public var sidecarExecutablePath: String
    public var sidecarArguments: String
    public var sidecarWorkingDirectoryPath: String
    public var sidecarPermissionMode: AgentPermissionMode
    public var extraHTTPHeaders: [String: String]

    private enum CodingKeys: String, CodingKey {
        case id, name, providerMode, connectionKind, baseURLString, model, selectedModel, hasAPIKey
        case sidecarExecutablePath, sidecarArguments, sidecarWorkingDirectoryPath, sidecarPermissionMode, extraHTTPHeaders
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
        sidecarExecutablePath: String = "",
        sidecarArguments: String = "",
        sidecarWorkingDirectoryPath: String = "",
        sidecarPermissionMode: AgentPermissionMode = .readOnly,
        extraHTTPHeaders: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.providerMode = providerMode
        self.connectionKind = connectionKind ?? (providerMode == .governedClaudeSidecar ? .claudeSidecar : .openAICompatible)
        self.baseURLString = baseURLString
        self.model = model
        let normalizedSelectedModel = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        self.selectedModel = normalizedSelectedModel.isEmpty ? Self.firstModel(in: model) : normalizedSelectedModel
        self.hasAPIKey = hasAPIKey
        self.sidecarExecutablePath = sidecarExecutablePath
        self.sidecarArguments = sidecarArguments
        self.sidecarWorkingDirectoryPath = sidecarWorkingDirectoryPath
        self.sidecarPermissionMode = sidecarPermissionMode == .allowAll ? .readOnly : sidecarPermissionMode
        self.extraHTTPHeaders = extraHTTPHeaders
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
            sidecarExecutablePath: try container.decodeIfPresent(String.self, forKey: .sidecarExecutablePath) ?? "",
            sidecarArguments: try container.decodeIfPresent(String.self, forKey: .sidecarArguments) ?? "",
            sidecarWorkingDirectoryPath: try container.decodeIfPresent(String.self, forKey: .sidecarWorkingDirectoryPath) ?? "",
            sidecarPermissionMode: try container.decodeIfPresent(AgentPermissionMode.self, forKey: .sidecarPermissionMode) ?? .readOnly,
            extraHTTPHeaders: try container.decodeIfPresent([String: String].self, forKey: .extraHTTPHeaders) ?? [:]
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

    public init(connections: [AppLLMConnectionConfig], defaultConnectionID: String) {
        let normalizedConnections = connections.isEmpty ? [AppLLMConnectionConfig.defaultOpenAICompatible] : connections
        self.connections = normalizedConnections
        self.defaultConnectionID = normalizedConnections.contains(where: { $0.id == defaultConnectionID })
            ? defaultConnectionID
            : normalizedConnections[0].id
    }

    public init(
        baseURLString: String,
        model: String,
        selectedModel: String = "",
        hasAPIKey: Bool,
        providerMode: AppLLMProviderMode,
        sidecarExecutablePath: String = "",
        sidecarArguments: String = "",
        sidecarWorkingDirectoryPath: String = "",
        sidecarPermissionMode: AgentPermissionMode = .readOnly
    ) {
        let id = providerMode == .openAICompatible ? "openai-compatible" : "claude-sidecar"
        let name = providerMode == .openAICompatible ? "OpenAI Compatible" : "Claude"
        let connection = AppLLMConnectionConfig(
            id: id,
            name: name,
            providerMode: providerMode,
            baseURLString: baseURLString,
            model: model,
            selectedModel: selectedModel,
            hasAPIKey: hasAPIKey,
            sidecarExecutablePath: sidecarExecutablePath,
            sidecarArguments: sidecarArguments,
            sidecarWorkingDirectoryPath: sidecarWorkingDirectoryPath,
            sidecarPermissionMode: sidecarPermissionMode
        )
        self.init(connections: [connection], defaultConnectionID: id)
    }

    public var defaultConnection: AppLLMConnectionConfig {
        connections.first(where: { $0.id == defaultConnectionID }) ?? connections[0]
    }

    public func connection(id: String?) -> AppLLMConnectionConfig? {
        guard let id, !id.isEmpty else { return defaultConnection }
        return connections.first(where: { $0.id == id })
    }

    public var baseURLString: String { defaultConnection.baseURLString }
    public var model: String { defaultConnection.model }
    public var selectedModel: String { defaultConnection.selectedModel }
    public var hasAPIKey: Bool { defaultConnection.hasAPIKey }
    public var providerMode: AppLLMProviderMode { defaultConnection.providerMode }
    public var sidecarExecutablePath: String { defaultConnection.sidecarExecutablePath }
    public var sidecarArguments: String { defaultConnection.sidecarArguments }
    public var sidecarWorkingDirectoryPath: String { defaultConnection.sidecarWorkingDirectoryPath }
    public var sidecarPermissionMode: AgentPermissionMode { defaultConnection.sidecarPermissionMode }
    public var modelOptions: [String] { defaultConnection.modelOptions }
    public var effectiveModel: String { defaultConnection.effectiveModel }

    public static func modelOptions(in rawValue: String) -> [String] { AppLLMConnectionConfig.modelOptions(in: rawValue) }
    public static func firstModel(in rawValue: String) -> String { AppLLMConnectionConfig.firstModel(in: rawValue) }

    public static let `default` = AppLLMSettings(
        connections: [.defaultOpenAICompatible],
        defaultConnectionID: AppLLMConnectionConfig.defaultOpenAICompatible.id
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
    public static let keychainService = "ConnorGraphAgent"
    public static let apiKeyAccount = "openai-compatible-api-key"

    private enum Keys {
        static let connections = "llm.connections"
        static let defaultConnectionID = "llm.defaultConnectionID"
        static let providerMode = "llm.providerMode"
        static let baseURLString = "llm.baseURLString"
        static let model = "llm.model"
        static let selectedModel = "llm.selectedModel"
        static let sidecarExecutablePath = "llm.sidecar.executablePath"
        static let sidecarArguments = "llm.sidecar.arguments"
        static let sidecarWorkingDirectoryPath = "llm.sidecar.workingDirectoryPath"
        static let sidecarPermissionMode = "llm.sidecar.permissionMode"
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

    public func loadSettings() throws -> AppLLMSettings {
        if let raw = settingsStore.string(forKey: Keys.connections), let data = raw.data(using: .utf8) {
            let decoded = try JSONDecoder().decode([AppLLMConnectionConfig].self, from: data)
            let hydrated = try decoded.map { connection in
                var copy = connection
                copy.hasAPIKey = try hasAPIKey(for: connection.id)
                return copy
            }
            return AppLLMSettings(
                connections: hydrated,
                defaultConnectionID: settingsStore.string(forKey: Keys.defaultConnectionID) ?? hydrated.first?.id ?? AppLLMConnectionConfig.defaultOpenAICompatible.id
            )
        }
        return try loadLegacySettings()
    }

    private func loadLegacySettings() throws -> AppLLMSettings {
        let defaults = AppLLMSettings.default
        let defaultConnection = defaults.defaultConnection
        let modeRaw = settingsStore.string(forKey: Keys.providerMode) ?? defaultConnection.providerMode.rawValue
        let mode = AppLLMProviderMode(rawValue: modeRaw) ?? defaultConnection.providerMode
        let apiKey = try credentialStore.readSecret(service: Self.keychainService, account: Self.apiKeyAccount)
        let sidecarPermissionRaw = settingsStore.string(forKey: Keys.sidecarPermissionMode) ?? defaultConnection.sidecarPermissionMode.rawValue
        let sidecarPermissionMode = AgentPermissionMode(rawValue: sidecarPermissionRaw) ?? defaultConnection.sidecarPermissionMode
        let id = mode == .openAICompatible ? "openai-compatible" : "claude-sidecar"
        let connection = AppLLMConnectionConfig(
            id: id,
            name: mode == .openAICompatible ? "OpenAI Compatible" : "Claude",
            providerMode: mode,
            baseURLString: settingsStore.string(forKey: Keys.baseURLString) ?? defaultConnection.baseURLString,
            model: settingsStore.string(forKey: Keys.model) ?? defaultConnection.model,
            selectedModel: settingsStore.string(forKey: Keys.selectedModel) ?? "",
            hasAPIKey: apiKey?.isEmpty == false,
            sidecarExecutablePath: settingsStore.string(forKey: Keys.sidecarExecutablePath) ?? defaultConnection.sidecarExecutablePath,
            sidecarArguments: settingsStore.string(forKey: Keys.sidecarArguments) ?? defaultConnection.sidecarArguments,
            sidecarWorkingDirectoryPath: settingsStore.string(forKey: Keys.sidecarWorkingDirectoryPath) ?? defaultConnection.sidecarWorkingDirectoryPath,
            sidecarPermissionMode: sidecarPermissionMode
        )
        return AppLLMSettings(connections: [connection], defaultConnectionID: id)
    }

    public func save(settings: AppLLMSettings, apiKey: String?) throws {
        let sanitized = AppLLMSettings(
            connections: settings.connections.map { connection in
                var copy = connection
                copy.hasAPIKey = false
                copy.sidecarPermissionMode = copy.sidecarPermissionMode == .allowAll ? .readOnly : copy.sidecarPermissionMode
                return copy
            },
            defaultConnectionID: settings.defaultConnectionID
        )
        let data = try JSONEncoder().encode(sanitized.connections)
        settingsStore.set(String(decoding: data, as: UTF8.self), forKey: Keys.connections)
        settingsStore.set(sanitized.defaultConnectionID, forKey: Keys.defaultConnectionID)

        let defaultConnection = settings.defaultConnection
        settingsStore.set(defaultConnection.providerMode.rawValue, forKey: Keys.providerMode)
        settingsStore.set(defaultConnection.baseURLString, forKey: Keys.baseURLString)
        settingsStore.set(defaultConnection.model, forKey: Keys.model)
        settingsStore.set(defaultConnection.effectiveModel, forKey: Keys.selectedModel)
        settingsStore.set(defaultConnection.sidecarExecutablePath, forKey: Keys.sidecarExecutablePath)
        settingsStore.set(defaultConnection.sidecarArguments, forKey: Keys.sidecarArguments)
        settingsStore.set(defaultConnection.sidecarWorkingDirectoryPath, forKey: Keys.sidecarWorkingDirectoryPath)
        settingsStore.set(defaultConnection.sidecarPermissionMode == .allowAll ? AgentPermissionMode.readOnly.rawValue : defaultConnection.sidecarPermissionMode.rawValue, forKey: Keys.sidecarPermissionMode)
        if let apiKey, !apiKey.isEmpty {
            try credentialStore.saveSecret(apiKey, service: Self.keychainService, account: Self.apiKeyAccount(for: defaultConnection.id))
            if defaultConnection.id == "openai-compatible" {
                try credentialStore.saveSecret(apiKey, service: Self.keychainService, account: Self.apiKeyAccount)
            }
        }
    }

    public func clearAPIKey() throws {
        let settings = try loadSettings()
        try clearAPIKey(connectionID: settings.defaultConnectionID)
    }

    public func clearAPIKey(connectionID: String) throws {
        try credentialStore.deleteSecret(service: Self.keychainService, account: Self.apiKeyAccount(for: connectionID))
        try credentialStore.deleteSecret(service: Self.keychainService, account: Self.oauthAccount(for: connectionID))
        if connectionID == "openai-compatible" {
            try credentialStore.deleteSecret(service: Self.keychainService, account: Self.apiKeyAccount)
        }
    }

    public func saveOAuthTokens(_ tokens: AppLLMOAuthTokens, connectionID: String) throws {
        let data = try JSONEncoder().encode(tokens)
        try credentialStore.saveSecret(String(decoding: data, as: UTF8.self), service: Self.keychainService, account: Self.oauthAccount(for: connectionID))
    }

    public func oauthTokens(for connectionID: String) throws -> AppLLMOAuthTokens? {
        guard let raw = try credentialStore.readSecret(service: Self.keychainService, account: Self.oauthAccount(for: connectionID)),
              let data = raw.data(using: .utf8) else { return nil }
        return try JSONDecoder().decode(AppLLMOAuthTokens.self, from: data)
    }

    public func hasAPIKey(for connectionID: String) throws -> Bool {
        if let key = try credentialStore.readSecret(service: Self.keychainService, account: Self.apiKeyAccount(for: connectionID)), !key.isEmpty {
            return true
        }
        if let oauth = try credentialStore.readSecret(service: Self.keychainService, account: Self.oauthAccount(for: connectionID)), !oauth.isEmpty {
            return true
        }
        if connectionID == "openai-compatible", let key = try credentialStore.readSecret(service: Self.keychainService, account: Self.apiKeyAccount), !key.isEmpty {
            return true
        }
        return false
    }

    public func apiKey(for connectionID: String) throws -> String? {
        if let key = try credentialStore.readSecret(service: Self.keychainService, account: Self.apiKeyAccount(for: connectionID)), !key.isEmpty {
            return key
        }
        if connectionID == "openai-compatible" {
            return try credentialStore.readSecret(service: Self.keychainService, account: Self.apiKeyAccount)
        }
        return nil
    }

    public func openAICompatibleConfig(connectionID: String? = nil, modelOverride: String? = nil, baseURLOverride: String? = nil) throws -> OpenAICompatibleConfig? {
        let settings = try loadSettings()
        guard let connection = settings.connection(id: connectionID), connection.providerMode == .openAICompatible else { return nil }
        guard let apiKey = try apiKey(for: connection.id), !apiKey.isEmpty else { return nil }
        let urlString = baseURLOverride ?? connection.baseURLString
        guard let baseURL = URL(string: urlString) else {
            throw OpenAICompatibleProviderError.invalidBaseURL(urlString)
        }
        return OpenAICompatibleConfig(baseURL: baseURL, apiKey: apiKey, model: modelOverride ?? connection.effectiveModel, extraHeaders: connection.extraHTTPHeaders)
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
                case .openAICompatible:
                    result.append(await openAICompatibleConnection(connection: connection, isDefault: connection.id == settings.defaultConnectionID))
                case .governedClaudeSidecar:
                    result.append(sidecarConnection(connection: connection, isDefault: connection.id == settings.defaultConnectionID))
                }
            }
            return result
        } catch {
            return fallbackConnections(error: error)
        }
    }

    private func sidecarConnection(connection: AppLLMConnectionConfig, isDefault: Bool) -> AppLLMModelConnection {
        AppLLMModelConnection(
            id: connection.id,
            title: connection.name + (isDefault ? " · 默认" : ""),
            subtitle: connection.sidecarExecutablePath.isEmpty ? "Claude · Sidecar 未配置 executable" : "Claude · \(connection.sidecarExecutablePath)",
            providerMode: .governedClaudeSidecar,
            models: options(from: connection, fallback: "claude-sdk-default"),
            isLiveCatalog: false
        )
    }

    private func openAICompatibleConnection(connection: AppLLMConnectionConfig, isDefault: Bool) async -> AppLLMModelConnection {
        let configuredModels = connection.modelOptions
        let selectedModel = connection.effectiveModel
        let fallbackModel = selectedModel.isEmpty ? AppLLMSettings.default.effectiveModel : selectedModel
        guard let baseURL = URL(string: connection.baseURLString) else {
            return AppLLMModelConnection(id: connection.id, title: connection.name + (isDefault ? " · 默认" : ""), subtitle: "OpenAI Compatible · Base URL 无效", providerMode: .openAICompatible, models: options(from: connection, fallback: fallbackModel), isLiveCatalog: false)
        }
        guard let apiKey = try? settingsRepository.apiKey(for: connection.id), !apiKey.isEmpty else {
            return AppLLMModelConnection(id: connection.id, title: connection.name + (isDefault ? " · 默认" : ""), subtitle: "OpenAI Compatible · 缺少 API Key", providerMode: .openAICompatible, models: options(from: connection, fallback: fallbackModel), isLiveCatalog: false)
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
                return AppLLMModelConnection(id: connection.id, title: connection.name + (isDefault ? " · 默认" : ""), subtitle: "OpenAI Compatible · 模型列表请求失败（HTTP \(response.statusCode)）", providerMode: .openAICompatible, models: options(from: connection, fallback: fallbackModel), isLiveCatalog: false)
            }
            let modelIDs = try Self.parseModelIDs(response.body)
            var options = modelIDs.map { AppLLMModelOption(id: $0) }
            let missingConfiguredModels = configuredModels.filter { configuredModel in !options.contains(where: { $0.id == configuredModel }) }
            options.insert(contentsOf: missingConfiguredModels.map { AppLLMModelOption(id: $0) }, at: 0)
            if options.isEmpty { options = [AppLLMModelOption(id: fallbackModel)] }
            return AppLLMModelConnection(id: connection.id, title: connection.name + (isDefault ? " · 默认" : ""), subtitle: "OpenAI Compatible · \(baseURL.absoluteString)", providerMode: .openAICompatible, models: options, isLiveCatalog: true)
        } catch {
            return AppLLMModelConnection(id: connection.id, title: connection.name + (isDefault ? " · 默认" : ""), subtitle: "OpenAI Compatible · 模型列表解析失败", providerMode: .openAICompatible, models: options(from: connection, fallback: fallbackModel), isLiveCatalog: false)
        }
    }

    private func fallbackConnections(error: Error) -> [AppLLMModelConnection] {
        let settings = (try? settingsRepository.loadSettings()) ?? .default
        let connection = settings.defaultConnection
        let fallbackModel = connection.effectiveModel.isEmpty ? AppLLMSettings.default.effectiveModel : connection.effectiveModel
        return [AppLLMModelConnection(id: connection.id, title: connection.name, subtitle: "模型目录不可用：\(error.localizedDescription)", providerMode: connection.providerMode, models: options(from: connection, fallback: fallbackModel), isLiveCatalog: false)]
    }

    private func options(from connection: AppLLMConnectionConfig, fallback: String) -> [AppLLMModelOption] {
        var ids = connection.modelOptions
        if ids.isEmpty { ids = [fallback] }
        let selected = connection.effectiveModel
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
