import Foundation
import ConnorGraphCore

public enum AppSessionGovernanceConfigError: Error, Equatable, CustomStringConvertible {
    case duplicateStatusID(String)
    case duplicateLabelID(String)
    case invalidLabelValue(String)

    public var description: String {
        switch self {
        case .duplicateStatusID(let id): "duplicateStatusID: \(id)"
        case .duplicateLabelID(let id): "duplicateLabelID: \(id)"
        case .invalidLabelValue(let message): "invalidLabelValue: \(message)"
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
        guard let definition = definition(for: label.id) else { return }
        switch definition.valueType {
        case .boolean:
            if label.value != nil { throw AppSessionGovernanceConfigError.invalidLabelValue("Boolean label \(label.id) must not carry a value") }
        case .number:
            if let value = label.value, Double(value) == nil { throw AppSessionGovernanceConfigError.invalidLabelValue("Number label \(label.id) requires numeric value") }
        case .date:
            if let value = label.value, Self.dateFormatter.date(from: value) == nil { throw AppSessionGovernanceConfigError.invalidLabelValue("Date label \(label.id) requires yyyy-MM-dd") }
        case .link:
            if let value = label.value, URL(string: value)?.scheme == nil { throw AppSessionGovernanceConfigError.invalidLabelValue("Link label \(label.id) requires URL") }
        case .string, .graphEntityRef:
            break
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
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
            return config
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
