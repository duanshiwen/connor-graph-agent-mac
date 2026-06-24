import Foundation
import ConnorGraphCore

public struct CalendarCalDAVDiscoveryResult: Sendable, Equatable {
    public var principalURL: URL?
    public var calendarHomeSetURL: URL?
    public var collections: [DiscoveredCalendarCollection]
    public var collectionURLs: [CalendarID: URL]

    public init(principalURL: URL? = nil, calendarHomeSetURL: URL? = nil, collections: [DiscoveredCalendarCollection] = [], collectionURLs: [CalendarID: URL] = [:]) {
        self.principalURL = principalURL
        self.calendarHomeSetURL = calendarHomeSetURL
        self.collections = collections
        self.collectionURLs = collectionURLs
    }
}

public struct CalendarCalDAVDiscoveryService: Sendable {
    private let client: CalendarCalDAVHTTPClient
    private let parser: CalendarCalDAVDiscoveryParser

    public init(client: CalendarCalDAVHTTPClient = CalendarCalDAVHTTPClient(), parser: CalendarCalDAVDiscoveryParser = CalendarCalDAVDiscoveryParser()) {
        self.client = client
        self.parser = parser
    }

    public func discover(baseURL: URL, credential: String?) async throws -> CalendarCalDAVDiscoveryResult {
        let normalizedBase = normalizedBaseURL(baseURL)
        let principalBody = """
        <?xml version="1.0" encoding="utf-8" ?>
        <d:propfind xmlns:d="DAV:"><d:prop><d:current-user-principal /></d:prop></d:propfind>
        """
        let principalResponse = try await client.propfind(url: normalizedBase, depth: "0", body: principalBody, credential: credential)
        let principalHref = try parser.currentUserPrincipal(from: Data(principalResponse.body.utf8))
        let principalURL = resolve(principalHref, relativeTo: normalizedBase)

        let homeBody = """
        <?xml version="1.0" encoding="utf-8" ?>
        <d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:prop><c:calendar-home-set /></d:prop></d:propfind>
        """
        let homeResponse = try await client.propfind(url: principalURL, depth: "0", body: homeBody, credential: credential)
        let homeHref = try parser.calendarHomeSet(from: Data(homeResponse.body.utf8))
        let homeURL = resolve(homeHref, relativeTo: normalizedBase)

        let collectionBody = """
        <?xml version="1.0" encoding="utf-8" ?>
        <d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" xmlns:cs="http://calendarserver.org/ns/"><d:prop><d:displayname /><cs:getctag /><c:calendar-color /><c:supported-calendar-component-set /></d:prop></d:propfind>
        """
        let collectionResponse = try await client.propfind(url: homeURL, depth: "1", body: collectionBody, credential: credential)
        let discovered = try parser.calendarCollections(from: Data(collectionResponse.body.utf8))
        var collectionURLs: [CalendarID: URL] = [:]
        let collections = discovered.map { collection in
            let url = resolve(collection.href, relativeTo: normalizedBase)
            let id = CalendarID(rawValue: calendarID(for: url))
            collectionURLs[id] = url
            return DiscoveredCalendarCollection(
                id: id,
                displayName: collection.displayName,
                colorHex: collection.colorHex,
                isReadOnly: true
            )
        }
        return CalendarCalDAVDiscoveryResult(principalURL: principalURL, calendarHomeSetURL: homeURL, collections: collections, collectionURLs: collectionURLs)
    }

    private func normalizedBaseURL(_ url: URL) -> URL {
        if url.path.isEmpty { return url.appendingPathComponent("/") }
        return url
    }

    private func resolve(_ href: String, relativeTo baseURL: URL) -> URL {
        URL(string: href, relativeTo: baseURL)?.absoluteURL ?? baseURL
    }

    private func calendarID(for url: URL) -> String {
        let raw = "caldav-\(url.absoluteString)"
        let sanitized = raw.lowercased().map { character -> Character in
            if character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == ".") { return character }
            return "-"
        }
        return String(sanitized).replacingOccurrences(of: #"[-.]{2,}"#, with: "-", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "-."))
    }
}
