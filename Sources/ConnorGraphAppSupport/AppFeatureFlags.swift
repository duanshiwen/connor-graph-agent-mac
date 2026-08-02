import Foundation

public struct AppFeatureFlags: Sendable, Equatable {
    public static let noteImportEnvironmentKey = "CONNOR_NOTE_IMPORT_ENABLED"
    public static let noteImportDefaultsKey = "connor.feature.noteImport.enabled"
    public static let interactiveWebSuggestionsEnvironmentKey = "CONNOR_INTERACTIVE_WEB_SUGGESTIONS_ENABLED"
    public static let interactiveWebSuggestionsDefaultsKey = "connor.feature.interactiveWebSuggestions.enabled"

    public var noteImportEnabled: Bool
    public var interactiveWebSuggestionsEnabled: Bool

    public init(noteImportEnabled: Bool = true, interactiveWebSuggestionsEnabled: Bool = true) {
        self.noteImportEnabled = noteImportEnabled
        self.interactiveWebSuggestionsEnabled = interactiveWebSuggestionsEnabled
    }

    public static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        userDefaults: UserDefaults = .standard
    ) -> AppFeatureFlags {
        let noteImportEnabled = resolvedBoolean(
            environmentValue: environment[noteImportEnvironmentKey],
            defaultsKey: noteImportDefaultsKey,
            userDefaults: userDefaults
        )
        let interactiveWebSuggestionsEnabled = resolvedBoolean(
            environmentValue: environment[interactiveWebSuggestionsEnvironmentKey],
            defaultsKey: interactiveWebSuggestionsDefaultsKey,
            userDefaults: userDefaults
        )
        return AppFeatureFlags(
            noteImportEnabled: noteImportEnabled,
            interactiveWebSuggestionsEnabled: interactiveWebSuggestionsEnabled
        )
    }

    private static func resolvedBoolean(environmentValue: String?, defaultsKey: String, userDefaults: UserDefaults) -> Bool {
        if let environmentValue, let value = parseBoolean(environmentValue) { return value }
        if userDefaults.object(forKey: defaultsKey) != nil { return userDefaults.bool(forKey: defaultsKey) }
        return true
    }

    private static func parseBoolean(_ value: String) -> Bool? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on": true
        case "0", "false", "no", "off": false
        default: nil
        }
    }
}
