import Foundation

public struct AppFeatureFlags: Sendable, Equatable {
    public static let noteImportEnvironmentKey = "CONNOR_NOTE_IMPORT_ENABLED"
    public static let noteImportDefaultsKey = "connor.feature.noteImport.enabled"

    public var noteImportEnabled: Bool

    public init(noteImportEnabled: Bool = true) {
        self.noteImportEnabled = noteImportEnabled
    }

    public static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        userDefaults: UserDefaults = .standard
    ) -> AppFeatureFlags {
        if let rawValue = environment[noteImportEnvironmentKey],
           let value = parseBoolean(rawValue) {
            return AppFeatureFlags(noteImportEnabled: value)
        }
        if userDefaults.object(forKey: noteImportDefaultsKey) != nil {
            return AppFeatureFlags(noteImportEnabled: userDefaults.bool(forKey: noteImportDefaultsKey))
        }
        return AppFeatureFlags(noteImportEnabled: true)
    }

    private static func parseBoolean(_ value: String) -> Bool? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on": true
        case "0", "false", "no", "off": false
        default: nil
        }
    }
}
