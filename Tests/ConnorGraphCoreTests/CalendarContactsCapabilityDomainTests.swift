import Foundation
import Testing
import ConnorGraphCore

@Suite("Calendar and Contacts Capability Domain Tests")
struct CalendarContactsCapabilityDomainTests {
    @Test func connectedAccountCodableRoundTripsCapabilities() throws {
        let account = ConnectedAccount(
            id: ConnectedAccountID(rawValue: "connected-alice-example-com"),
            provider: .google,
            displayName: "Alice Google",
            primaryIdentifier: "alice@example.com",
            credentialBinding: ConnectedAccountCredentialBinding(keychainService: "Connor", accountName: "alice@example.com", authMode: .oauth2),
            capabilities: [
                ConnectedAccountCapability(kind: .mail, status: .enabled),
                ConnectedAccountCapability(kind: .calendar, status: .enabled),
                ConnectedAccountCapability(kind: .contacts, status: .disabled)
            ],
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )

        let data = try JSONEncoder().encode(account)
        let decoded = try JSONDecoder().decode(ConnectedAccount.self, from: data)

        #expect(decoded == account)
        #expect(decoded.enabledCapabilities == [.mail, .calendar])
        #expect(decoded.capability(.contacts)?.status == .disabled)
    }

    @Test func providerPresetsExposeDefaultCapabilities() {
        #expect(ConnectedAccountProviderKind.appleICloud.defaultCapabilities == [.mail, .calendar, .contacts])
        #expect(ConnectedAccountProviderKind.microsoft365.defaultCapabilities == [])
        #expect(ConnectedAccountProviderKind.google.defaultCapabilities == [])
        #expect(!ConnectedAccountProviderKind.microsoft365.isSupportedForNewConnection)
        #expect(!ConnectedAccountProviderKind.google.isSupportedForNewConnection)
        #expect(ConnectedAccountProviderKind.qq.defaultCapabilities == [.mail])
        #expect(ConnectedAccountProviderKind.netEase.defaultCapabilities == [.mail])
        #expect(ConnectedAccountProviderKind.genericIMAPSMTP.defaultCapabilities == [.mail])
    }

    @Test func calendarDomainCodableRoundTripsEvent() throws {
        let event = CalendarEvent(
            id: CalendarEventID(rawValue: "event-1"),
            calendarID: CalendarID(rawValue: "calendar-work"),
            title: "产品讨论",
            start: CalendarEventDateTime(date: Date(timeIntervalSince1970: 1_000), timeZoneIdentifier: "Asia/Shanghai"),
            end: CalendarEventDateTime(date: Date(timeIntervalSince1970: 4_600), timeZoneIdentifier: "Asia/Shanghai"),
            isAllDay: false,
            location: "杭州",
            url: URL(string: "https://example.com/meet"),
            notes: "讨论 Calendar capability",
            attendees: [CalendarAttendee(id: CalendarAttendeeID(rawValue: "attendee-1"), name: "诗闻", email: "shiwen@example.com", role: .required, responseStatus: .accepted)],
            recurrenceSummary: CalendarRecurrenceSummary(ruleDescription: "每周五"),
            updatedAt: Date(timeIntervalSince1970: 5_000)
        )

        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(CalendarEvent.self, from: data)

        #expect(decoded == event)
        #expect(decoded.durationSeconds == 3_600)
    }

    @Test func timeAnalysisComputesSignedDifferencesAndOverlaps() {
        let base = Date(timeIntervalSince1970: 1_000)
        let ranges = [
            TimeAnalysisRange(id: "a", start: base, end: base.addingTimeInterval(3_600)),
            TimeAnalysisRange(id: "b", start: base.addingTimeInterval(1_800), end: base.addingTimeInterval(5_400)),
            TimeAnalysisRange(id: "c", start: base.addingTimeInterval(7_200), end: base.addingTimeInterval(8_000))
        ]

        let result = TimeRangeAnalyzer().analyze(ranges: ranges)

        #expect(result.startDifferences.first { $0.leftID == "a" && $0.rightID == "b" }?.signedSeconds == 1_800)
        #expect(result.startDifferences.first { $0.leftID == "b" && $0.rightID == "a" }?.signedSeconds == -1_800)
        let overlap = result.overlaps.first { $0.leftID == "a" && $0.rightID == "b" }
        #expect(overlap?.overlaps == true)
        #expect(overlap?.overlapSeconds == 1_800)
        #expect(result.overlaps.first { $0.leftID == "a" && $0.rightID == "c" }?.overlaps == false)
    }
}
