import Foundation
import Testing
import ConnorGraphAppSupport

@Suite("Calendar CalDAV Discovery Parser Tests")
struct CalendarCalDAVDiscoveryParserTests {
    @Test func parserExtractsCurrentUserPrincipalAndCalendarHomeSet() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8" ?>
        <d:multistatus xmlns:d="DAV:" xmlns:cs="http://calendarserver.org/ns/" xmlns:c="urn:ietf:params:xml:ns:caldav">
          <d:response>
            <d:href>/</d:href>
            <d:propstat>
              <d:prop>
                <d:current-user-principal><d:href>/principals/users/shiwen/</d:href></d:current-user-principal>
                <c:calendar-home-set><d:href>/calendars/users/shiwen/</d:href></c:calendar-home-set>
              </d:prop>
              <d:status>HTTP/1.1 200 OK</d:status>
            </d:propstat>
          </d:response>
        </d:multistatus>
        """

        let parser = CalendarCalDAVDiscoveryParser()
        let principal = try parser.currentUserPrincipal(from: Data(xml.utf8))
        let homeSet = try parser.calendarHomeSet(from: Data(xml.utf8))

        #expect(principal == "/principals/users/shiwen/")
        #expect(homeSet == "/calendars/users/shiwen/")
    }

    @Test func parserExtractsCalendarCollections() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8" ?>
        <d:multistatus xmlns:d="DAV:" xmlns:cs="http://calendarserver.org/ns/" xmlns:c="urn:ietf:params:xml:ns:caldav" xmlns:ical="http://apple.com/ns/ical/">
          <d:response>
            <d:href>/calendars/users/shiwen/work/</d:href>
            <d:propstat>
              <d:prop>
                <d:displayname>Work</d:displayname>
                <ical:calendar-color>#FF9500FF</ical:calendar-color>
                <c:supported-calendar-component-set>
                  <c:comp name="VEVENT" />
                </c:supported-calendar-component-set>
              </d:prop>
              <d:status>HTTP/1.1 200 OK</d:status>
            </d:propstat>
          </d:response>
          <d:response>
            <d:href>/calendars/users/shiwen/tasks/</d:href>
            <d:propstat>
              <d:prop>
                <d:displayname>Tasks</d:displayname>
                <c:supported-calendar-component-set>
                  <c:comp name="VTODO" />
                </c:supported-calendar-component-set>
              </d:prop>
              <d:status>HTTP/1.1 200 OK</d:status>
            </d:propstat>
          </d:response>
        </d:multistatus>
        """

        let parser = CalendarCalDAVDiscoveryParser()
        let collections = try parser.calendarCollections(from: Data(xml.utf8))

        #expect(collections.count == 1)
        #expect(collections[0].href == "/calendars/users/shiwen/work/")
        #expect(collections[0].displayName == "Work")
        #expect(collections[0].colorHex == "#FF9500")
    }
}
