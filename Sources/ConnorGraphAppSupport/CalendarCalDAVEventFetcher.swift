import Foundation
import ConnorGraphCore

public struct CalendarCalDAVEventFetcher: Sendable {
    private let client: CalendarCalDAVHTTPClient
    private let parser: ICalendarParser

    public init(client: CalendarCalDAVHTTPClient = CalendarCalDAVHTTPClient(), parser: ICalendarParser = ICalendarParser()) {
        self.client = client
        self.parser = parser
    }

    public func fetchEvents(collection: CalendarCollection, collectionURL: URL, credential: String?, windowStart: Date, windowEnd: Date) async throws -> [CalendarEvent] {
        let body = calendarQueryBody(windowStart: windowStart, windowEnd: windowEnd)
        let response = try await client.report(url: collectionURL, depth: "1", body: body, credential: credential)
        let objects = try CalendarCalDAVCalendarDataParser.calendarDataObjects(from: Data(response.body.utf8))
        return try objects.flatMap { object in
            try parser.events(from: object.calendarData).map { event in
                CalendarEvent(
                    id: CalendarEventID(rawValue: "caldav-\(collection.id.rawValue)-\(event.uid)"),
                    calendarID: collection.id,
                    title: event.summary,
                    start: CalendarEventDateTime(date: event.start.date, timeZoneIdentifier: event.start.timeZoneIdentifier),
                    end: CalendarEventDateTime(date: event.end?.date ?? event.start.date, timeZoneIdentifier: event.end?.timeZoneIdentifier ?? event.start.timeZoneIdentifier),
                    isAllDay: event.isAllDay,
                    location: event.location,
                    url: event.url,
                    notes: event.description,
                    attendees: event.attendees.enumerated().map { index, attendee in
                        CalendarAttendee(
                            id: CalendarAttendeeID(rawValue: "caldav-\(collection.id.rawValue)-\(event.uid)-attendee-\(index)"),
                            name: attendee.name,
                            email: attendee.email,
                            role: calendarRole(from: attendee.role),
                            responseStatus: calendarResponseStatus(from: attendee.participationStatus)
                        )
                    },
                    recurrenceSummary: event.recurrenceRule.map(CalendarRecurrenceSummary.init(ruleDescription:)),
                    updatedAt: event.lastModified ?? Date()
                )
            }
        }
    }

    private func calendarQueryBody(windowStart: Date, windowEnd: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return """
        <?xml version="1.0" encoding="utf-8" ?>
        <c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
          <d:prop><d:getetag /><c:calendar-data /></d:prop>
          <c:filter><c:comp-filter name="VCALENDAR"><c:comp-filter name="VEVENT"><c:time-range start="\(formatter.string(from: windowStart))" end="\(formatter.string(from: windowEnd))" /></c:comp-filter></c:comp-filter></c:filter>
        </c:calendar-query>
        """
    }

    private func calendarRole(from role: String?) -> CalendarAttendeeRole {
        switch role?.uppercased() {
        case "REQ-PARTICIPANT": return .required
        case "OPT-PARTICIPANT": return .optional
        case "NON-PARTICIPANT": return .resource
        default: return .unknown
        }
    }

    private func calendarResponseStatus(from status: String?) -> CalendarAttendeeResponseStatus {
        switch status?.uppercased() {
        case "NEEDS-ACTION": return .needsAction
        case "ACCEPTED": return .accepted
        case "DECLINED": return .declined
        case "TENTATIVE": return .tentative
        case "DELEGATED": return .delegated
        default: return .unknown
        }
    }
}

private struct CalendarCalDAVCalendarDataObject: Sendable, Equatable {
    var href: String
    var etag: String?
    var calendarData: String
}

private final class CalendarCalDAVCalendarDataParser: NSObject, XMLParserDelegate {
    private(set) var objects: [CalendarCalDAVCalendarDataObject] = []
    private var currentHref = ""
    private var currentETag: String?
    private var currentCalendarData = ""
    private var elementStack: [String] = []
    private var textBuffer = ""
    private var insideResponse = false

    static func calendarDataObjects(from data: Data) throws -> [CalendarCalDAVCalendarDataObject] {
        let delegate = CalendarCalDAVCalendarDataParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw CalendarCalDAVDiscoveryParserError.invalidXML }
        return delegate.objects
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let local = Self.localName(elementName)
        elementStack.append(local)
        textBuffer = ""
        if local == "response" {
            insideResponse = true
            currentHref = ""
            currentETag = nil
            currentCalendarData = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { textBuffer += string }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { textBuffer += String(data: CDATABlock, encoding: .utf8) ?? "" }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let local = Self.localName(elementName)
        let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if insideResponse {
            switch local {
            case "href": currentHref = text
            case "getetag": currentETag = text
            case "calendar-data": currentCalendarData = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            case "response":
                if !currentCalendarData.isEmpty { objects.append(CalendarCalDAVCalendarDataObject(href: currentHref, etag: currentETag, calendarData: currentCalendarData)) }
                insideResponse = false
            default: break
            }
        }
        if !elementStack.isEmpty { elementStack.removeLast() }
        textBuffer = ""
    }

    private static func localName(_ name: String) -> String {
        if let separator = name.lastIndex(of: ":") { return String(name[name.index(after: separator)...]).lowercased() }
        return name.lowercased()
    }
}
