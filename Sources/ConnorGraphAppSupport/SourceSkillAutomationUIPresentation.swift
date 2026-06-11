import Foundation
import ConnorGraphAgent
import ConnorGraphCore

public struct SourceRuntimeUISummary: Codable, Sendable, Equatable {
    public var totalCount: Int
    public var enabledCount: Int
    public var needsCredentialCount: Int

    public init(totalCount: Int, enabledCount: Int, needsCredentialCount: Int) {
        self.totalCount = totalCount
        self.enabledCount = enabledCount
        self.needsCredentialCount = needsCredentialCount
    }
}

public struct SourceRuntimeUICard: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var statusLabel: String
    public var transportLabel: String
    public var credentialLabel: String
    public var capabilityLabels: [String]
    public var toolPrefixLabel: String
    public var graphPolicyLabel: String
    public var tags: [String]
    public var severity: AgentEventPresentationSeverity

    public init(
        id: String,
        title: String,
        statusLabel: String,
        transportLabel: String,
        credentialLabel: String,
        capabilityLabels: [String],
        toolPrefixLabel: String,
        graphPolicyLabel: String,
        tags: [String],
        severity: AgentEventPresentationSeverity
    ) {
        self.id = id
        self.title = title
        self.statusLabel = statusLabel
        self.transportLabel = transportLabel
        self.credentialLabel = credentialLabel
        self.capabilityLabels = capabilityLabels
        self.toolPrefixLabel = toolPrefixLabel
        self.graphPolicyLabel = graphPolicyLabel
        self.tags = tags
        self.severity = severity
    }
}

public struct SourceRuntimeUIPresentation: Codable, Sendable, Equatable {
    public var summary: SourceRuntimeUISummary
    public var cards: [SourceRuntimeUICard]

    public init(summary: SourceRuntimeUISummary, cards: [SourceRuntimeUICard]) {
        self.summary = summary
        self.cards = cards
    }

    public static func build(sources: [MCPSourceRuntimeConfiguration]) -> SourceRuntimeUIPresentation {
        let cards = sources
            .sorted { lhs, rhs in lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending }
            .map(SourceRuntimeUICard.init(configuration:))
        return SourceRuntimeUIPresentation(
            summary: SourceRuntimeUISummary(
                totalCount: sources.count,
                enabledCount: sources.filter { $0.status == .enabled }.count,
                needsCredentialCount: sources.filter { $0.credentialRequirement != .none }.count
            ),
            cards: cards
        )
    }
}

private extension SourceRuntimeUICard {
    init(configuration: MCPSourceRuntimeConfiguration) {
        self.init(
            id: configuration.sourceID,
            title: configuration.displayName,
            statusLabel: configuration.status.rawValue,
            transportLabel: configuration.transport.uiLabel,
            credentialLabel: configuration.credentialRequirement.rawValue,
            capabilityLabels: configuration.allowedCapabilities.map(\.rawValue),
            toolPrefixLabel: configuration.toolNamePrefix,
            graphPolicyLabel: "ingest \(configuration.graphIngestionEnabled ? "on" : "off") · \(configuration.graphWritePolicy.rawValue)",
            tags: configuration.tags,
            severity: configuration.status.sourceUISeverity
        )
    }
}

private extension MCPSourceRuntimeTransport {
    var uiLabel: String {
        switch self {
        case .stdio(let command, let arguments):
            return "stdio · \(([command] + arguments).joined(separator: " "))"
        case .http(let url):
            return "http · \(url.absoluteString)"
        }
    }
}

public struct SkillRuntimeUISummary: Codable, Sendable, Equatable {
    public var totalCount: Int
    public var projectScopedCount: Int
    public var requiresSourceCount: Int

    public init(totalCount: Int, projectScopedCount: Int, requiresSourceCount: Int) {
        self.totalCount = totalCount
        self.projectScopedCount = projectScopedCount
        self.requiresSourceCount = requiresSourceCount
    }
}

public struct SkillRuntimeUICard: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var description: String
    public var scopeLabel: String
    public var triggerLabels: [String]
    public var capabilityLabels: [String]
    public var requiredSourceLabels: [String]
    public var globLabels: [String]
    public var graphPolicyLabel: String
    public var manifestPath: String
    public var severity: AgentEventPresentationSeverity

    public init(
        id: String,
        title: String,
        description: String,
        scopeLabel: String,
        triggerLabels: [String],
        capabilityLabels: [String],
        requiredSourceLabels: [String],
        globLabels: [String],
        graphPolicyLabel: String,
        manifestPath: String,
        severity: AgentEventPresentationSeverity
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.scopeLabel = scopeLabel
        self.triggerLabels = triggerLabels
        self.capabilityLabels = capabilityLabels
        self.requiredSourceLabels = requiredSourceLabels
        self.globLabels = globLabels
        self.graphPolicyLabel = graphPolicyLabel
        self.manifestPath = manifestPath
        self.severity = severity
    }
}

public struct SkillRuntimeUIPresentation: Codable, Sendable, Equatable {
    public var summary: SkillRuntimeUISummary
    public var cards: [SkillRuntimeUICard]

    public init(summary: SkillRuntimeUISummary, cards: [SkillRuntimeUICard]) {
        self.summary = summary
        self.cards = cards
    }

    public static func build(skills: [SkillRuntimeDefinition]) -> SkillRuntimeUIPresentation {
        let cards = skills
            .sorted { $0.manifest.name.localizedCaseInsensitiveCompare($1.manifest.name) == .orderedAscending }
            .map(SkillRuntimeUICard.init(definition:))
        return SkillRuntimeUIPresentation(
            summary: SkillRuntimeUISummary(
                totalCount: skills.count,
                projectScopedCount: skills.filter { $0.scope == .project }.count,
                requiresSourceCount: skills.filter { !$0.manifest.requiredSources.isEmpty }.count
            ),
            cards: cards
        )
    }
}

private extension SkillRuntimeUICard {
    init(definition: SkillRuntimeDefinition) {
        self.init(
            id: definition.slug,
            title: definition.manifest.name,
            description: definition.manifest.description,
            scopeLabel: definition.scope.rawValue,
            triggerLabels: definition.manifest.triggers.map(\.rawValue),
            capabilityLabels: definition.manifest.requiredCapabilities.map(\.rawValue),
            requiredSourceLabels: definition.manifest.requiredSources,
            globLabels: definition.manifest.globs,
            graphPolicyLabel: definition.manifest.graphContextPolicy.rawValue,
            manifestPath: definition.skillURL.path,
            severity: definition.manifest.skillUISeverity
        )
    }
}

public struct AutomationRuntimeUISummary: Codable, Sendable, Equatable {
    public var totalRuleCount: Int
    public var enabledRuleCount: Int
    public var pendingReviewRuleCount: Int
    public var recentTriggerCount: Int
    public var historyCount: Int

    public init(totalRuleCount: Int, enabledRuleCount: Int, pendingReviewRuleCount: Int, recentTriggerCount: Int, historyCount: Int) {
        self.totalRuleCount = totalRuleCount
        self.enabledRuleCount = enabledRuleCount
        self.pendingReviewRuleCount = pendingReviewRuleCount
        self.recentTriggerCount = recentTriggerCount
        self.historyCount = historyCount
    }
}

public struct AutomationRuntimeUICard: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var detail: String
    public var severity: AgentEventPresentationSeverity
    public var dispositionLabel: String

    public init(id: String, title: String, subtitle: String, detail: String, severity: AgentEventPresentationSeverity, dispositionLabel: String) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
        self.severity = severity
        self.dispositionLabel = dispositionLabel
    }
}

public struct AutomationRuntimeUIPresentation: Codable, Sendable, Equatable {
    public var summary: AutomationRuntimeUISummary
    public var ruleCards: [AutomationRuntimeUICard]
    public var triggerCards: [AutomationRuntimeUICard]
    public var historyCards: [AutomationRuntimeUICard]

    public init(summary: AutomationRuntimeUISummary, ruleCards: [AutomationRuntimeUICard], triggerCards: [AutomationRuntimeUICard], historyCards: [AutomationRuntimeUICard]) {
        self.summary = summary
        self.ruleCards = ruleCards
        self.triggerCards = triggerCards
        self.historyCards = historyCards
    }

    public static func build(
        config: ProductOSAutomationConfig,
        triggers: [ProductOSAutomationTriggerRecord],
        history: [ProductOSAutomationExecutionHistoryRecord]
    ) -> AutomationRuntimeUIPresentation {
        AutomationRuntimeUIPresentation(
            summary: AutomationRuntimeUISummary(
                totalRuleCount: config.rules.count,
                enabledRuleCount: config.rules.filter(\.isEnabled).count,
                pendingReviewRuleCount: config.rules.filter(\.requiresReview).count,
                recentTriggerCount: triggers.count,
                historyCount: history.count
            ),
            ruleCards: config.rules.map(AutomationRuntimeUICard.init(rule:)),
            triggerCards: triggers.map(AutomationRuntimeUICard.init(trigger:)),
            historyCards: history.map(AutomationRuntimeUICard.init(history:))
        )
    }
}

private extension AutomationRuntimeUICard {
    init(rule: ProductOSAutomationRule) {
        let disposition = rule.requiresReview ? "pendingReview" : "ready"
        let actionSummary = rule.actions.map { "\($0.kind.rawValue): \($0.message)" }.joined(separator: " · ")
        self.init(
            id: rule.id,
            title: rule.name,
            subtitle: "\(rule.trigger.kind.rawValue) · \(rule.isEnabled ? "enabled" : "disabled")",
            detail: actionSummary,
            severity: !rule.isEnabled || rule.requiresReview ? .warning : .success,
            dispositionLabel: disposition
        )
    }

    init(trigger: ProductOSAutomationTriggerRecord) {
        self.init(
            id: trigger.id,
            title: trigger.ruleName,
            subtitle: "\(trigger.trigger.rawValue) · session \(trigger.sessionID)",
            detail: trigger.actionSummaries.joined(separator: " · "),
            severity: trigger.requiresReview ? .warning : .info,
            dispositionLabel: trigger.requiresReview ? "pendingReview" : "ready"
        )
    }

    init(history: ProductOSAutomationExecutionHistoryRecord) {
        self.init(
            id: history.id,
            title: "\(history.outcome.rawValue) · \(history.trigger.rawValue)",
            subtitle: "session \(history.sessionID) · rules \(history.ruleIDs.joined(separator: ","))",
            detail: "applied \(history.appliedActionCount) · skipped \(history.skippedActionCount) · events \(history.eventCount) · \(history.message)",
            severity: history.outcome.automationUISeverity,
            dispositionLabel: history.outcome.rawValue
        )
    }
}

private extension ProductOSAutomationExecutionOutcome {
    var automationUISeverity: AgentEventPresentationSeverity {
        switch self {
        case .completed: .success
        case .partial, .skipped: .warning
        case .failed: .error
        }
    }
}

private extension SkillRuntimeManifest {
    var skillUISeverity: AgentEventPresentationSeverity {
        if graphContextPolicy == .readOnly && requiredSources.isEmpty { return .success }
        if graphContextPolicy == .readOnly { return .info }
        return .warning
    }
}

private extension ProductOSRegistryEntryStatus {
    var sourceUISeverity: AgentEventPresentationSeverity {
        switch self {
        case .enabled: .success
        case .draft, .needsReview: .warning
        case .disabled, .deprecated: .info
        }
    }
}
