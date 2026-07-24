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
    public var sessionNotificationSettings: SessionNotificationSettings

    public init(
        desktopNotificationsEnabled: Bool = true,
        keepScreenAwake: Bool = false,
        internalBrowserEnabled: Bool = true,
        httpProxyEnabled: Bool = false,
        httpProxyURLString: String = "",
        sessionNotificationSettings: SessionNotificationSettings = .default
    ) {
        self.desktopNotificationsEnabled = desktopNotificationsEnabled
        self.keepScreenAwake = keepScreenAwake
        self.internalBrowserEnabled = internalBrowserEnabled
        self.httpProxyEnabled = httpProxyEnabled
        self.httpProxyURLString = httpProxyURLString
        self.sessionNotificationSettings = sessionNotificationSettings
    }

    private enum CodingKeys: String, CodingKey {
        case desktopNotificationsEnabled
        case keepScreenAwake
        case internalBrowserEnabled
        case httpProxyEnabled
        case httpProxyURLString
        case sessionNotificationSettings
        case sessionNotificationPolicy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        desktopNotificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .desktopNotificationsEnabled) ?? true
        keepScreenAwake = try container.decodeIfPresent(Bool.self, forKey: .keepScreenAwake) ?? false
        internalBrowserEnabled = try container.decodeIfPresent(Bool.self, forKey: .internalBrowserEnabled) ?? true
        httpProxyEnabled = try container.decodeIfPresent(Bool.self, forKey: .httpProxyEnabled) ?? false
        httpProxyURLString = try container.decodeIfPresent(String.self, forKey: .httpProxyURLString) ?? ""
        if let settings = try container.decodeIfPresent(SessionNotificationSettings.self, forKey: .sessionNotificationSettings) {
            sessionNotificationSettings = settings
        } else if let legacyPolicy = try container.decodeIfPresent(LegacySessionNotificationPolicy.self, forKey: .sessionNotificationPolicy) {
            sessionNotificationSettings = SessionNotificationSettings(newMessageLevel: legacyPolicy.minimumLevel)
        } else {
            sessionNotificationSettings = .default
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(desktopNotificationsEnabled, forKey: .desktopNotificationsEnabled)
        try container.encode(keepScreenAwake, forKey: .keepScreenAwake)
        try container.encode(internalBrowserEnabled, forKey: .internalBrowserEnabled)
        try container.encode(httpProxyEnabled, forKey: .httpProxyEnabled)
        try container.encode(httpProxyURLString, forKey: .httpProxyURLString)
        try container.encode(sessionNotificationSettings, forKey: .sessionNotificationSettings)
    }
}

private struct LegacySessionNotificationPolicy: Codable {
    var minimumLevel: SessionAttentionLevel
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
    public var sessionSpeechTranscriptionEnabled: Bool

    public init(
        composerSendShortcut: String = "return",
        spellCheckEnabled: Bool = true,
        autoSaveDraftsEnabled: Bool = true,
        sessionSpeechTranscriptionEnabled: Bool = false
    ) {
        self.composerSendShortcut = composerSendShortcut
        self.spellCheckEnabled = spellCheckEnabled
        self.autoSaveDraftsEnabled = autoSaveDraftsEnabled
        self.sessionSpeechTranscriptionEnabled = sessionSpeechTranscriptionEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case composerSendShortcut
        case spellCheckEnabled
        case autoSaveDraftsEnabled
        case sessionSpeechTranscriptionEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        composerSendShortcut = try container.decodeIfPresent(String.self, forKey: .composerSendShortcut) ?? "return"
        spellCheckEnabled = try container.decodeIfPresent(Bool.self, forKey: .spellCheckEnabled) ?? true
        autoSaveDraftsEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoSaveDraftsEnabled) ?? true
        sessionSpeechTranscriptionEnabled = try container.decodeIfPresent(Bool.self, forKey: .sessionSpeechTranscriptionEnabled) ?? false
    }
}

public struct AgentRuntimePermissionSettings: Codable, Sendable, Equatable {
    public var requireApprovalForNetwork: Bool
    public var requireApprovalForShell: Bool

    public init(
        requireApprovalForNetwork: Bool = false,
        requireApprovalForShell: Bool = true
    ) {
        self.requireApprovalForNetwork = requireApprovalForNetwork
        self.requireApprovalForShell = requireApprovalForShell
    }
}

public enum AgentRuntimeShortcutAction: String, Codable, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case newSession
    case toggleBrowser
    case focusTopSearch
    case openSettings
    case focusBrowserAddress
    case newBrowserTab
    case closeBrowserTab
    case browserBack
    case browserForward
    case toggleBrowserBookmarks
    case toggleBrowserHistory

    public var id: String { rawValue }

    public init?(legacyRawValue rawValue: String) {
        self.init(rawValue: rawValue)
    }
}

public struct AgentRuntimeKeyboardShortcut: Codable, Sendable, Equatable, Hashable {
    public var key: String
    public var command: Bool
    public var shift: Bool
    public var option: Bool
    public var control: Bool

    public init(
        key: String,
        command: Bool = true,
        shift: Bool = false,
        option: Bool = false,
        control: Bool = false
    ) {
        self.key = key
        self.command = command
        self.shift = shift
        self.option = option
        self.control = control
    }

    public var displayText: String {
        [
            command ? "⌘" : "",
            shift ? "⇧" : "",
            option ? "⌥" : "",
            control ? "⌃" : "",
            key.uppercased()
        ].filter { !$0.isEmpty }.joined()
    }

    public func matches(
        character: String?,
        isCommandDown: Bool,
        isShiftDown: Bool,
        isControlDown: Bool,
        isOptionDown: Bool
    ) -> Bool {
        guard command == isCommandDown,
              shift == isShiftDown,
              control == isControlDown,
              option == isOptionDown else { return false }
        return character?.lowercased() == key.lowercased()
    }
}

public struct AgentRuntimeShortcutSettings: Codable, Sendable, Equatable {
    public var bindings: [AgentRuntimeShortcutAction: AgentRuntimeKeyboardShortcut]

    public init(bindings: [AgentRuntimeShortcutAction: AgentRuntimeKeyboardShortcut] = AgentRuntimeShortcutSettings.defaultBindings) {
        self.bindings = AgentRuntimeShortcutSettings.mergedWithDefaults(bindings)
    }

    public static let defaultBindings: [AgentRuntimeShortcutAction: AgentRuntimeKeyboardShortcut] = [
        .newSession: AgentRuntimeKeyboardShortcut(key: "n"),
        .toggleBrowser: AgentRuntimeKeyboardShortcut(key: "b"),
        .focusTopSearch: AgentRuntimeKeyboardShortcut(key: "f"),
        .openSettings: AgentRuntimeKeyboardShortcut(key: ","),
        .focusBrowserAddress: AgentRuntimeKeyboardShortcut(key: "l"),
        .newBrowserTab: AgentRuntimeKeyboardShortcut(key: "t"),
        .closeBrowserTab: AgentRuntimeKeyboardShortcut(key: "w"),
        .browserBack: AgentRuntimeKeyboardShortcut(key: "["),
        .browserForward: AgentRuntimeKeyboardShortcut(key: "]"),
        .toggleBrowserBookmarks: AgentRuntimeKeyboardShortcut(key: "b", shift: true),
        .toggleBrowserHistory: AgentRuntimeKeyboardShortcut(key: "y")
    ]

    public static func mergedWithDefaults(_ bindings: [AgentRuntimeShortcutAction: AgentRuntimeKeyboardShortcut]) -> [AgentRuntimeShortcutAction: AgentRuntimeKeyboardShortcut] {
        var merged = defaultBindings
        for (action, shortcut) in bindings { merged[action] = shortcut }
        return merged
    }

    public func shortcut(for action: AgentRuntimeShortcutAction) -> AgentRuntimeKeyboardShortcut {
        bindings[action] ?? Self.defaultBindings[action] ?? AgentRuntimeKeyboardShortcut(key: "")
    }

    private enum CodingKeys: String, CodingKey { case bindings }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawBindings = try Self.decodeBindings(from: container)
        var decoded: [AgentRuntimeShortcutAction: AgentRuntimeKeyboardShortcut] = [:]
        for (rawAction, shortcut) in rawBindings {
            guard let action = AgentRuntimeShortcutAction(legacyRawValue: rawAction) else { continue }
            decoded[action] = shortcut
        }
        self.bindings = Self.mergedWithDefaults(decoded.isEmpty ? Self.defaultBindings : decoded)
    }

    private static func decodeBindings(from container: KeyedDecodingContainer<CodingKeys>) throws -> [String: AgentRuntimeKeyboardShortcut] {
        if let dictionary = try? container.decodeIfPresent([String: AgentRuntimeKeyboardShortcut].self, forKey: .bindings) {
            return dictionary
        }
        if let legacyPairs = try? container.decodeIfPresent([LegacyShortcutBindingElement].self, forKey: .bindings) {
            return Self.decodeLegacyBindings(from: legacyPairs)
        }
        return [:]
    }

    private static func decodeLegacyBindings(from elements: [LegacyShortcutBindingElement]) -> [String: AgentRuntimeKeyboardShortcut] {
        var decoded: [String: AgentRuntimeKeyboardShortcut] = [:]
        var index = 0
        while index + 1 < elements.count {
            guard case let .action(rawAction) = elements[index],
                  case let .shortcut(shortcut) = elements[index + 1] else {
                index += 1
                continue
            }
            decoded[rawAction] = shortcut
            index += 2
        }
        return decoded
    }

    private enum LegacyShortcutBindingElement: Decodable {
        case action(String)
        case shortcut(AgentRuntimeKeyboardShortcut)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let rawAction = try? container.decode(String.self) {
                self = .action(rawAction)
                return
            }
            self = .shortcut(try container.decode(AgentRuntimeKeyboardShortcut.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let rawBindings = Dictionary(uniqueKeysWithValues: bindings.map { ($0.key.rawValue, $0.value) })
        try container.encode(rawBindings, forKey: .bindings)
    }
}

public struct AgentRuntimeWorkspaceRoot: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var displayName: String
    public var path: String
    public var role: String
    public var isPrimary: Bool

    public init(
        id: String = UUID().uuidString,
        displayName: String,
        path: String,
        role: String = "project",
        isPrimary: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.path = path
        self.role = role
        self.isPrimary = isPrimary
    }
}

public struct AgentRuntimeWorkspaceSettings: Codable, Sendable, Equatable {
    public var defaultWorkingDirectoryPath: String
    public var additionalAllowedDirectoryPaths: [String]
    public var roots: [AgentRuntimeWorkspaceRoot]
    public var recentWorkspacePaths: [String]

    public init(
        defaultWorkingDirectoryPath: String = "",
        additionalAllowedDirectoryPaths: [String] = [],
        roots: [AgentRuntimeWorkspaceRoot] = [],
        recentWorkspacePaths: [String] = []
    ) {
        self.defaultWorkingDirectoryPath = defaultWorkingDirectoryPath
        self.additionalAllowedDirectoryPaths = additionalAllowedDirectoryPaths
        self.roots = roots
        self.recentWorkspacePaths = recentWorkspacePaths
    }

    private enum CodingKeys: String, CodingKey {
        case defaultWorkingDirectoryPath
        case additionalAllowedDirectoryPaths
        case roots
        case recentWorkspacePaths
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.defaultWorkingDirectoryPath = try container.decodeIfPresent(String.self, forKey: .defaultWorkingDirectoryPath) ?? ""
        self.additionalAllowedDirectoryPaths = try container.decodeIfPresent([String].self, forKey: .additionalAllowedDirectoryPaths) ?? []
        self.roots = try container.decodeIfPresent([AgentRuntimeWorkspaceRoot].self, forKey: .roots) ?? []
        self.recentWorkspacePaths = try container.decodeIfPresent([String].self, forKey: .recentWorkspacePaths) ?? []
    }

    public var primaryRoot: AgentRuntimeWorkspaceRoot? {
        roots.first(where: \.isPrimary) ?? roots.first
    }

    public mutating func rememberWorkspacePath(_ rawPath: String, limit: Int = 10) {
        let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }
        recentWorkspacePaths.removeAll { $0 == path }
        recentWorkspacePaths.insert(path, at: 0)
        if recentWorkspacePaths.count > limit {
            recentWorkspacePaths = Array(recentWorkspacePaths.prefix(limit))
        }
    }

    public mutating func clearRecentWorkspacePaths() {
        recentWorkspacePaths = []
    }

    public mutating func syncLegacyFieldsFromRoots() {
        guard !roots.isEmpty else { return }
        let primary = primaryRoot
        defaultWorkingDirectoryPath = primary?.path ?? ""
        additionalAllowedDirectoryPaths = roots
            .filter { $0.id != primary?.id }
            .map(\.path)
    }

    public func effectiveRoots() -> [AgentRuntimeWorkspaceRoot] {
        if !roots.isEmpty { return roots }
        let primaryPath = defaultWorkingDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let additional = additionalAllowedDirectoryPaths
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var synthesized: [AgentRuntimeWorkspaceRoot] = []
        if !primaryPath.isEmpty {
            synthesized.append(AgentRuntimeWorkspaceRoot(displayName: URL(fileURLWithPath: primaryPath).lastPathComponent, path: primaryPath, role: "project", isPrimary: true))
        }
        synthesized.append(contentsOf: additional.map { path in
            AgentRuntimeWorkspaceRoot(displayName: URL(fileURLWithPath: path).lastPathComponent, path: path, role: "additional", isPrimary: false)
        })
        return synthesized
    }
}

public struct AgentRuntimePreferenceSettings: Codable, Sendable, Equatable {
    public var displayName: String
    public var timezone: String
    public var preferredLanguage: String
    public var city: String
    public var country: String
    public var genderIdentity: String
    public var birthDate: String
    public var notes: String
    public var defaultSearchEngine: DefaultSearchEngine
    public var connorPersonality: ConnorPersonalitySettings
    public var connorPersonalityRevision: Int
    public var connorSpeech: ConnorSpeechSettings

    public init(
        displayName: String = "",
        timezone: String = "",
        preferredLanguage: String = "",
        city: String = "",
        country: String = "",
        genderIdentity: String = "",
        birthDate: String = "",
        notes: String = "",
        defaultSearchEngine: DefaultSearchEngine = .default,
        connorPersonality: ConnorPersonalitySettings = .balancedDefault,
        connorPersonalityRevision: Int = 0,
        connorSpeech: ConnorSpeechSettings = .default
    ) {
        self.displayName = displayName
        self.timezone = timezone
        self.preferredLanguage = preferredLanguage
        self.city = city
        self.country = country
        self.genderIdentity = genderIdentity
        self.birthDate = birthDate
        self.notes = notes
        self.defaultSearchEngine = defaultSearchEngine
        self.connorPersonality = connorPersonality
        self.connorPersonalityRevision = max(0, connorPersonalityRevision)
        self.connorSpeech = connorSpeech
    }

    private enum CodingKeys: String, CodingKey {
        case displayName
        case timezone
        case preferredLanguage
        case city
        case country
        case genderIdentity
        case birthDate
        case notes
        case defaultSearchEngine
        case connorPersonality
        case connorPersonalityRevision
        case connorSpeech
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        self.timezone = try container.decodeIfPresent(String.self, forKey: .timezone) ?? ""
        self.preferredLanguage = try container.decodeIfPresent(String.self, forKey: .preferredLanguage) ?? ""
        self.city = try container.decodeIfPresent(String.self, forKey: .city) ?? ""
        self.country = try container.decodeIfPresent(String.self, forKey: .country) ?? ""
        self.genderIdentity = try container.decodeIfPresent(String.self, forKey: .genderIdentity) ?? ""
        self.birthDate = try container.decodeIfPresent(String.self, forKey: .birthDate) ?? ""
        self.notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        self.defaultSearchEngine = try container.decodeIfPresent(DefaultSearchEngine.self, forKey: .defaultSearchEngine) ?? .default
        self.connorPersonality = try container.decodeIfPresent(ConnorPersonalitySettings.self, forKey: .connorPersonality) ?? .balancedDefault
        self.connorPersonalityRevision = max(0, try container.decodeIfPresent(Int.self, forKey: .connorPersonalityRevision) ?? 0)
        self.connorSpeech = try container.decodeIfPresent(ConnorSpeechSettings.self, forKey: .connorSpeech) ?? .default
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
    public var shortcuts: AgentRuntimeShortcutSettings
    public var workspace: AgentRuntimeWorkspaceSettings
    public var preferences: AgentRuntimePreferenceSettings
    public var updatedAt: Date

    public init(
        schemaVersion: Int = 3,
        loop: AgentLoopConfiguration = AgentLoopConfiguration(),
        ui: AgentRuntimeUISettings = AgentRuntimeUISettings(),
        app: AgentRuntimeAppSettings = AgentRuntimeAppSettings(),
        appearance: AgentRuntimeAppearanceSettings = AgentRuntimeAppearanceSettings(),
        input: AgentRuntimeInputSettings = AgentRuntimeInputSettings(),
        permissions: AgentRuntimePermissionSettings = AgentRuntimePermissionSettings(),
        shortcuts: AgentRuntimeShortcutSettings = AgentRuntimeShortcutSettings(),
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
        self.shortcuts = shortcuts
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
        case shortcuts
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
        self.shortcuts = try container.decodeIfPresent(AgentRuntimeShortcutSettings.self, forKey: .shortcuts) ?? AgentRuntimeShortcutSettings()
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

    /// Persists a personality change only if the on-disk revision still matches the
    /// revision that the caller read before proposing the change.
    public func commitPersonality(
        _ settings: AgentRuntimeSettings,
        expectedRevision: Int
    ) throws {
        let current = try loadOrCreateDefault()
        guard current.preferences.connorPersonalityRevision == expectedRevision else {
            throw ConnorPersonalityProposalError.revisionConflict(
                expected: expectedRevision,
                actual: current.preferences.connorPersonalityRevision
            )
        }
        guard settings.preferences.connorPersonalityRevision == expectedRevision + 1 else {
            throw ConnorPersonalityProposalError.revisionConflict(
                expected: expectedRevision + 1,
                actual: settings.preferences.connorPersonalityRevision
            )
        }
        try save(settings)
    }
}
