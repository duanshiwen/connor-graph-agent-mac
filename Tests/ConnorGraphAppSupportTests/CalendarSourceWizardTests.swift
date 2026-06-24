import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Calendar Source Wizard Tests")
struct CalendarSourceWizardTests {
    @Test func wizardBuildsICSAccountWithoutCredentials() throws {
        var state = CalendarSourceWizardState(provider: .icsSubscription)
        state.displayName = "Team Holidays"
        state.subscriptionURLString = "webcal://example.com/team.ics"

        let account = try state.buildAccount(existingAccountCount: 0)

        #expect(account.sourceKind == .icsSubscription)
        #expect(account.configuration.authMode == .none)
        #expect(account.configuration.subscriptionURL?.scheme == "webcal")
        #expect(account.configuration.syncMode == .readOnly)
    }

    @Test func wizardBuildsCalDAVAccountAndCredentialBinding() throws {
        var state = CalendarSourceWizardState(provider: .genericCalDAV)
        state.displayName = "Work CalDAV"
        state.serverURLString = "https://cal.example.com"
        state.username = "USER@example.com"
        state.appPassword = "secret"
        state.syncWindowPastDays = 14
        state.syncWindowFutureDays = 90

        let account = try state.buildAccount(existingAccountCount: 2)
        let binding = try state.credentialBinding(for: account.id)

        #expect(account.sourceKind == .genericCalDAV)
        #expect(account.configuration.serverURL?.absoluteString == "https://cal.example.com")
        #expect(account.configuration.username == "USER@example.com")
        #expect(account.configuration.syncWindowPastDays == 14)
        #expect(account.configuration.syncWindowFutureDays == 90)
        #expect(binding.accountName.contains("user@example.com"))
    }

    @Test func wizardRejectsPlannedOAuthProviders() {
        let state = CalendarSourceWizardState(provider: .googleCalendar)
        #expect(throws: CalendarSourceWizardError.providerNotConfigurable) {
            _ = try state.buildAccount(existingAccountCount: 0)
        }
    }
}
