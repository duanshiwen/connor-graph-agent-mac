import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Calendar Source Diagnostics Presentation Tests")
struct CalendarSourceDiagnosticsPresentationTests {
    @Test func builderSummarizesAccountHealthCountsAndDiagnostics() {
        let accountID = CalendarAccountID(rawValue: "account")
        let calendarID = CalendarID(rawValue: "calendar")
        let snapshot = CalendarSourceRuntimeSnapshot(
            accounts: [CalendarAccount(id: accountID, provider: .genericCalDAVCardDAV, sourceKind: .icsSubscription, displayName: "ICS")],
            collections: [CalendarCollection(id: calendarID, accountID: accountID, displayName: "ICS", isReadOnly: true)],
            events: [CalendarEvent(id: CalendarEventID(rawValue: "event"), calendarID: calendarID, title: "Demo", start: CalendarEventDateTime(date: Date()), end: CalendarEventDateTime(date: Date()))],
            syncStates: [CalendarAccountSyncState(accountID: accountID, sourceKind: .icsSubscription, lastSuccessfulSyncAt: Date(timeIntervalSince1970: 100), failureCount: 1, nextRetryAt: Date(timeIntervalSince1970: 200))],
            diagnostics: [CalendarSourceSyncDiagnostic(accountID: accountID, severity: .error, code: "network", message: "Network failed")]
        )

        let presentation = CalendarSourceDiagnosticsPresentationBuilder().build(snapshot: snapshot)

        #expect(presentation.cards.count == 1)
        #expect(presentation.cards[0].displayName == "ICS")
        #expect(presentation.cards[0].collectionCount == 1)
        #expect(presentation.cards[0].eventCount == 1)
        #expect(presentation.cards[0].status == .degraded)
        #expect(presentation.cards[0].lastDiagnosticMessage == "Network failed")
    }
}
