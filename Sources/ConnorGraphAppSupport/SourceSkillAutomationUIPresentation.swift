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

private extension ProductOSRegistryEntryStatus {
    var sourceUISeverity: AgentEventPresentationSeverity {
        switch self {
        case .enabled: .success
        case .draft, .needsReview: .warning
        case .disabled, .deprecated: .info
        }
    }
}
