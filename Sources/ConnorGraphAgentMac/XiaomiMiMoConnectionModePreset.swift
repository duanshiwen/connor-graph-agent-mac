import Foundation

enum XiaomiMiMoConnectionModePreset: String, CaseIterable, Identifiable, Equatable {
    case payAsYouGo
    case tokenPlan

    var id: String { rawValue }

    var title: String {
        switch self {
        case .payAsYouGo: "按量付费 API"
        case .tokenPlan: "Token Plan"
        }
    }

    var subtitle: String {
        switch self {
        case .payAsYouGo:
            "适用于 sk-... API Key，按实际调用量计费。"
        case .tokenPlan:
            "适用于 tp-... API Key，需使用小米 Token Plan 专属 endpoint。"
        }
    }

    var openAIEndpoint: String {
        switch self {
        case .payAsYouGo: "https://api.xiaomimimo.com/v1"
        case .tokenPlan: "https://token-plan-cn.xiaomimimo.com/v1"
        }
    }

    var keyPlaceholder: String {
        keyPrefixHint
    }

    var keyPrefixHint: String {
        switch self {
        case .payAsYouGo: "sk-..."
        case .tokenPlan: "tp-..."
        }
    }

    func keyEndpointMismatchWarning(for apiKey: String) -> String? {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return nil }

        switch (self, trimmedKey.lowercased()) {
        case (.payAsYouGo, let key) where key.hasPrefix("tp-"):
            return "这个 Key 看起来是 Token Plan Key（tp-...）。请将使用方式切换为 Token Plan，Endpoint 应为 \(Self.tokenPlan.openAIEndpoint)。"
        case (.tokenPlan, let key) where key.hasPrefix("sk-"):
            return "这个 Key 看起来是按量付费 API Key（sk-...）。请将使用方式切换为按量付费 API，Endpoint 应为 \(Self.payAsYouGo.openAIEndpoint)。"
        default:
            return nil
        }
    }
}
