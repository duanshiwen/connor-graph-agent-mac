import Foundation
import ConnorGraphAgent

enum GitHubCopilotRequestHeaders {
    static func applying(to headers: [String: String], initiator: String = "user") -> [String: String] {
        var result = headers
        result["User-Agent"] = "GitHubCopilotChat/0.35.0"
        result["Editor-Version"] = "vscode/1.107.0"
        result["Editor-Plugin-Version"] = "copilot-chat/0.35.0"
        result["Copilot-Integration-Id"] = "vscode-chat"
        result["Openai-Intent"] = "conversation-edits"
        result["X-Initiator"] = initiator
        return result
    }
}

public struct GitHubCopilotTokenRefreshingAgentModelProvider: StreamingAgentModelProvider {
    public let modelID: String
    public let capabilities: AgentModelCapabilities

    private let connectionID: String
    private let settingsRepository: AppLLMSettingsRepository
    private let modelOverride: String?
    private let baseURLOverride: String?
    private let refreshSkew: TimeInterval
    private let now: @Sendable () -> Date
    private let refreshTokens: @Sendable (String) async throws -> AppLLMOAuthTokens
    private let makeProvider: @Sendable (OpenAICompatibleConfig) -> AnyAgentModelProvider

    public init(
        connectionID: String,
        modelID: String,
        capabilities: AgentModelCapabilities,
        settingsRepository: AppLLMSettingsRepository,
        modelOverride: String? = nil,
        baseURLOverride: String? = nil,
        refreshSkew: TimeInterval = 5 * 60,
        now: @escaping @Sendable () -> Date = Date.init,
        refreshTokens: @escaping @Sendable (String) async throws -> AppLLMOAuthTokens = { githubAccessToken in
            try await AppLLMOAuthService.shared.refreshGitHubCopilotTokens(githubAccessToken: githubAccessToken)
        },
        makeProvider: @escaping @Sendable (OpenAICompatibleConfig) -> AnyAgentModelProvider = { config in
            AnyAgentModelProvider(OpenAICompatibleProvider(config: config))
        }
    ) {
        self.connectionID = connectionID
        self.modelID = modelID
        self.capabilities = capabilities
        self.settingsRepository = settingsRepository
        self.modelOverride = modelOverride
        self.baseURLOverride = baseURLOverride
        self.refreshSkew = refreshSkew
        self.now = now
        self.refreshTokens = refreshTokens
        self.makeProvider = makeProvider
    }

    public func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse {
        let provider = try await makeCurrentProvider(initiator: initiator(for: request))
        return try await provider.complete(request)
    }

    public func streamComplete(_ request: AgentModelRequest) -> AsyncThrowingStream<AgentModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let provider = try await makeCurrentProvider(initiator: initiator(for: request))
                    for try await event in provider.streamComplete(request) {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func makeCurrentProvider(initiator: String) async throws -> AnyAgentModelProvider {
        try await refreshIfNeeded()
        guard var config = try settingsRepository.openAICompatibleConfig(
            connectionID: connectionID,
            modelOverride: modelOverride,
            baseURLOverride: baseURLOverride
        ) else {
            throw OpenAICompatibleProviderError.missingAPIKey
        }
        config.extraHeaders = GitHubCopilotRequestHeaders.applying(to: config.extraHeaders, initiator: initiator)
        return makeProvider(config)
    }

    private func initiator(for request: AgentModelRequest) -> String {
        request.messages.last?.role == .user ? "user" : "agent"
    }

    private func refreshIfNeeded() async throws {
        let settings = try settingsRepository.loadSettings()
        guard let connection = settings.connection(id: connectionID), connection.connectionKind == .githubCopilot else { return }
        guard let tokens = try settingsRepository.oauthTokens(for: connectionID) else { return }
        guard let expiresAt = tokens.expiresAt else { return }
        let refreshThresholdMilliseconds = (now().timeIntervalSince1970 + refreshSkew) * 1000
        guard expiresAt <= refreshThresholdMilliseconds else { return }
        guard let githubAccessToken = tokens.refreshToken, !githubAccessToken.isEmpty else { return }

        let refreshed = try await refreshTokens(githubAccessToken)
        try settingsRepository.saveOAuthTokens(refreshed, connectionID: connectionID)
        try settingsRepository.saveAPIKey(refreshed.accessToken, connectionID: connectionID)

        if baseURLOverride == nil, let derivedBaseURL = AppLLMOAuthService.copilotBaseURL(from: refreshed.accessToken), derivedBaseURL != connection.baseURLString {
            var updated = connection
            updated.baseURLString = derivedBaseURL
            try settingsRepository.updateConnection(updated)
        }
    }
}
