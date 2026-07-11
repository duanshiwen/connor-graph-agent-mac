import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("iCalendar Event Serializer Tests")
struct ICalendarEventSerializerTests {
    @Test func serializesEscapedEventWithCRLFAndStableUID() throws {
        let draft = CalendarEventDraft(calendarID: .init(rawValue: "c"), title: "讨论,规划;下一步", start: .init(date: Date(timeIntervalSince1970: 1_782_276_400)), end: .init(date: Date(timeIntervalSince1970: 1_782_280_000)), location: "杭州\\会议室", notes: "第一行\n第二行")
        let value = try ICalendarEventSerializer().serialize(draft: draft, uid: "uid-1", timestamp: Date(timeIntervalSince1970: 1_782_270_000))
        #expect(value.contains("UID:uid-1\r\n"))
        #expect(value.contains("SUMMARY:讨论\\,规划\\;下一步\r\n"))
        #expect(value.contains("LOCATION:杭州\\\\会议室\r\n"))
        #expect(value.contains("DESCRIPTION:第一行\\n第二行\r\n"))
        #expect(!value.replacingOccurrences(of: "\r\n", with: "").contains("\n"))
        #expect(try ICalendarParser().events(from: value).first?.uid == "uid-1")
    }

    @Test func serializesAllDayAndFoldsLongUTF8Lines() throws {
        let draft = CalendarEventDraft(calendarID: .init(rawValue: "c"), title: String(repeating: "日程", count: 60), start: .init(date: Date(timeIntervalSince1970: 1_782_259_200), timeZoneIdentifier: "Asia/Shanghai"), end: .init(date: Date(timeIntervalSince1970: 1_782_345_600), timeZoneIdentifier: "Asia/Shanghai"), isAllDay: true)
        let value = try ICalendarEventSerializer().serialize(draft: draft, uid: "uid", timestamp: Date())
        #expect(value.contains("DTSTART;VALUE=DATE:"))
        #expect(value.contains("\r\n "))
        for line in value.components(separatedBy: "\r\n") where !line.isEmpty { #expect(line.utf8.count <= 75) }
    }
}
