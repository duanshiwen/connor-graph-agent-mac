import Foundation
import ConnorGraphAgent
import ConnorGraphAppSupport

@MainActor
extension AppViewModel {
static func makeLLMProvider(settingsRepository: AppLLMSettingsRepository) -> AnyLLMProvider {
    do {
        let settings = try settingsRepository.loadSettings()
        guard let connection = settings.defaultConnection else {
                return AnyLLMProvider { _, _ in
                    throw OpenAICompatibleProviderError.missingAPIKey
                }
            }
        switch connection.providerMode {
        case .openAIResponses:
            guard let config = try settingsRepository.openAIResponsesConfig(connectionID: connection.id) else {
                return AnyLLMProvider { _, _ in
                    throw OpenAICompatibleProviderError.missingAPIKey
                }
            }
            return AnyLLMProvider(OpenAIResponsesProvider(config: config))
        case .anthropicMessages:
            guard let config = try settingsRepository.anthropicCompatibleConfig(connectionID: connection.id) else {
                return AnyLLMProvider { _, _ in
                    throw OpenAICompatibleProviderError.missingAPIKey
                }
            }
            return AnyLLMProvider(AnthropicCompatibleProvider(config: config))
        case .openAICompatible:
            guard let config = try settingsRepository.openAICompatibleConfig(connectionID: connection.id) else {
                return AnyLLMProvider { _, _ in
                    throw OpenAICompatibleProviderError.missingAPIKey
                }
            }
            return AnyLLMProvider(OpenAICompatibleProvider(config: config))
        }
    } catch {
        return AnyLLMProvider { _, _ in throw error }
    }
}
}
