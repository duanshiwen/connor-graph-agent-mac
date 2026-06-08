import Foundation
import ConnorGraphAgent

public enum AppLLMProviderHealthCheckStatus: Sendable, Equatable {
    case notConfigured
    case success
    case failed
}

public struct AppLLMProviderHealthCheckResult: Sendable, Equatable {
    public var status: AppLLMProviderHealthCheckStatus
    public var message: String

    public init(status: AppLLMProviderHealthCheckStatus, message: String) {
        self.status = status
        self.message = message
    }
}

public typealias OpenAICompatibleHealthCheck = @Sendable (OpenAICompatibleConfig) async throws -> LLMProviderHealthCheckResult

public struct AppLLMProviderHealthChecker: Sendable {
    public var settingsRepository: AppLLMSettingsRepository
    public var openAICompatibleHealthCheck: OpenAICompatibleHealthCheck

    public init(
        settingsRepository: AppLLMSettingsRepository = AppLLMSettingsRepository(),
        openAICompatibleHealthCheck: @escaping OpenAICompatibleHealthCheck = { config in
            try await OpenAICompatibleProvider(config: config).healthCheck()
        }
    ) {
        self.settingsRepository = settingsRepository
        self.openAICompatibleHealthCheck = openAICompatibleHealthCheck
    }

    public func testConnection() async -> AppLLMProviderHealthCheckResult {
        do {
            let settings = try settingsRepository.loadSettings()
            switch settings.providerMode {
            case .stub:
                return AppLLMProviderHealthCheckResult(status: .success, message: "Stub provider is available.")
            case .openAICompatible:
                guard let config = try settingsRepository.openAICompatibleConfig() else {
                    return AppLLMProviderHealthCheckResult(status: .notConfigured, message: "OpenAI-compatible provider is missing an API key.")
                }
                let result = try await openAICompatibleHealthCheck(config)
                return AppLLMProviderHealthCheckResult(
                    status: result.ok ? .success : .failed,
                    message: result.message
                )
            }
        } catch {
            return AppLLMProviderHealthCheckResult(status: .failed, message: Self.safeMessage(for: error))
        }
    }

    private static func safeMessage(for error: Error) -> String {
        switch error {
        case OpenAICompatibleProviderError.missingAPIKey:
            return "OpenAI-compatible provider is missing an API key."
        case let OpenAICompatibleProviderError.invalidBaseURL(value):
            return "Invalid base URL: \(value)"
        case OpenAICompatibleProviderError.invalidResponse:
            return "Provider returned an invalid response."
        case let OpenAICompatibleProviderError.httpStatus(code):
            return "Provider returned HTTP status \(code)."
        case OpenAICompatibleProviderError.missingAssistantMessage:
            return "Provider response did not include an assistant message."
        default:
            return String(describing: error)
        }
    }
}
