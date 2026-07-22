import Foundation

enum AIConnectionUsageMode: String, CaseIterable, Identifiable, Equatable {
    case payAsYouGo
    case subscriptionPlan

    var id: String { rawValue }

    var title: String {
        switch self {
        case .payAsYouGo: "按量付费 API"
        case .subscriptionPlan: "订阅套餐"
        }
    }
}

struct AIConnectionSubscriptionPlanPreset: Equatable {
    var title: String
    var subtitle: String
    var endpoint: String
    var defaultModel: String
    var supportedModels: [String]
    var keyPlaceholder: String
    var purchaseURLString: String
    var managementURLString: String
    var restrictionNotice: String?

    var availableModels: [String] {
        if !supportedModels.isEmpty { return supportedModels }
        return defaultModel.isEmpty ? [] : [defaultModel]
    }
}
