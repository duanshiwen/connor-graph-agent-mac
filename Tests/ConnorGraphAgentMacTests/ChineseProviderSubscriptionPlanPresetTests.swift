import Testing
@testable import ConnorGraphAgentMac

@Suite("Chinese provider subscription plan presets")
struct ChineseProviderSubscriptionPlanPresetTests {
    private func preset(_ id: String) -> AIConnectionProviderPreset {
        AIConnectionProviderPreset.chinaProviderPresets.first { $0.id == id }!
    }

    @Test func exposesOnlyOfficiallyConfirmedProviderPlans() {
        #expect(preset("deepseek").subscriptionPlan == nil)
        for id in ["xiaomi-mimo", "qwen", "doubao", "moonshot", "zhipu", "minimax", "stepfun", "zai"] {
            #expect(preset(id).subscriptionPlan != nil)
        }
    }

    @Test func usesOfficialDedicatedOpenAIEndpoints() {
        #expect(preset("xiaomi-mimo").subscriptionPlan?.endpoint == "https://token-plan-cn.xiaomimimo.com/v1")
        #expect(preset("qwen").subscriptionPlan?.endpoint == "https://coding.dashscope.aliyuncs.com/v1")
        #expect(preset("doubao").subscriptionPlan?.endpoint == "https://ark.cn-beijing.volces.com/api/coding/v3")
        #expect(preset("moonshot").subscriptionPlan?.endpoint == "https://api.kimi.com/coding/v1")
        #expect(preset("zhipu").subscriptionPlan?.endpoint == "https://open.bigmodel.cn/api/coding/paas/v4")
        #expect(preset("minimax").subscriptionPlan?.endpoint == "https://api.minimaxi.com/v1")
        #expect(preset("stepfun").subscriptionPlan?.endpoint == "https://api.stepfun.com/step_plan/v1")
        #expect(preset("zai").subscriptionPlan?.endpoint == "https://api.z.ai/api/coding/paas/v4")
    }

    @Test func exposesOfficialPurchaseAndManagementLinks() {
        for id in ["xiaomi-mimo", "qwen", "doubao", "moonshot", "zhipu", "minimax", "stepfun", "zai"] {
            let plan = preset(id).subscriptionPlan!
            #expect(plan.purchaseURLString.hasPrefix("https://"))
            #expect(plan.managementURLString.hasPrefix("https://"))
            #expect(plan.availableModels.isEmpty == false)
        }
    }

    @Test func preservesKnownDedicatedKeyPrefixes() {
        #expect(preset("xiaomi-mimo").subscriptionPlan?.keyPlaceholder == "tp-...")
        #expect(preset("qwen").subscriptionPlan?.keyPlaceholder == "sk-sp-...")
        #expect(preset("minimax").subscriptionPlan?.keyPlaceholder == "sk-cp-...")
    }
}
