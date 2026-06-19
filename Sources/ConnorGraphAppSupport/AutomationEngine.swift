import Foundation
import ConnorGraphAgent
import ConnorGraphCore

// LEGACY COMPATIBILITY SHIM:
// The formal task lifecycle/control plane is TaskManagementStack. This engine
// remains temporarily for legacy session automation call sites and should not be
// extended as a standalone background-task architecture.

public enum AutomationEngineError: Error, Sendable, Equatable, CustomStringConvertible {
    case rateLimited(String)

    public var description: String {
        switch self {
        case .rateLimited(let key): "rateLimited: \(key)"
        }
    }
}

public final class AutomationRateLimiter: @unchecked Sendable {
    private let maxEvents: Int
    private let interval: TimeInterval
    private var buckets: [String: [Date]]
    private let lock = NSLock()

    public init(maxEvents: Int = 10, interval: TimeInterval = 60) {
        self.maxEvents = max(1, maxEvents)
        self.interval = max(1, interval)
        self.buckets = [:]
    }

    public func allow(key: String, now: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let cutoff = now.addingTimeInterval(-interval)
        var events = buckets[key, default: []].filter { $0 > cutoff }
        guard events.count < maxEvents else {
            buckets[key] = events
            return false
        }
        events.append(now)
        buckets[key] = events
        return true
    }
}

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
    public var rateLimiter: AutomationRateLimiter?

    public init(
        repository: AppProductOSAutomationRepository,
        governanceConfig: AppSessionGovernanceConfig = .default,
        rateLimiter: AutomationRateLimiter? = nil
    ) {
        self.repository = repository
        self.governanceConfig = governanceConfig
        self.rateLimiter = rateLimiter
    }

    public func evaluate(context: ProductOSAutomationEventContext, runID: String? = nil, now: Date = Date()) throws -> AutomationEngineRun {
        let config = try repository.loadOrCreateDefault(governanceConfig: governanceConfig)
        let matchedRules = config.rules.filter { $0.isEnabled && AppProductOSAutomationRepository.matches(rule: $0, context: context) }
        guard !matchedRules.isEmpty else {
             return AutomationEngineRun(context: context, matchedRules: [], actionPlans: [], records: [], events: [])
         }

        let limiterKey = rateLimitKey(context: context)
        if let rateLimiter, !rateLimiter.allow(key: limiterKey, now: now) {
            throw AutomationEngineError.rateLimited(limiterKey)
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

        let outcome: ProductOSAutomationExecutionOutcome
        if appliedPlans.isEmpty && !skippedPlans.isEmpty {
            outcome = .skipped
        } else if !appliedPlans.isEmpty && !skippedPlans.isEmpty {
            outcome = .partial
        } else {
            outcome = .completed
        }
        try repository.appendExecutionHistory(ProductOSAutomationExecutionHistoryRecord(
            sessionID: run.context.sessionID,
            trigger: run.context.triggerKind,
            ruleIDs: run.matchedRules.map(\.id),
            appliedActionCount: appliedPlans.count,
            skippedActionCount: skippedPlans.count,
            eventCount: events.count,
            outcome: outcome,
            message: "Applied \(appliedPlans.count) automation action(s), skipped \(skippedPlans.count)."
        ))

        return AutomationExecutionResult(appliedPlans: appliedPlans, skippedPlans: skippedPlans, events: events)
    }

    private func blocked(_ plan: AutomationActionPlan, reason: String) -> AutomationActionPlan {
        var blockedPlan = plan
        blockedPlan.disposition = .blocked
        blockedPlan.reason = reason
        return blockedPlan
    }

    private func rateLimitKey(context: ProductOSAutomationEventContext) -> String {
        [
            context.triggerKind.rawValue,
            context.sessionID,
            context.status?.rawValue ?? "",
            context.labelID ?? "",
            context.registryEntryID ?? ""
        ].joined(separator: "|")
    }

    private func automationMessage(records: [ProductOSAutomationTriggerRecord], actionPlans: [AutomationActionPlan]) -> String {
        let ruleNames = records.map(\.ruleName).joined(separator: ", ")
        let pending = actionPlans.filter { $0.disposition == .pendingReview }.count
        let ready = actionPlans.filter { $0.disposition == .ready }.count
        return "Automation matched: \(ruleNames). Actions ready: \(ready), pending review: \(pending)."
    }
}
