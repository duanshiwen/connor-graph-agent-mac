import Foundation
import ConnorGraphCore

public enum AppProductOSAutomationError: Error, Equatable, CustomStringConvertible {
    case duplicateRuleID(String)
    case invalidID(String)
    case missingRequiredActionField(String)
    case unsafeAction(String)

    public var description: String {
        switch self {
        case .duplicateRuleID(let id): "duplicateRuleID: \(id)"
        case .invalidID(let id): "invalidID: \(id)"
        case .missingRequiredActionField(let message): "missingRequiredActionField: \(message)"
        case .unsafeAction(let message): "unsafeAction: \(message)"
        }
    }
}

public struct AppProductOSAutomationRepository: Sendable {
    public var storagePaths: AppStoragePaths

    public init(storagePaths: AppStoragePaths) {
        self.storagePaths = storagePaths
    }

    public var automationConfigURL: URL { storagePaths.automationsDirectory.appendingPathComponent("automations.json") }
    public var automationLogURL: URL { storagePaths.automationsDirectory.appendingPathComponent("automation-trigger-log.json") }
    public var statusesMirrorURL: URL { storagePaths.statusesDirectory.appendingPathComponent("statuses.json") }
    public var labelsMirrorURL: URL { storagePaths.labelsDirectory.appendingPathComponent("labels.json") }

    public func loadOrCreateDefault(governanceConfig: AppSessionGovernanceConfig = .default) throws -> ProductOSAutomationConfig {
        try storagePaths.ensureDirectoryHierarchy()
        try mirrorGovernanceConfig(governanceConfig)
        if FileManager.default.fileExists(atPath: automationConfigURL.path) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let config = try decoder.decode(ProductOSAutomationConfig.self, from: try Data(contentsOf: automationConfigURL))
            try validate(config)
            return config
        }
        let config = ProductOSAutomationConfig.default
        try save(config, governanceConfig: governanceConfig)
        return config
    }

    public func save(_ config: ProductOSAutomationConfig, governanceConfig: AppSessionGovernanceConfig = .default) throws {
        try validate(config)
        try storagePaths.ensureDirectoryHierarchy()
        try mirrorGovernanceConfig(governanceConfig)
        var normalized = config
        normalized.rules = config.rules.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        normalized.updatedAt = Date()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(normalized).write(to: automationConfigURL, options: .atomic)
    }

    public func setRuleEnabled(id: String, isEnabled: Bool, governanceConfig: AppSessionGovernanceConfig = .default) throws -> ProductOSAutomationConfig {
        var config = try loadOrCreateDefault(governanceConfig: governanceConfig)
        guard let index = config.rules.firstIndex(where: { $0.id == id }) else { return config }
        config.rules[index].isEnabled = isEnabled
        config.rules[index].updatedAt = Date()
        try save(config, governanceConfig: governanceConfig)
        return try loadOrCreateDefault(governanceConfig: governanceConfig)
    }

    public func evaluate(context: ProductOSAutomationEventContext, governanceConfig: AppSessionGovernanceConfig = .default) throws -> [ProductOSAutomationTriggerRecord] {
        let config = try loadOrCreateDefault(governanceConfig: governanceConfig)
        let records = config.rules
            .filter { $0.isEnabled && Self.matches(rule: $0, context: context) }
            .map { rule in
                ProductOSAutomationTriggerRecord(
                    ruleID: rule.id,
                    ruleName: rule.name,
                    trigger: context.triggerKind,
                    sessionID: context.sessionID,
                    actionSummaries: rule.actions.map(\.message),
                    requiresReview: rule.requiresReview
                )
            }
        guard !records.isEmpty else { return [] }
        try append(records: records)
        return records
    }

    public func loadRecentTriggerRecords(limit: Int = 50) throws -> [ProductOSAutomationTriggerRecord] {
        guard FileManager.default.fileExists(atPath: automationLogURL.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let records = try decoder.decode([ProductOSAutomationTriggerRecord].self, from: try Data(contentsOf: automationLogURL))
        return Array(records.sorted { $0.createdAt > $1.createdAt }.prefix(limit))
    }

    public static func matches(rule: ProductOSAutomationRule, context: ProductOSAutomationEventContext) -> Bool {
        guard rule.trigger.kind == context.triggerKind else { return false }
        if let status = rule.trigger.status, status != context.status { return false }
        if let labelID = rule.trigger.labelID, labelID != context.labelID { return false }
        if let registryEntryID = rule.trigger.registryEntryID, registryEntryID != context.registryEntryID { return false }
        return true
    }

    public func validate(_ config: ProductOSAutomationConfig) throws {
        var ids: Set<String> = []
        for rule in config.rules {
            try validateID(rule.id)
            if !ids.insert(rule.id).inserted { throw AppProductOSAutomationError.duplicateRuleID(rule.id) }
            for action in rule.actions { try validate(action) }
        }
    }

    private func validate(_ action: ProductOSAutomationAction) throws {
        switch action.kind {
        case .setSessionStatus:
            if action.status == nil { throw AppProductOSAutomationError.missingRequiredActionField("setSessionStatus requires status") }
        case .addSessionLabel, .removeSessionLabel:
            if action.label == nil { throw AppProductOSAutomationError.missingRequiredActionField("\(action.kind.rawValue) requires label") }
        case .triggerSkill:
            guard let skillID = action.skillID, !skillID.isEmpty else { throw AppProductOSAutomationError.missingRequiredActionField("triggerSkill requires skillID") }
        case .appendTimelineEvent, .createArtifactPlaceholder:
            break
        }
        if action.kind == .setSessionStatus, action.status == .archived {
            throw AppProductOSAutomationError.unsafeAction("Archiving by automation is deferred until explicit execution review exists")
        }
    }

    private func append(records: [ProductOSAutomationTriggerRecord]) throws {
        var existing = try loadRecentTriggerRecords(limit: 500)
        existing.append(contentsOf: records)
        existing = Array(existing.sorted { $0.createdAt > $1.createdAt }.prefix(500))
        try FileManager.default.createDirectory(at: storagePaths.automationsDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(existing).write(to: automationLogURL, options: .atomic)
    }

    private func mirrorGovernanceConfig(_ config: AppSessionGovernanceConfig) throws {
        try FileManager.default.createDirectory(at: storagePaths.statusesDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: storagePaths.labelsDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config.statuses).write(to: statusesMirrorURL, options: .atomic)
        try encoder.encode(config.labels).write(to: labelsMirrorURL, options: .atomic)
    }

    private func validateID(_ id: String) throws {
        let pattern = #"^[a-z0-9][a-z0-9-]{1,62}[a-z0-9]$"#
        guard id.range(of: pattern, options: .regularExpression) != nil else {
            throw AppProductOSAutomationError.invalidID(id)
        }
    }
}
