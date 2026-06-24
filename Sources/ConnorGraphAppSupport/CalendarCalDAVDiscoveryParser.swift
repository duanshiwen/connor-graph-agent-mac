import Foundation

public enum CalendarCalDAVDiscoveryParserError: Error, Sendable, Equatable {
    case missingCurrentUserPrincipal
    case missingCalendarHomeSet
    case invalidXML
}

public struct CalendarCalDAVDiscoveredCollection: Sendable, Equatable {
    public var href: String
    public var displayName: String
    public var colorHex: String?

    public init(href: String, displayName: String, colorHex: String? = nil) {
        self.href = href
        self.displayName = displayName
        self.colorHex = colorHex
    }
}

public struct CalendarCalDAVDiscoveryParser: Sendable {
    public init() {}

    public func currentUserPrincipal(from data: Data) throws -> String {
        let document = try ParsedCalDAVMultistatus.parse(data)
        guard let value = document.responses.compactMap(\.currentUserPrincipal).first else {
            throw CalendarCalDAVDiscoveryParserError.missingCurrentUserPrincipal
        }
        return value
    }

    public func calendarHomeSet(from data: Data) throws -> String {
        let document = try ParsedCalDAVMultistatus.parse(data)
        guard let value = document.responses.compactMap(\.calendarHomeSet).first else {
            throw CalendarCalDAVDiscoveryParserError.missingCalendarHomeSet
        }
        return value
    }

    public func calendarCollections(from data: Data) throws -> [CalendarCalDAVDiscoveredCollection] {
        let document = try ParsedCalDAVMultistatus.parse(data)
        return document.responses.compactMap { response in
            guard response.supportedComponents.contains("VEVENT") else { return nil }
            let displayName = response.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            return CalendarCalDAVDiscoveredCollection(
                href: response.href,
                displayName: displayName?.isEmpty == false ? displayName! : response.href,
                colorHex: Self.normalizedColor(response.calendarColor)
            )
        }
    }

    private static func normalizedColor(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), value.hasPrefix("#") else { return nil }
        if value.count == 9 { value = String(value.prefix(7)) }
        return value.count == 7 ? value.uppercased() : nil
    }
}

private struct ParsedCalDAVMultistatus {
    var responses: [ParsedCalDAVResponse]

    static func parse(_ data: Data) throws -> ParsedCalDAVMultistatus {
        let delegate = CalDAVXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw CalendarCalDAVDiscoveryParserError.invalidXML }
        return ParsedCalDAVMultistatus(responses: delegate.responses)
    }
}

private struct ParsedCalDAVResponse {
    var href: String = ""
    var displayName: String?
    var currentUserPrincipal: String?
    var calendarHomeSet: String?
    var calendarColor: String?
    var supportedComponents: Set<String> = []
}

private final class CalDAVXMLDelegate: NSObject, XMLParserDelegate {
    private(set) var responses: [ParsedCalDAVResponse] = []
    private var currentResponse: ParsedCalDAVResponse?
    private var elementStack: [String] = []
    private var textBuffer = ""
    private var isInsideCurrentUserPrincipal = false
    private var isInsideCalendarHomeSet = false

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let local = Self.localName(elementName)
        elementStack.append(local)
        textBuffer = ""

        if local == "response" {
            currentResponse = ParsedCalDAVResponse()
        } else if local == "current-user-principal" {
            isInsideCurrentUserPrincipal = true
        } else if local == "calendar-home-set" {
            isInsideCalendarHomeSet = true
        } else if local == "comp", let name = attributeDict["name"]?.uppercased() {
            currentResponse?.supportedComponents.insert(name)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let local = Self.localName(elementName)
        let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)

        switch local {
        case "href":
            if isInsideCurrentUserPrincipal {
                currentResponse?.currentUserPrincipal = text
            } else if isInsideCalendarHomeSet {
                currentResponse?.calendarHomeSet = text
            } else if currentResponse?.href.isEmpty == true {
                currentResponse?.href = text
            }
        case "displayname":
            currentResponse?.displayName = text
        case "calendar-color":
            currentResponse?.calendarColor = text
        case "current-user-principal":
            isInsideCurrentUserPrincipal = false
        case "calendar-home-set":
            isInsideCalendarHomeSet = false
        case "response":
            if let currentResponse { responses.append(currentResponse) }
            currentResponse = nil
        default:
            break
        }

        if !elementStack.isEmpty { elementStack.removeLast() }
        textBuffer = ""
    }

    private static func localName(_ name: String) -> String {
        if let separator = name.lastIndex(of: ":") {
            return String(name[name.index(after: separator)...]).lowercased()
        }
        return name.lowercased()
    }
}
