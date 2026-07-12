import Foundation
import Testing
@testable import ConnorGraphAppSupport

@Suite("App feature flags")
struct AppFeatureFlagsTests {
    @Test("Note import is enabled by default")
    func noteImportDefaultsOn() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let flags = AppFeatureFlags.load(environment: [:], userDefaults: defaults)
        #expect(flags.noteImportEnabled)
    }

    @Test("Environment override can disable note import")
    func environmentOverride() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let flags = AppFeatureFlags.load(
            environment: [AppFeatureFlags.noteImportEnvironmentKey: "false"],
            userDefaults: defaults
        )
        #expect(!flags.noteImportEnabled)
    }

    @Test("Persisted kill switch can disable note import")
    func defaultsOverride() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(false, forKey: AppFeatureFlags.noteImportDefaultsKey)
        let flags = AppFeatureFlags.load(environment: [:], userDefaults: defaults)
        #expect(!flags.noteImportEnabled)
    }
}
