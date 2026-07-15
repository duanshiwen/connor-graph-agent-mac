import Foundation
import Observation
import ConnorGraphAgent
import ConnorGraphAppSupport

@MainActor
@Observable
final class AIConnectionsFeatureModel {
    var connectionConfigs: [AppLLMConnectionConfig] = []
    var defaultConnectionID = ""
    var connectionName = ""
    var providerMode: AppLLMProviderMode = .openAICompatible
    var baseURLString = ""
    var model = ""
    var selectedModel = ""
    var shouldFetchModelsList = true
    var thinkingLevel = AppLLMSettings.default.defaultThinkingLevel
    var apiKeyInput = ""
    var hasAPIKey = false
    var settingsMessage: String?
    var healthCheckMessage: String?
    var isTestingConnection = false
    private(set) var lastAddedConnectionID: String?
    private(set) var lastAddedCapabilityEvidence: [AppProviderCapabilityEvidence] = []
    var isAddingConnection = false
    var modelConnections: [AppLLMModelConnection] = []
    var isLoadingModelConnections = false
    var showsWelcome = true
    var errorMessage: String?

    @ObservationIgnored let settingsRepository: AppLLMSettingsRepository
    @ObservationIgnored private let healthChecker: AppLLMProviderHealthChecker
    @ObservationIgnored private let capabilityEvidenceRepository: AppProviderCapabilityEvidenceRepository
    @ObservationIgnored private let setupServiceFactory: @MainActor (AppLLMSettingsRepository) -> AppLLMConnectionSetupService
    @ObservationIgnored var onRuntimeSettingsChanged: (_ rebuildRuntime: Bool) -> Void = { _ in }
    @ObservationIgnored var onConnectionSetup: (AppLLMConnectionConfig) -> Void = { _ in }

    init(
        settingsRepository: AppLLMSettingsRepository = AppLLMSettingsRepository(),
        setupServiceFactory: (@MainActor (AppLLMSettingsRepository) -> AppLLMConnectionSetupService)? = nil
    ) {
        self.settingsRepository = settingsRepository
        self.healthChecker = AppLLMProviderHealthChecker(settingsRepository: settingsRepository)
        let evidenceRepository = AppProviderCapabilityEvidenceRepository(
            settingsStore: settingsRepository.settingsStore,
            credentialStore: settingsRepository.credentialStore
        )
        self.capabilityEvidenceRepository = evidenceRepository
        self.setupServiceFactory = setupServiceFactory ?? { repository in
            AppLLMConnectionSetupService(
                settingsRepository: repository,
                capabilityDiscoveryService: AppProviderCapabilityDiscoveryService(
                    settingsRepository: repository,
                    evidenceRepository: evidenceRepository
                )
            )
        }
    }

    func apply(_ settings: AppLLMSettings) {
        let connection = settings.defaultConnection
        connectionConfigs = settings.connections
        defaultConnectionID = settings.defaultConnectionID
        connectionName = connection?.name ?? ""
        providerMode = connection?.providerMode ?? .openAICompatible
        baseURLString = connection?.baseURLString ?? ""
        model = connection?.model ?? ""
        selectedModel = connection?.effectiveModel ?? ""
        shouldFetchModelsList = connection?.shouldFetchModelsList ?? true
        thinkingLevel = settings.defaultThinkingLevel
        hasAPIKey = connection?.hasAPIKey ?? false
        apiKeyInput = ""
        settingsMessage = nil
        healthCheckMessage = nil
        showsWelcome = settings.connections.isEmpty
    }

    func loadSettings() {
        do {
            apply(try settingsRepository.loadSettings())
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func updateWelcomeState() {
        do {
            showsWelcome = try settingsRepository.loadSettings().connections.isEmpty
        } catch {
            showsWelcome = connectionConfigs.isEmpty
        }
    }

    func handleSuccessfulSetup() {
        loadSettings()
        showsWelcome = false
    }

    func reloadModelConnections() async {
        isLoadingModelConnections = true
        defer { isLoadingModelConnections = false }
        let catalog = AppLLMModelCatalog(settingsRepository: settingsRepository, httpClient: URLSessionAgentHTTPClient())
        modelConnections = await catalog.loadConnections()
    }

    func selectDefaultConnection(_ connectionID: String) {
        guard let connection = connectionConfigs.first(where: { $0.id == connectionID }) else { return }
        defaultConnectionID = connection.id
        connectionName = connection.name
        providerMode = connection.providerMode
        baseURLString = connection.baseURLString
        model = connection.model
        selectedModel = connection.effectiveModel
        shouldFetchModelsList = connection.shouldFetchModelsList
        hasAPIKey = connection.hasAPIKey
        apiKeyInput = ""
        persistSettings(rebuildRuntime: true)
    }

    func selectDefaultThinkingLevel(_ level: AppLLMThinkingLevel) {
        do {
            let existing = (try? settingsRepository.loadSettings()) ?? .default
            let settings = AppLLMSettings(
                connections: existing.connections,
                defaultConnectionID: existing.defaultConnectionID,
                defaultThinkingLevel: level
            )
            try settingsRepository.save(settings: settings, apiKey: nil)
            thinkingLevel = level
            onRuntimeSettingsChanged(true)
            settingsMessage = "默认思考强度已保存。"
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    @discardableResult
    func addConnection(
        providerMode: AppLLMProviderMode,
        name: String? = nil,
        baseURLString: String? = nil,
        model: String? = nil,
        selectedModel: String? = nil
    ) -> AppLLMConnectionConfig {
        let idBase = providerMode == .openAICompatible ? "openai-compatible" : "claude"
        return addConnection(
            id: "\(idBase)-\(UUID().uuidString.prefix(8).lowercased())",
            providerMode: providerMode,
            name: name,
            baseURLString: baseURLString,
            model: model,
            selectedModel: selectedModel,
            hasAPIKey: false
        )
    }

    @discardableResult
    func addAuthenticatedConnection(
        id: String,
        providerMode: AppLLMProviderMode,
        name: String,
        baseURLString: String,
        model: String,
        selectedModel: String,
        apiKey: String? = nil,
        oauthTokens: AppLLMOAuthTokens? = nil
    ) throws -> AppLLMConnectionConfig {
        let connection = addConnection(
            id: id,
            providerMode: providerMode,
            name: name,
            baseURLString: baseURLString,
            model: model,
            selectedModel: selectedModel,
            hasAPIKey: apiKey?.isEmpty == false || oauthTokens != nil
        )
        try settingsRepository.save(
            settings: AppLLMSettings(connections: connectionConfigs, defaultConnectionID: connection.id),
            apiKey: apiKey
        )
        if let oauthTokens {
            try settingsRepository.saveOAuthTokens(oauthTokens, connectionID: connection.id)
        }
        loadSettings()
        onRuntimeSettingsChanged(true)
        Task { await reloadModelConnections() }
        return connection
    }

    @discardableResult
    func setupConnection(_ input: AppLLMConnectionSetupInput) async throws -> AppLLMConnectionConfig {
        isAddingConnection = true
        defer { isAddingConnection = false }
        let result = try await setupServiceFactory(settingsRepository).setupConnection(input)
        lastAddedConnectionID = result.connection.id
        lastAddedCapabilityEvidence = result.capabilityEvidence
        loadSettings()
        onConnectionSetup(result.connection)
        updateWelcomeState()
        onRuntimeSettingsChanged(true)
        await reloadModelConnections()
        let verifiedCount = result.capabilityEvidence.filter { $0.status == .verified }.count
        let suffix = result.capabilityEvidence.isEmpty ? "" : "；已发现 \(verifiedCount)/\(result.capabilityEvidence.count) 项可用能力。"
        settingsMessage = result.message + suffix
        healthCheckMessage = result.message + suffix
        errorMessage = nil
        return result.connection
    }

    func deleteConnection(_ connectionID: String) {
        guard connectionConfigs.count > 1 else {
            settingsMessage = "至少需要保留一个 AI 连接。"
            return
        }
        guard connectionConfigs.contains(where: { $0.id == connectionID }) else { return }
        let wasDefault = connectionID == defaultConnectionID
        connectionConfigs.removeAll { $0.id == connectionID }
        try? settingsRepository.clearAPIKey(connectionID: connectionID)
        try? capabilityEvidenceRepository.invalidate(connectionID: connectionID)
        if wasDefault {
            defaultConnectionID = connectionConfigs.first?.id ?? AppLLMSettings.default.defaultConnectionID
        }
        persistSettings(rebuildRuntime: true)
    }

    func capabilityDetailPresentation(for connectionID: String) -> AppProviderCapabilityDetailPresentation? {
        guard let connection = connectionConfigs.first(where: { $0.id == connectionID }) else { return nil }
        return capabilityEvidenceRepository.detailPresentation(for: connection)
    }

    func renameConnection(_ connectionID: String, name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              let index = connectionConfigs.firstIndex(where: { $0.id == connectionID }) else { return }
        var renamed = connectionConfigs[index]
        guard renamed.name != trimmedName else { return }
        renamed.name = trimmedName
        do {
            try settingsRepository.updateConnection(renamed)
            loadSettings()
            onRuntimeSettingsChanged(true)
            Task { await reloadModelConnections() }
            settingsMessage = "连接名称已更新。"
            healthCheckMessage = nil
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func persistSettings(rebuildRuntime: Bool) {
        do {
            let existing = (try? settingsRepository.loadSettings()) ?? .default
            var connections = connectionConfigs.isEmpty ? existing.connections : connectionConfigs
            let targetID = defaultConnectionID.isEmpty ? existing.defaultConnectionID : defaultConnectionID
            let updated = AppLLMConnectionConfig(
                id: targetID,
                name: connectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? (connections.first(where: { $0.id == targetID })?.name ?? (providerMode == .openAICompatible ? "OpenAI Compatible" : "Claude"))
                    : connectionName.trimmingCharacters(in: .whitespacesAndNewlines),
                providerMode: providerMode,
                baseURLString: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines),
                model: model.trimmingCharacters(in: .whitespacesAndNewlines),
                selectedModel: selectedModel.trimmingCharacters(in: .whitespacesAndNewlines),
                hasAPIKey: hasAPIKey,
                shouldFetchModelsList: shouldFetchModelsList
            )
            if let index = connections.firstIndex(where: { $0.id == targetID }) { connections[index] = updated }
            else { connections.append(updated) }
            let settings = AppLLMSettings(
                connections: connections,
                defaultConnectionID: targetID,
                defaultThinkingLevel: thinkingLevel
            )
            connectionConfigs = settings.connections
            defaultConnectionID = settings.defaultConnectionID
            let apiKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
            try settingsRepository.save(settings: settings, apiKey: apiKey.isEmpty ? nil : apiKey)
            loadSettings()
            updateWelcomeState()
            onRuntimeSettingsChanged(rebuildRuntime)
            settingsMessage = "模型设置已保存。"
            healthCheckMessage = nil
            errorMessage = nil
            Task { await reloadModelConnections() }
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func clearAPIKey() {
        do {
            try settingsRepository.clearAPIKey()
            loadSettings()
            updateWelcomeState()
            onRuntimeSettingsChanged(true)
            settingsMessage = "API Key 已清除。"
            healthCheckMessage = nil
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func testConnection() async {
        isTestingConnection = true
        defer { isTestingConnection = false }
        healthCheckMessage = nil
        let result = await healthChecker.testConnection()
        healthCheckMessage = result.message
        switch result.status {
        case .success: errorMessage = nil
        case .notConfigured, .failed: errorMessage = result.message
        }
    }

    private func addConnection(
        id: String,
        providerMode: AppLLMProviderMode,
        name: String?,
        baseURLString: String?,
        model: String?,
        selectedModel: String?,
        hasAPIKey: Bool,
        shouldFetchModelsList: Bool = true
    ) -> AppLLMConnectionConfig {
        let defaultName = providerMode == .openAICompatible ? "新 OpenAI Compatible 连接" : "新 Claude 连接"
        let defaultBaseURL = providerMode == .openAICompatible ? "https://api.openai.com/v1" : ""
        let defaultModel = providerMode == .openAICompatible ? "gpt-4o-mini" : "claude-sdk-default"
        let normalizedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? model! : defaultModel
        let normalizedSelected = selectedModel?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? selectedModel!
            : AppLLMConnectionConfig.firstModel(in: normalizedModel)
        let connection = AppLLMConnectionConfig(
            id: id,
            name: name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? name! : defaultName,
            providerMode: providerMode,
            baseURLString: baseURLString ?? defaultBaseURL,
            model: normalizedModel,
            selectedModel: normalizedSelected,
            hasAPIKey: hasAPIKey,
            shouldFetchModelsList: shouldFetchModelsList
        )
        connectionConfigs.removeAll { $0.id == connection.id }
        connectionConfigs.append(connection)
        defaultConnectionID = connection.id
        selectDefaultConnection(connection.id)
        return connection
    }
}

enum LLMProviderFactory {
    static func make(settingsRepository: AppLLMSettingsRepository) -> AnyLLMProvider {
        do {
            let settings = try settingsRepository.loadSettings()
            guard let connection = settings.defaultConnection else {
                return AnyLLMProvider { _, _ in throw OpenAICompatibleProviderError.missingAPIKey }
            }
            switch connection.providerMode {
            case .openAIResponses:
                guard let config = try settingsRepository.openAIResponsesConfig(connectionID: connection.id) else {
                    return AnyLLMProvider { _, _ in throw OpenAICompatibleProviderError.missingAPIKey }
                }
                return AnyLLMProvider(OpenAIResponsesProvider(config: config))
            case .anthropicMessages:
                guard let config = try settingsRepository.anthropicCompatibleConfig(connectionID: connection.id) else {
                    return AnyLLMProvider { _, _ in throw OpenAICompatibleProviderError.missingAPIKey }
                }
                return AnyLLMProvider(AnthropicCompatibleProvider(config: config))
            case .openAICompatible:
                guard let config = try settingsRepository.openAICompatibleConfig(connectionID: connection.id) else {
                    return AnyLLMProvider { _, _ in throw OpenAICompatibleProviderError.missingAPIKey }
                }
                return AnyLLMProvider(OpenAICompatibleProvider(config: config))
            }
        } catch {
            return AnyLLMProvider { _, _ in throw error }
        }
    }
}
