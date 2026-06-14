import Foundation
import ConnorGraphAgent
import ConnorGraphAppSupport

@MainActor
extension AppViewModel {
static func makeLLMProvider(settingsRepository: AppLLMSettingsRepository) -> AnyLLMProvider {
    do {
        let settings = try settingsRepository.loadSettings()
        switch settings.providerMode {
        case .governedClaudeSidecar:
            return AnyLLMProvider { _, _ in
                throw AppGraphAgentRuntimeFactoryError.sidecarRequiresSessionManager
            }
        case .openAICompatible:
            guard let config = try settingsRepository.openAICompatibleConfig() else {
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
