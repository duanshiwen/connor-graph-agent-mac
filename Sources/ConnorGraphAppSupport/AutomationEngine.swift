import Foundation
import ConnorGraphAgent
import ConnorGraphCore

public enum AutomationActionDisposition: String, Codable, Sendable, Equatable {
    case ready
    case pendingReview
    case blocked
}

public struct AutomationActionPlan: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var ruleID: String
    public var ruleName: String
    public var action: ProductOSAutomationAction
    public var disposition: AutomationActionDisposition
    public var reason: String

    public init(
        id: String = UUID().uuidString,
        ruleID: String,
        ruleName: String,
        action: ProductOSAutomationAction,
        disposition: AutomationActionDisposition,
        reason: String
    ) {
        self.id = id
        self.ruleID = ruleID
        self.ruleName = ruleName
        self.action = action
        self.disposition = disposition
        self.reason = reason
    }
}

public struct AutomationEngineRun: Sendable, Equatable {
    public var context: ProductOSAutomationEventContext
    public var matchedRules: [ProductOSAutomationRule]
    public var actionPlans: [AutomationActionPlan]
    public var records: [ProductOSAutomationTriggerRecord]
    public var events: [AgentEvent]

    public init(
        context: ProductOSAutomationEventContext,
        matchedRules: [ProductOSAutomationRule],
        actionPlans: [AutomationActionPlan],
        records: [ProductOSAutomationTriggerRecord],
        events: [AgentEvent]
    ) {
        self.context = context
        self.matchedRules = matchedRules
        self.actionPlans = actionPlans
        self.records = records
        self.events = events
    }
}

public struct AutomationEngine: Sendable {
    public var repository: AppProductOSAutomationRepository
    public var governanceConfig: AppSessionGovernanceConfig

    public init(repository: AppProductOSAutomationRepository, governanceConfig: AppSessionGovernanceConfig = .default) {
        self.repository = repository
        self.governanceConfig = governanceConfig
    }

    public func evaluate(context: ProductOSAutomationEventContext, runID: String? = nil) throws -> AutomationEngineRun {
        let config = try repository.loadOrCreateDefault(governanceConfig: governanceConfig)
        let matchedRules = config.rules.filter { $0.isEnabled && AppProductOSAutomationRepository.matches(rule: $0, context: context) }
        guard !matchedRules.isEmpty else {
            return AutomationEngineRun(context: context, matchedRules: [], actionPlans: [], records: [], events: [])
        }

        let records = try repository.evaluate(context: context, governanceConfig: governanceConfig)
        let actionPlans = matchedRules.flatMap { rule in
            rule.actions.map { action in
                AutomationActionPlan(
                    ruleID: rule.id,
                    ruleName: rule.name,
                    action: action,
                    disposition: rule.requiresReview ? .pendingReview : .ready,
                    reason: rule.requiresReview ? "Rule requires governed review before execution." : "Rule is eligible for safe execution."
                )
            }
        }
        let event = AgentEvent.automationTriggered(AgentAutomationPlaceholderEvent(
            runID: runID,
            sessionID: context.sessionID,
            trigger: context.triggerKind.rawValue,
            message: automationMessage(records: records, actionPlans: actionPlans)
        ))
        return AutomationEngineRun(context: context, matchedRules: matchedRules, actionPlans: actionPlans, records: records, events: [event])
    }

    private func automationMessage(records: [ProductOSAutomationTriggerRecord], actionPlans: [AutomationActionPlan]) -> String {
        let ruleNames = records.map(\.ruleName).joined(separator: ", ")
        let pending = actionPlans.filter { $0.disposition == .pendingReview }.count
        let ready = actionPlans.filter { $0.disposition == .ready }.count
        return "Automation matched: \(ruleNames). Actions ready: \(ready), pending review: \(pending)."
    }
}
