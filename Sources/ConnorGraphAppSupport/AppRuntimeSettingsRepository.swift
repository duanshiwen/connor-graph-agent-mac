import Foundation
import ConnorGraphAgent

public struct AgentRuntimeUISettings: Codable, Sendable, Equatable {
    public var textDeltaFlushCharacterThreshold: Int
    public var textDeltaFlushIntervalMilliseconds: Int
    public var showPromptInspectionByDefault: Bool
    public var showProviderIcons: Bool
    public var richToolDescriptionsEnabled: Bool

    public init(
        textDeltaFlushCharacterThreshold: Int = 80,
        textDeltaFlushIntervalMilliseconds: Int = 120,
        showPromptInspectionByDefault: Bool = false,
        showProviderIcons: Bool = true,
        richToolDescriptionsEnabled: Bool = true
    ) {
        self.textDeltaFlushCharacterThreshold = textDeltaFlushCharacterThreshold
        self.textDeltaFlushIntervalMilliseconds = textDeltaFlushIntervalMilliseconds
        self.showPromptInspectionByDefault = showPromptInspectionByDefault
        self.showProviderIcons = showProviderIcons
        self.richToolDescriptionsEnabled = richToolDescriptionsEnabled
    }
}

public struct AgentRuntimeAppSettings: Codable, Sendable, Equatable {
    public var desktopNotificationsEnabled: Bool
    public var keepScreenAwake: Bool
    public var internalBrowserEnabled: Bool
    public var httpProxyEnabled: Bool
    public var httpProxyURLString: String

    public init(
        desktopNotificationsEnabled: Bool = true,
        keepScreenAwake: Bool = false,
        internalBrowserEnabled: Bool = true,
        httpProxyEnabled: Bool = false,
        httpProxyURLString: String = ""
    ) {
        self.desktopNotificationsEnabled = desktopNotificationsEnabled
        self.keepScreenAwake = keepScreenAwake
        self.internalBrowserEnabled = internalBrowserEnabled
        self.httpProxyEnabled = httpProxyEnabled
        self.httpProxyURLString = httpProxyURLString
    }
}

public struct AgentRuntimeAppearanceSettings: Codable, Sendable, Equatable {
    public var mode: String

    public init(mode: String = "system") {
        self.mode = mode
    }
}

public struct AgentRuntimeInputSettings: Codable, Sendable, Equatable {
    public var composerSendShortcut: String
    public var spellCheckEnabled: Bool
    public var autoSaveDraftsEnabled: Bool

    public init(
        composerSendShortcut: String = "return",
        spellCheckEnabled: Bool = true,
        autoSaveDraftsEnabled: Bool = true
    ) {
        self.composerSendShortcut = composerSendShortcut
        self.spellCheckEnabled = spellCheckEnabled
        self.autoSaveDraftsEnabled = autoSaveDraftsEnabled
    }
}

public struct AgentRuntimePermissionSettings: Codable, Sendable, Equatable {
    public var requireApprovalForNetwork: Bool
    public var requireApprovalForShell: Bool

    public init(
        requireApprovalForNetwork: Bool = true,
        requireApprovalForShell: Bool = true
    ) {
        self.requireApprovalForNetwork = requireApprovalForNetwork
        self.requireApprovalForShell = requireApprovalForShell
    }
}

public struct AgentRuntimeWorkspaceSettings: Codable, Sendable, Equatable {
    public var defaultWorkingDirectoryPath: String
    public var additionalAllowedDirectoryPaths: [String]

    public init(
        defaultWorkingDirectoryPath: String = "",
        additionalAllowedDirectoryPaths: [String] = []
    ) {
        self.defaultWorkingDirectoryPath = defaultWorkingDirectoryPath
        self.additionalAllowedDirectoryPaths = additionalAllowedDirectoryPaths
    }
}

public struct AgentRuntimePreferenceSettings: Codable, Sendable, Equatable {
    public var displayName: String
    public var timezone: String
    public var city: String
    public var country: String
    public var notes: String

    public init(
        displayName: String = "诗闻",
        timezone: String = "Asia/Shanghai",
        city: String = "杭州",
        country: String = "中国",
        notes: String = ""
    ) {
        self.displayName = displayName
        self.timezone = timezone
        self.city = city
        self.country = country
        self.notes = notes
    }
}

public struct AgentRuntimeSettings: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var loop: AgentLoopConfiguration
    public var ui: AgentRuntimeUISettings
    public var app: AgentRuntimeAppSettings
    public var appearance: AgentRuntimeAppearanceSettings
    public var input: AgentRuntimeInputSettings
    public var permissions: AgentRuntimePermissionSettings
    public var workspace: AgentRuntimeWorkspaceSettings
    public var preferences: AgentRuntimePreferenceSettings
    public var updatedAt: Date

    public init(
        schemaVersion: Int = 2,
        loop: AgentLoopConfiguration = AgentLoopConfiguration(),
        ui: AgentRuntimeUISettings = AgentRuntimeUISettings(),
        app: AgentRuntimeAppSettings = AgentRuntimeAppSettings(),
        appearance: AgentRuntimeAppearanceSettings = AgentRuntimeAppearanceSettings(),
        input: AgentRuntimeInputSettings = AgentRuntimeInputSettings(),
        permissions: AgentRuntimePermissionSettings = AgentRuntimePermissionSettings(),
        workspace: AgentRuntimeWorkspaceSettings = AgentRuntimeWorkspaceSettings(),
        preferences: AgentRuntimePreferenceSettings = AgentRuntimePreferenceSettings(),
        updatedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.loop = loop
        self.ui = ui
        self.app = app
        self.appearance = appearance
        self.input = input
        self.permissions = permissions
        self.workspace = workspace
        self.preferences = preferences
        self.updatedAt = updatedAt
    }

    public static let `default` = AgentRuntimeSettings()

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case loop
        case ui
        case app
        case appearance
        case input
        case permissions
        case workspace
        case preferences
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.loop = try container.decodeIfPresent(AgentLoopConfiguration.self, forKey: .loop) ?? AgentLoopConfiguration()
        self.ui = try container.decodeIfPresent(AgentRuntimeUISettings.self, forKey: .ui) ?? AgentRuntimeUISettings()
        self.app = try container.decodeIfPresent(AgentRuntimeAppSettings.self, forKey: .app) ?? AgentRuntimeAppSettings()
        self.appearance = try container.decodeIfPresent(AgentRuntimeAppearanceSettings.self, forKey: .appearance) ?? AgentRuntimeAppearanceSettings()
        self.input = try container.decodeIfPresent(AgentRuntimeInputSettings.self, forKey: .input) ?? AgentRuntimeInputSettings()
        self.permissions = try container.decodeIfPresent(AgentRuntimePermissionSettings.self, forKey: .permissions) ?? AgentRuntimePermissionSettings()
        self.workspace = try container.decodeIfPresent(AgentRuntimeWorkspaceSettings.self, forKey: .workspace) ?? AgentRuntimeWorkspaceSettings()
        self.preferences = try container.decodeIfPresent(AgentRuntimePreferenceSettings.self, forKey: .preferences) ?? AgentRuntimePreferenceSettings()
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
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
