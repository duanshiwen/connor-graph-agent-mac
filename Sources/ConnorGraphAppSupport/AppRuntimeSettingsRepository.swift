import Foundation
import ConnorGraphAgent

public struct AgentRuntimeUISettings: Codable, Sendable, Equatable {
    public var textDeltaFlushCharacterThreshold: Int
    public var textDeltaFlushIntervalMilliseconds: Int
    public var showPromptInspectionByDefault: Bool

    public init(
        textDeltaFlushCharacterThreshold: Int = 80,
        textDeltaFlushIntervalMilliseconds: Int = 120,
        showPromptInspectionByDefault: Bool = false
    ) {
        self.textDeltaFlushCharacterThreshold = textDeltaFlushCharacterThreshold
        self.textDeltaFlushIntervalMilliseconds = textDeltaFlushIntervalMilliseconds
        self.showPromptInspectionByDefault = showPromptInspectionByDefault
    }
}

public struct AgentRuntimeSettings: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var loop: AgentLoopConfiguration
    public var ui: AgentRuntimeUISettings
    public var updatedAt: Date

    public init(
        schemaVersion: Int = 1,
        loop: AgentLoopConfiguration = AgentLoopConfiguration(),
        ui: AgentRuntimeUISettings = AgentRuntimeUISettings(),
        updatedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.loop = loop
        self.ui = ui
        self.updatedAt = updatedAt
    }

    public static let `default` = AgentRuntimeSettings()
}

public struct AppRuntimeSettingsRepository: @unchecked Sendable {
    public var configDirectory: URL
    public var fileManager: FileManager
    public var filename: String

    public init(
        configDirectory: URL,
        fileManager: FileManager = .default,
        filename: String = "runtime-settings.json"
    ) {
        self.configDirectory = configDirectory
        self.fileManager = fileManager
        self.filename = filename
    }

    public var fileURL: URL { configDirectory.appendingPathComponent(filename) }

    public func loadOrCreateDefault() throws -> AgentRuntimeSettings {
        if fileManager.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(AgentRuntimeSettings.self, from: data)
        }
        let settings = AgentRuntimeSettings.default
        try save(settings)
        return settings
    }

    public func save(_ settings: AgentRuntimeSettings) throws {
        try fileManager.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        var updated = settings
        updated.updatedAt = Date()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(updated).write(to: fileURL, options: .atomic)
    }
}
