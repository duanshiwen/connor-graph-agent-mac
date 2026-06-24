import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Calendar Provider Profile Tests")
struct CalendarProviderProfileTests {
    @Test func providerProfilesExposeSupportedReadOnlySourcesAndPendingOAuthSourcesHonestly() {
        let profiles = CalendarProviderProfile.catalog

        #expect(profiles.first?.sourceKind == .macOSEventKit)
        #expect(profiles.contains { $0.sourceKind == .icsSubscription && $0.isUserConfigurable })
        #expect(profiles.contains { $0.sourceKind == .genericCalDAV && $0.authMode == .appPassword && $0.isUserConfigurable })
        #expect(profiles.contains { $0.sourceKind == .appleICloudCalDAV && $0.helpText.contains("App-specific") })
        #expect(profiles.contains { $0.sourceKind == .googleCalendar && !$0.isUserConfigurable && $0.status == .planned })
        #expect(profiles.contains { $0.sourceKind == .microsoft365Calendar && !$0.isUserConfigurable && $0.status == .planned })
    }
}
