import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Calendar Contacts System Adapter Tests")
struct CalendarContactsSystemAdapterTests {
    @Test func eventKitAdapterMapsSystemEventSnapshot() {
        let snapshot = CalendarSystemEventSnapshot(
            identifier: "ek-1",
            calendarIdentifier: "work",
            title: "系统日程",
            startDate: Date(timeIntervalSince1970: 1_000),
            endDate: Date(timeIntervalSince1970: 4_600),
            isAllDay: false,
            location: "杭州",
            notes: "来自 EventKit snapshot"
        )

        let event = CalendarEventKitAdapter.map(snapshot: snapshot)

        #expect(event.id.rawValue == "ek-1")
        #expect(event.calendarID.rawValue == "work")
        #expect(event.title == "系统日程")
        #expect(event.durationSeconds == 3_600)
    }

    @Test func contactsSystemAdapterMapsContactSnapshot() {
        let snapshot = ContactsSystemContactSnapshot(
            identifier: "cn-1",
            givenName: "诗闻",
            familyName: "",
            organizationName: "Connor",
            emails: ["shiwen@example.com"]
        )

        let record = ContactsSystemAdapter.map(snapshot: snapshot)

        #expect(record.id.rawValue == "cn-1")
        #expect(record.givenName == "诗闻")
        #expect(record.emails.first?.email == "shiwen@example.com")
    }
}
