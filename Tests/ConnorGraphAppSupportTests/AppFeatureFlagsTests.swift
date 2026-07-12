import Foundation
import Testing
@testable import ConnorGraphAppSupport

@Suite("App feature flags")
struct AppFeatureFlagsTests {
    @Test("Note import remains disabled by default")
    func noteImportDefaultsOff() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let flags = AppFeatureFlags.load(environment: [:], userDefaults: defaults)
        #expect(!flags.noteImportEnabled)
    }

    @Test("Environment override enables note import")
    func environmentOverride() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let flags = AppFeatureFlags.load(
            environment: [AppFeatureFlags.noteImportEnvironmentKey: "true"],
            userDefaults: defaults
        )
        #expect(flags.noteImportEnabled)
    }
}
