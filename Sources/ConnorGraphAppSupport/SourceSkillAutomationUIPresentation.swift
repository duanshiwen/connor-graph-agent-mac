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
