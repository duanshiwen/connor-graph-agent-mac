import Foundation
import ConnorGraphAgent

public enum AppLLMProviderMode: String, Sendable, Equatable, CaseIterable {
    case openAICompatible = "openai_compatible"
    case governedClaudeSidecar = "governed_claude_sidecar"
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
    public var baseURLString: String
    public var model: String
    public var selectedModel: String
    public var hasAPIKey: Bool
    public var providerMode: AppLLMProviderMode
    public var sidecarExecutablePath: String
    public var sidecarArguments: String
    public var sidecarWorkingDirectoryPath: String
    public var sidecarPermissionMode: AgentPermissionMode

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
        self.baseURLString = baseURLString
        self.model = model
        let normalizedSelectedModel = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        self.selectedModel = normalizedSelectedModel.isEmpty ? Self.firstModel(in: model) : normalizedSelectedModel
        self.hasAPIKey = hasAPIKey
        self.providerMode = providerMode
        self.sidecarExecutablePath = sidecarExecutablePath
        self.sidecarArguments = sidecarArguments
        self.sidecarWorkingDirectoryPath = sidecarWorkingDirectoryPath
        self.sidecarPermissionMode = sidecarPermissionMode == .allowAll ? .readOnly : sidecarPermissionMode
    }

    public var modelOptions: [String] {
        Self.modelOptions(in: model)
    }

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

    public static let `default` = AppLLMSettings(
        baseURLString: "https://api.openai.com/v1",
        model: "gpt-4o-mini",
        selectedModel: "gpt-4o-mini",
        hasAPIKey: false,
        providerMode: .openAICompatible
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

    public func loadSettings() throws -> AppLLMSettings {
        let defaults = AppLLMSettings.default
        let modeRaw = settingsStore.string(forKey: Keys.providerMode) ?? defaults.providerMode.rawValue
        let mode = AppLLMProviderMode(rawValue: modeRaw) ?? defaults.providerMode
        let apiKey = try credentialStore.readSecret(
            service: Self.keychainService,
            account: Self.apiKeyAccount
        )
        let sidecarPermissionRaw = settingsStore.string(forKey: Keys.sidecarPermissionMode) ?? defaults.sidecarPermissionMode.rawValue
        let sidecarPermissionMode = AgentPermissionMode(rawValue: sidecarPermissionRaw) ?? defaults.sidecarPermissionMode
        return AppLLMSettings(
            baseURLString: settingsStore.string(forKey: Keys.baseURLString) ?? defaults.baseURLString,
            model: settingsStore.string(forKey: Keys.model) ?? defaults.model,
            selectedModel: settingsStore.string(forKey: Keys.selectedModel) ?? "",
            hasAPIKey: apiKey?.isEmpty == false,
            providerMode: mode,
            sidecarExecutablePath: settingsStore.string(forKey: Keys.sidecarExecutablePath) ?? defaults.sidecarExecutablePath,
            sidecarArguments: settingsStore.string(forKey: Keys.sidecarArguments) ?? defaults.sidecarArguments,
            sidecarWorkingDirectoryPath: settingsStore.string(forKey: Keys.sidecarWorkingDirectoryPath) ?? defaults.sidecarWorkingDirectoryPath,
            sidecarPermissionMode: sidecarPermissionMode
        )
    }

    public func save(settings: AppLLMSettings, apiKey: String?) throws {
        settingsStore.set(settings.providerMode.rawValue, forKey: Keys.providerMode)
        settingsStore.set(settings.baseURLString, forKey: Keys.baseURLString)
        settingsStore.set(settings.model, forKey: Keys.model)
        settingsStore.set(settings.effectiveModel, forKey: Keys.selectedModel)
        settingsStore.set(settings.sidecarExecutablePath, forKey: Keys.sidecarExecutablePath)
        settingsStore.set(settings.sidecarArguments, forKey: Keys.sidecarArguments)
        settingsStore.set(settings.sidecarWorkingDirectoryPath, forKey: Keys.sidecarWorkingDirectoryPath)
        settingsStore.set(settings.sidecarPermissionMode == .allowAll ? AgentPermissionMode.readOnly.rawValue : settings.sidecarPermissionMode.rawValue, forKey: Keys.sidecarPermissionMode)
        if let apiKey, !apiKey.isEmpty {
            try credentialStore.saveSecret(
                apiKey,
                service: Self.keychainService,
                account: Self.apiKeyAccount
            )
        }
    }

    public func clearAPIKey() throws {
        try credentialStore.deleteSecret(
            service: Self.keychainService,
            account: Self.apiKeyAccount
        )
    }

    public func openAICompatibleConfig() throws -> OpenAICompatibleConfig? {
        let settings = try loadSettings()
        guard settings.providerMode == .openAICompatible else { return nil }
        guard let apiKey = try credentialStore.readSecret(service: Self.keychainService, account: Self.apiKeyAccount), !apiKey.isEmpty else {
            return nil
        }
        guard let baseURL = URL(string: settings.baseURLString) else {
            throw OpenAICompatibleProviderError.invalidBaseURL(settings.baseURLString)
        }
        return OpenAICompatibleConfig(baseURL: baseURL, apiKey: apiKey, model: settings.effectiveModel)
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
            var connections: [AppLLMModelConnection] = []

            if let openAIConnection = await openAICompatibleConnection(settings: settings) {
                connections.append(openAIConnection)
            }

            if settings.providerMode == .governedClaudeSidecar || !settings.sidecarExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                connections.append(sidecarConnection(settings: settings))
            }

            return connections
        } catch {
            return fallbackConnections(error: error)
        }
    }

    private func sidecarConnection(settings: AppLLMSettings) -> AppLLMModelConnection {
        return AppLLMModelConnection(
            id: AppLLMProviderMode.governedClaudeSidecar.rawValue,
            title: "Claude Sidecar",
            subtitle: settings.sidecarExecutablePath.isEmpty ? "已配置 Sidecar Provider" : settings.sidecarExecutablePath,
            providerMode: .governedClaudeSidecar,
            models: options(from: settings, fallback: "claude-sdk-default"),
            isLiveCatalog: false
        )
    }

    private func openAICompatibleConnection(settings: AppLLMSettings) async -> AppLLMModelConnection? {
        let configuredModels = settings.modelOptions
        let selectedModel = settings.effectiveModel
        let fallbackModel = selectedModel.isEmpty ? AppLLMSettings.default.effectiveModel : selectedModel
        guard let baseURL = URL(string: settings.baseURLString) else {
            guard settings.providerMode == .openAICompatible else { return nil }
            return AppLLMModelConnection(
                id: AppLLMProviderMode.openAICompatible.rawValue,
                title: "OpenAI 兼容",
                subtitle: "Base URL 无效，显示当前配置模型",
                providerMode: .openAICompatible,
                models: options(from: settings, fallback: fallbackModel),
                isLiveCatalog: false
            )
        }
        guard let apiKey = try? settingsRepository.credentialStore.readSecret(
            service: AppLLMSettingsRepository.keychainService,
            account: AppLLMSettingsRepository.apiKeyAccount
        ), !apiKey.isEmpty else {
            guard settings.providerMode == .openAICompatible else { return nil }
            return AppLLMModelConnection(
                id: AppLLMProviderMode.openAICompatible.rawValue,
                title: "OpenAI 兼容",
                subtitle: "缺少 API Key，显示当前配置模型",
                providerMode: .openAICompatible,
                models: options(from: settings, fallback: fallbackModel),
                isLiveCatalog: false
            )
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
                return AppLLMModelConnection(
                    id: AppLLMProviderMode.openAICompatible.rawValue,
                    title: "OpenAI 兼容",
                    subtitle: "模型列表请求失败（HTTP \(response.statusCode)），显示当前配置模型",
                    providerMode: .openAICompatible,
                    models: options(from: settings, fallback: fallbackModel),
                    isLiveCatalog: false
                )
            }
            let modelIDs = try Self.parseModelIDs(response.body)
            var options = modelIDs.map { AppLLMModelOption(id: $0) }
            let missingConfiguredModels = configuredModels.filter { configuredModel in
                !options.contains(where: { $0.id == configuredModel })
            }
            options.insert(contentsOf: missingConfiguredModels.map { AppLLMModelOption(id: $0) }, at: 0)
            if options.isEmpty {
                options = [AppLLMModelOption(id: fallbackModel)]
            }
            return AppLLMModelConnection(
                id: AppLLMProviderMode.openAICompatible.rawValue,
                title: "OpenAI 兼容",
                subtitle: baseURL.absoluteString,
                providerMode: .openAICompatible,
                models: options,
                isLiveCatalog: true
            )
        } catch {
            return AppLLMModelConnection(
                id: AppLLMProviderMode.openAICompatible.rawValue,
                title: "OpenAI 兼容",
                subtitle: "模型列表解析失败，显示当前配置模型",
                providerMode: .openAICompatible,
                models: options(from: settings, fallback: fallbackModel),
                isLiveCatalog: false
            )
        }
    }

    private func fallbackConnections(error: Error) -> [AppLLMModelConnection] {
        let settings = (try? settingsRepository.loadSettings()) ?? .default
        let fallbackModel = settings.effectiveModel.isEmpty ? AppLLMSettings.default.effectiveModel : settings.effectiveModel
        return [
            AppLLMModelConnection(
                id: settings.providerMode.rawValue,
                title: settings.providerMode.displayName,
                subtitle: "模型目录不可用：\(error.localizedDescription)",
                providerMode: settings.providerMode,
                models: options(from: settings, fallback: fallbackModel),
                isLiveCatalog: false
            )
        ]
    }

    private func options(from settings: AppLLMSettings, fallback: String) -> [AppLLMModelOption] {
        var ids = settings.modelOptions
        if ids.isEmpty {
            ids = [fallback]
        }
        let selected = settings.effectiveModel
        if !selected.isEmpty, !ids.contains(selected) {
            ids.insert(selected, at: 0)
        }
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

private extension AppLLMProviderMode {
    var displayName: String {
        switch self {
        case .openAICompatible:
            return "OpenAI 兼容"
        case .governedClaudeSidecar:
            return "Claude Sidecar"
        }
    }
}

private struct OpenAIModelsResponse: Decodable {
    var data: [OpenAIModel]
}

private struct OpenAIModel: Decodable {
    var id: String
}
