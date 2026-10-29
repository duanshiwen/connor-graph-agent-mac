import Foundation
import ConnorGraphCore

public enum AppSessionGovernanceConfigError: Error, Equatable, CustomStringConvertible {
    case duplicateLabelID(String)

    public var description: String {
        switch self {
        case .duplicateLabelID(let id): "duplicateLabelID: \(id)"
        }
    }
}

public struct AppSessionGovernanceConfig: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey { case labels }

    public var labels: [AgentSessionLabelDefinition]

    public init(
        labels: [AgentSessionLabelDefinition] = AgentSessionLabelDefinition.defaults
    ) {
        self.labels = labels
    }

    public static let `default` = AppSessionGovernanceConfig()

    public func validate() throws {
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
        let labelDefaults = Dictionary(uniqueKeysWithValues: AgentSessionLabelDefinition.defaults.map { ($0.id, $0) })
        let normalizedLabels = labels.map { definition in
            guard let builtIn = labelDefaults[definition.id] else { return definition }
            var copy = definition
            // 内置标签只有在“从未编辑过”（updatedAt == 0）时才回填默认显示名；
            // 用户显式改过文字后保留自定义名，避免同步后又被规范化覆盖。
            if copy.updatedAt == 0, copy.name != builtIn.name {
                copy.name = builtIn.name
            }
            if copy.updatedAt == 0, copy.systemImage == "tag", builtIn.systemImage != "tag" {
                copy.systemImage = builtIn.systemImage
            }
            return copy
        }
        return AppSessionGovernanceConfig(labels: normalizedLabels)
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
        let deletions = AccountSyncLocalDeletions(directory: configDirectory)
        if FileManager.default.fileExists(atPath: configURL.path) {
            let data = try Data(contentsOf: configURL)
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            let previous = try decoder.decode(AppSessionGovernanceConfig.self, from: data)
            for label in previous.labels where !config.labels.contains(where: { $0.id == label.id }) {
                try deletions.record(collection: "governance_labels", id: label.id)
            }
        }
        for label in config.labels { try deletions.clear("governance_labels|\(label.id)") }
        try saveSynced(config)
    }

    public func saveSynced(_ config: AppSessionGovernanceConfig) throws {
        try config.validate()
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: configURL, options: .atomic)
        // 标签定义属于账号同步的 governance_labels 集合，保存后通知同步协调器。
        AppAccountSyncSignal.postLocalDataDidChange()
    }
}
