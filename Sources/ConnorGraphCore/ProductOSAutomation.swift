import Foundation

// LEGACY COMPATIBILITY SHIM:
// The formal Connor background-task architecture is now TaskManagementDomain.
// These ProductOSAutomation types remain temporarily for runtime readiness
// and UI compatibility until those call sites are migrated to the
// abstract Task Management Stack.

public enum ProductOSAutomationTriggerKind: String, Codable, Sendable, Equatable, CaseIterable {
    case sessionStatusChanged
    case sessionLabelAdded
    case sessionLabelRemoved
    case sessionArchived
    case sessionRestored
    case sourceRegistryChanged
    case skillRegistryChanged
}

public struct ProductOSAutomationTrigger: Codable, Sendable, Equatable {
    public var kind: ProductOSAutomationTriggerKind
    public var status: AgentSessionStatus?
    public var labelID: String?
    public var registryEntryID: String?

    public init(
        kind: ProductOSAutomationTriggerKind,
        status: AgentSessionStatus? = nil,
        labelID: String? = nil,
        registryEntryID: String? = nil
    ) {
        self.kind = kind
        self.status = status
        self.labelID = labelID
        self.registryEntryID = registryEntryID
    }
}

public enum ProductOSAutomationActionKind: String, Codable, Sendable, Equatable, CaseIterable {
    case appendTimelineEvent
    case setSessionStatus
    case addSessionLabel
    case removeSessionLabel
    case triggerSkill
    case createArtifactPlaceholder
}

public struct ProductOSAutomationAction: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var kind: ProductOSAutomationActionKind
    public var status: AgentSessionStatus?
    public var label: AgentSessionLabel?
    public var skillID: String?
    public var message: String

    public init(
        id: String = UUID().uuidString,
        kind: ProductOSAutomationActionKind,
        status: AgentSessionStatus? = nil,
        label: AgentSessionLabel? = nil,
        skillID: String? = nil,
        message: String
    ) {
        self.id = id
        self.kind = kind
        self.status = status
        self.label = label
        self.skillID = skillID
        self.message = message
    }
}

public struct ProductOSAutomationRule: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var isEnabled: Bool
    public var trigger: ProductOSAutomationTrigger
    public var actions: [ProductOSAutomationAction]
    public var requiresReview: Bool
    public var tags: [String]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        name: String,
        isEnabled: Bool = true,
        trigger: ProductOSAutomationTrigger,
        actions: [ProductOSAutomationAction],
        requiresReview: Bool = true,
        tags: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.trigger = trigger
        self.actions = actions
        self.requiresReview = requiresReview
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ProductOSAutomationConfig: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var rules: [ProductOSAutomationRule]
    public var updatedAt: Date

    public init(schemaVersion: Int = 1, rules: [ProductOSAutomationRule] = ProductOSAutomationRule.defaults, updatedAt: Date = Date()) {
        self.schemaVersion = schemaVersion
        self.rules = rules.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        self.updatedAt = updatedAt
    }

    public static let `default` = ProductOSAutomationConfig()
}

public struct ProductOSAutomationEventContext: Sendable, Equatable {
    public var triggerKind: ProductOSAutomationTriggerKind
    public var sessionID: String
    public var status: AgentSessionStatus?
    public var labelID: String?
    public var registryEntryID: String?

    public init(
        triggerKind: ProductOSAutomationTriggerKind,
        sessionID: String,
        status: AgentSessionStatus? = nil,
        labelID: String? = nil,
        registryEntryID: String? = nil
    ) {
        self.triggerKind = triggerKind
        self.sessionID = sessionID
        self.status = status
        self.labelID = labelID
        self.registryEntryID = registryEntryID
    }
}

public struct ProductOSAutomationTriggerRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var ruleID: String
    public var ruleName: String
    public var trigger: ProductOSAutomationTriggerKind
    public var sessionID: String
    public var actionSummaries: [String]
    public var requiresReview: Bool
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        ruleID: String,
        ruleName: String,
        trigger: ProductOSAutomationTriggerKind,
        sessionID: String,
        actionSummaries: [String],
        requiresReview: Bool,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.ruleID = ruleID
        self.ruleName = ruleName
        self.trigger = trigger
        self.sessionID = sessionID
        self.actionSummaries = actionSummaries
        self.requiresReview = requiresReview
        self.createdAt = createdAt
    }
}

public extension ProductOSAutomationRule {
    static let defaults: [ProductOSAutomationRule] = [
        ProductOSAutomationRule(
            id: "important-label-adds-review-note",
            name: "Important label → Review note",
            trigger: ProductOSAutomationTrigger(kind: .sessionLabelAdded, labelID: "important"),
            actions: [
                ProductOSAutomationAction(kind: .appendTimelineEvent, message: "Important session marked; keep it visible in the review workflow.")
            ],
            requiresReview: false,
            tags: ["built-in", "label"]
        )
    ]
}
