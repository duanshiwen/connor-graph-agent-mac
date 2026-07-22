import Foundation

enum KimiConnectionModePreset: String, CaseIterable, Identifiable, Equatable {
    case payAsYouGo
    case codingPlan

    var id: String { rawValue }

    var title: String {
        switch self {
        case .payAsYouGo: "按量付费 API"
        case .codingPlan: "Coding Plan"
        }
    }

    var subtitle: String {
        switch self {
        case .payAsYouGo:
            "适用于 Kimi 开放平台 API Key，按实际调用量计费。"
        case .codingPlan:
            "适用于 Kimi Code 会员 API Key，使用 Coding Plan 专属 endpoint 和会员额度。"
        }
    }

    var openAIEndpoint: String {
        switch self {
        case .payAsYouGo: "https://api.moonshot.cn/v1"
        case .codingPlan: "https://api.kimi.com/coding/v1"
        }
    }

    var defaultModel: String {
        switch self {
        case .payAsYouGo: "kimi-k2.6"
        case .codingPlan: "kimi-for-coding"
        }
    }

    var availableModels: [String] {
        switch self {
        case .payAsYouGo:
            [
                "kimi-k2.7-code", "kimi-k2.7-code-highspeed", "kimi-k2.6", "kimi-k2.5",
                "moonshot-v1-8k", "moonshot-v1-32k", "moonshot-v1-128k",
                "moonshot-v1-8k-vision-preview", "moonshot-v1-32k-vision-preview", "moonshot-v1-128k-vision-preview"
            ]
        case .codingPlan:
            ["kimi-for-coding", "kimi-for-coding-highspeed", "k3"]
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .payAsYouGo: "sk-..."
        case .codingPlan: "Kimi Code API Key"
        }
    }

    var connectionName: String {
        switch self {
        case .payAsYouGo: "Moonshot · Kimi"
        case .codingPlan: "Kimi Coding Plan"
        }
    }
}
