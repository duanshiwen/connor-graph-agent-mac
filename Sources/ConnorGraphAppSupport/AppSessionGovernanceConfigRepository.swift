import Foundation
import ConnorGraphCore

public enum AppSessionGovernanceConfigError: Error, Equatable, CustomStringConvertible {
    case duplicateStatusID(String)
    case duplicateLabelID(String)

    public var description: String {
        switch self {
        case .duplicateStatusID(let id): "duplicateStatusID: \(id)"
        case .duplicateLabelID(let id): "duplicateLabelID: \(id)"
        }
    }
}

public struct AppSessionGovernanceConfig: Codable, Sendable, Equatable {
    public var statuses: [AgentSessionStatusDefinition]
    public var labels: [AgentSessionLabelDefinition]

    public init(
        statuses: [AgentSessionStatusDefinition] = AgentSessionStatusDefinition.defaults,
        labels: [AgentSessionLabelDefinition] = AgentSessionLabelDefinition.defaults
    ) {
        self.statuses = statuses.sorted { $0.sortOrder < $1.sortOrder }
        self.labels = labels
    }

    public static let `default` = AppSessionGovernanceConfig()

    public func validate() throws {
        var statusIDs: Set<String> = []
        for status in statuses {
            if !statusIDs.insert(status.id).inserted { throw AppSessionGovernanceConfigError.duplicateStatusID(status.id) }
        }
        var labelIDs: Set<String> = []
        for label in labels {
            if !labelIDs.insert(label.id).inserted { throw AppSessionGovernanceConfigError.duplicateLabelID(label.id) }
        }
    }

    public func definition(for labelID: String) -> AgentSessionLabelDefinition? {
        labels.first { $0.id == labelID }
    }

    public func validate(label: AgentSessionLabel) throws {
        _ = definition(for: label.id)
    }

    public func normalizingBuiltInDisplayNames() -> AppSessionGovernanceConfig {
        let statusNames = Dictionary(uniqueKeysWithValues: AgentSessionStatusDefinition.defaults.map { ($0.id, $0.name) })
        let labelDefaults = Dictionary(uniqueKeysWithValues: AgentSessionLabelDefinition.defaults.map { ($0.id, $0) })
        let normalizedStatuses = statuses.map { definition in
            guard let name = statusNames[definition.id], definition.name != name else { return definition }
            var copy = definition
            copy.name = name
            return copy
        }
        let normalizedLabels = labels.map { definition in
            guard let builtIn = labelDefaults[definition.id] else { return definition }
            var copy = definition
            if copy.name != builtIn.name {
                copy.name = builtIn.name
            }
            if copy.systemImage == "tag", builtIn.systemImage != "tag" {
                copy.systemImage = builtIn.systemImage
            }
            return copy
        }
        return AppSessionGovernanceConfig(statuses: normalizedStatuses, labels: normalizedLabels)
    }

}

public struct AppSessionGovernanceConfigRepository: Sendable {
    public var configDirectory: URL

    public init(configDirectory: URL) {
        self.configDirectory = configDirectory
    }

    public var configURL: URL { configDirectory.appendingPathComponent("session-governance.json") }

    public func loadOrCreateDefault() throws -> AppSessionGovernanceConfig {
        if FileManager.default.fileExists(atPath: configURL.path) {
            let data = try Data(contentsOf: configURL)
            let config = try JSONDecoder().decode(AppSessionGovernanceConfig.self, from: data)
            try config.validate()
            let normalizedConfig = config.normalizingBuiltInDisplayNames()
            if normalizedConfig != config {
                try save(normalizedConfig)
            }
            return normalizedConfig
        }
        let config = AppSessionGovernanceConfig.default
        try save(config)
        return config
    }

    public func save(_ config: AppSessionGovernanceConfig) throws {
        try config.validate()
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: configURL, options: .atomic)
    }
}
