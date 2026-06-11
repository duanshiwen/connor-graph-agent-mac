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

public struct AutomationExecutionResult: Sendable, Equatable {
    public var appliedPlans: [AutomationActionPlan]
    public var skippedPlans: [AutomationActionPlan]
    public var events: [AgentEvent]

    public init(appliedPlans: [AutomationActionPlan], skippedPlans: [AutomationActionPlan], events: [AgentEvent]) {
        self.appliedPlans = appliedPlans
        self.skippedPlans = skippedPlans
        self.events = events
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

    public func execute(run: AutomationEngineRun, sessionRepository: AppChatSessionRepository, runID: String? = nil) throws -> AutomationExecutionResult {
        var appliedPlans: [AutomationActionPlan] = []
        var skippedPlans: [AutomationActionPlan] = []
        var events = run.events

        for plan in run.actionPlans {
            guard plan.disposition == .ready else {
                skippedPlans.append(plan)
                continue
            }

            switch plan.action.kind {
            case .appendTimelineEvent:
                events.append(.automationTriggered(AgentAutomationPlaceholderEvent(
                    runID: runID,
                    sessionID: run.context.sessionID,
                    trigger: run.context.triggerKind.rawValue,
                    message: plan.action.message
                )))
                appliedPlans.append(plan)

            case .setSessionStatus:
                guard let status = plan.action.status else {
                    skippedPlans.append(blocked(plan, reason: "setSessionStatus requires a status."))
                    continue
                }
                _ = try sessionRepository.setStatus(sessionID: run.context.sessionID, status: status)
                events.append(.sessionStatusChanged(AgentSessionGovernanceEvent(
                    runID: runID,
                    sessionID: run.context.sessionID,
                    message: plan.action.message,
                    status: status
                )))
                appliedPlans.append(plan)

            case .addSessionLabel:
                guard let label = plan.action.label else {
                    skippedPlans.append(blocked(plan, reason: "addSessionLabel requires a label."))
                    continue
                }
                let session = try sessionRepository.updateGovernance(sessionID: run.context.sessionID) { governance in
                    if !governance.labels.contains(where: { $0.id == label.id }) {
                        governance.labels.append(label)
                    }
                }
                events.append(.sessionLabelsChanged(AgentSessionGovernanceEvent(
                    runID: runID,
                    sessionID: run.context.sessionID,
                    message: plan.action.message,
                    labels: session.governance.labels
                )))
                appliedPlans.append(plan)

            case .removeSessionLabel:
                guard let label = plan.action.label else {
                    skippedPlans.append(blocked(plan, reason: "removeSessionLabel requires a label."))
                    continue
                }
                let session = try sessionRepository.updateGovernance(sessionID: run.context.sessionID) { governance in
                    governance.labels.removeAll { $0.id == label.id }
                }
                events.append(.sessionLabelsChanged(AgentSessionGovernanceEvent(
                    runID: runID,
                    sessionID: run.context.sessionID,
                    message: plan.action.message,
                    labels: session.governance.labels
                )))
                appliedPlans.append(plan)

            case .triggerSkill:
                events.append(.automationTriggered(AgentAutomationPlaceholderEvent(
                    runID: runID,
                    sessionID: run.context.sessionID,
                    trigger: "triggerSkill",
                    message: "Skill trigger requested: \(plan.action.skillID ?? "unknown"). \(plan.action.message)"
                )))
                appliedPlans.append(plan)

            case .createArtifactPlaceholder:
                events.append(.artifactCreated(AgentSessionArtifactEvent(
                    runID: runID,
                    sessionID: run.context.sessionID,
                    artifactKind: "automation-placeholder",
                    path: "automation://\(plan.id)",
                    message: plan.action.message
                )))
                appliedPlans.append(plan)
            }
        }

        return AutomationExecutionResult(appliedPlans: appliedPlans, skippedPlans: skippedPlans, events: events)
    }

    private func blocked(_ plan: AutomationActionPlan, reason: String) -> AutomationActionPlan {
        var blockedPlan = plan
        blockedPlan.disposition = .blocked
        blockedPlan.reason = reason
        return blockedPlan
    }

    private func automationMessage(records: [ProductOSAutomationTriggerRecord], actionPlans: [AutomationActionPlan]) -> String {
        let ruleNames = records.map(\.ruleName).joined(separator: ", ")
        let pending = actionPlans.filter { $0.disposition == .pendingReview }.count
        let ready = actionPlans.filter { $0.disposition == .ready }.count
        return "Automation matched: \(ruleNames). Actions ready: \(ready), pending review: \(pending)."
    }
}
