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
            case .governedClaudeSidecar:
                let path = settings.sidecarExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !path.isEmpty else {
                    return AppLLMProviderHealthCheckResult(status: .notConfigured, message: "Governed Claude Sidecar 缺少 executable path。")
                }
                guard settings.sidecarPermissionMode != .allowAll else {
                    return AppLLMProviderHealthCheckResult(status: .failed, message: "Governed Claude Sidecar 不允许 allowAll 权限模式。")
                }
                return AppLLMProviderHealthCheckResult(status: .success, message: "Governed Claude Sidecar 配置可用；实际 SDK 登录和依赖由 sidecar 运行时验证。")
            case .openAICompatible:
                guard let config = try settingsRepository.openAICompatibleConfig() else {
                    return AppLLMProviderHealthCheckResult(status: .notConfigured, message: "OpenAI 兼容模型提供方缺少 API Key。")
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
            return "OpenAI 兼容模型提供方缺少 API Key。"
        case let OpenAICompatibleProviderError.invalidBaseURL(value):
            return "Base URL 无效：\(value)"
        case OpenAICompatibleProviderError.invalidResponse:
            return "模型提供方返回了无效响应。"
        case let OpenAICompatibleProviderError.httpStatus(code):
            return "模型提供方返回 HTTP 状态码 \(code)。"
        case OpenAICompatibleProviderError.missingAssistantMessage:
            return "模型提供方响应中没有助手消息。"
        default:
            return String(describing: error)
        }
    }
}
