import Foundation
import ConnorGraphCore

public struct SkillAutomationTriggerPlan: Codable, Sendable, Equatable, Hashable {
    public var ruleID: String
    public var skillSlug: String
    public var arguments: String
    public var requiresReview: Bool
    public var reason: String

    public init(ruleID: String, skillSlug: String, arguments: String = "", requiresReview: Bool, reason: String) {
        self.ruleID = ruleID
        self.skillSlug = skillSlug
        self.arguments = arguments
        self.requiresReview = requiresReview
        self.reason = reason
    }
}

public struct SkillAutomationIntegrationService: Sendable {
    public init() {}

    public func triggerPlans(config: ProductOSAutomationConfig) -> [SkillAutomationTriggerPlan] {
        config.rules.flatMap { rule in
            rule.actions.compactMap { action in
                guard action.kind == .triggerSkill, let skillID = action.skillID else { return nil }
                return SkillAutomationTriggerPlan(
                    ruleID: rule.id,
                    skillSlug: skillID,
                    arguments: action.message,
                    requiresReview: rule.requiresReview,
                    reason: rule.requiresReview ? "Automation-triggered skills require review before execution." : "Automation can trigger skill through Connor governed runtime."
                )
            }
        }
    }
}

public struct SkillGraphContextRequest: Codable, Sendable, Equatable, Hashable {
    public var skillSlug: String
    public var policy: AgentPermissionMode
    public var domains: [String]
    public var workObjectID: String?
    public var canWriteDirectly: Bool

    public init(skillSlug: String, policy: AgentPermissionMode, domains: [String] = [], workObjectID: String? = nil, canWriteDirectly: Bool = false) {
        self.skillSlug = skillSlug
        self.policy = policy
        self.domains = domains
        self.workObjectID = workObjectID
        self.canWriteDirectly = canWriteDirectly
    }
}

public struct SkillGraphMemoryIntegrationService: Sendable {
    public init() {}

    public func graphContextRequest(for package: SkillPackage, domains: [String] = [], workObjectID: String? = nil) -> SkillGraphContextRequest {
        SkillGraphContextRequest(
            skillSlug: package.slug.rawValue,
            policy: package.manifest.connor.graphContextPolicy,
            domains: domains,
            workObjectID: workObjectID,
            canWriteDirectly: false
        )
    }
}
