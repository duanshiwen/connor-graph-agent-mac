import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Calendar ICS Subscription Connector Tests")
struct CalendarICSSubscriptionConnectorTests {
    @Test func icsConnectorParsesSubscriptionIntoReadOnlyCollectionAndEvents() async throws {
        let accountID = CalendarAccountID(rawValue: "calendar-account-ics-holidays")
        let account = CalendarAccount(
            id: accountID,
            provider: .genericCalDAVCardDAV,
            sourceKind: .icsSubscription,
            displayName: "公开订阅",
            configuration: CalendarSourceConfiguration(
                sourceKind: .icsSubscription,
                authMode: .none,
                subscriptionURL: URL(string: "webcal://example.com/calendar.ics")
            )
        )
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:event-ics-1
        SUMMARY:公开活动
        DTSTART:20260624T040000Z
        DTEND:20260624T050000Z
        DESCRIPTION:ICS subscription event
        END:VEVENT
        END:VCALENDAR
        """
        let connector = CalendarICSSubscriptionConnector(fetchICS: { url in
            #expect(url.absoluteString == "https://example.com/calendar.ics")
            return ics
        })

        let result = try await connector.sync(request: CalendarSourceSyncRequest(account: account, runID: "run-ics"))

        #expect(result.sourceKind == .icsSubscription)
        #expect(result.updatedCollections == 1)
        #expect(result.insertedEvents == 1)
        #expect(result.collections.first?.isReadOnly == true)
        #expect(result.events.first?.title == "公开活动")
        #expect(result.events.first?.notes == "ICS subscription event")
    }
}
