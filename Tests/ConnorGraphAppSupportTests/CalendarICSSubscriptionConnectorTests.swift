import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Calendar ICS Subscription Connector Tests")
struct CalendarICSSubscriptionConnectorTests {
    @Test func validationRejectsMissingAndUnsupportedSubscriptionURLs() async throws {
        let connector = CalendarICSSubscriptionConnector()
        let missing = try await connector.validate(configuration: CalendarSourceConfiguration(sourceKind: .icsSubscription, authMode: .none), credential: nil)
        let unsupported = try await connector.validate(configuration: CalendarSourceConfiguration(sourceKind: .icsSubscription, authMode: .none, subscriptionURL: URL(string: "ftp://example.com/calendar.ics")), credential: nil)

        #expect(missing.status == .needsConfiguration)
        #expect(missing.blockingReasons.contains("missingSubscriptionURL"))
        #expect(unsupported.status == .blocked)
        #expect(unsupported.blockingReasons.contains("unsupportedURLScheme"))
    }

    @Test func syncMapsICalendarAttendeesIntoCalendarEvents() async throws {
        let account = CalendarAccount(
            id: CalendarAccountID(rawValue: "calendar-account-attendees"),
            provider: .genericCalDAVCardDAV,
            sourceKind: .icsSubscription,
            displayName: "Attendees",
            configuration: CalendarSourceConfiguration(sourceKind: .icsSubscription, authMode: .none, subscriptionURL: URL(string: "https://example.com/attendees.ics"))
        )
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:with-attendees
        SUMMARY:Meeting
        DTSTART:20260624T040000Z
        DTEND:20260624T050000Z
        ATTENDEE;CN=Alice;ROLE=REQ-PARTICIPANT;PARTSTAT=ACCEPTED:mailto:alice@example.com
        END:VEVENT
        END:VCALENDAR
        """
        let connector = CalendarICSSubscriptionConnector(now: { Date(timeIntervalSince1970: 1_782_278_400) }, fetchICS: { _ in ics })

        let result = try await connector.sync(request: CalendarSourceSyncRequest(account: account, runID: "run-attendees"))

        #expect(result.events.first?.attendees.first?.name == "Alice")
        #expect(result.events.first?.attendees.first?.email == "alice@example.com")
        #expect(result.events.first?.attendees.first?.responseStatus == .accepted)
    }

    @Test func syncAppliesConfiguredWindowAndReportsFilteredCount() async throws {
        let account = CalendarAccount(
            id: CalendarAccountID(rawValue: "calendar-account-window"),
            provider: .genericCalDAVCardDAV,
            sourceKind: .icsSubscription,
            displayName: "Windowed",
            configuration: CalendarSourceConfiguration(
                sourceKind: .icsSubscription,
                authMode: .none,
                subscriptionURL: URL(string: "https://example.com/window.ics"),
                syncWindowPastDays: 1,
                syncWindowFutureDays: 7
            )
        )
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:past
        SUMMARY:Too old
        DTSTART:20260601T040000Z
        DTEND:20260601T050000Z
        END:VEVENT
        BEGIN:VEVENT
        UID:inside
        SUMMARY:Inside window
        DTSTART:20260625T040000Z
        DTEND:20260625T050000Z
        END:VEVENT
        BEGIN:VEVENT
        UID:future
        SUMMARY:Too far
        DTSTART:20260720T040000Z
        DTEND:20260720T050000Z
        END:VEVENT
        END:VCALENDAR
        """
        let connector = CalendarICSSubscriptionConnector(now: { Date(timeIntervalSince1970: 1_782_278_400) }, fetchICS: { _ in ics })

        let result = try await connector.sync(request: CalendarSourceSyncRequest(account: account, runID: "run-window"))

        #expect(result.events.map(\.title) == ["Inside window"])
        #expect(result.insertedEvents == 1)
        #expect(result.diagnostics.contains { $0.code == "eventsFilteredBySyncWindow" && $0.summary.contains("2") })
    }

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
