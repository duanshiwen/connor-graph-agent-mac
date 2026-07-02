import Foundation
import ConnorGraphCore

/// Mozilla autoconfig service for automatic email server discovery
public struct MailAutoconfigService: Sendable {
    public init() {}

    /// Discover email server settings using Mozilla autoconfig
    public func discover(email: String) async throws -> MailAutoconfigResult? {
        let domain = email.components(separatedBy: "@").last?.lowercased() ?? ""
        guard !domain.isEmpty else { return nil }

        // Try Mozilla autoconfig first
        if let result = try? await queryMozillaAutoconfig(domain: domain) {
            return result
        }

        // Fallback: try ISPDB
        if let result = try? await queryISPDB(domain: domain) {
            return result
        }

        return nil
    }

    /// Query Mozilla autoconfig database
    private func queryMozillaAutoconfig(domain: String) async throws -> MailAutoconfigResult? {
        let urlString = "https://autoconfig.thunderbird.net/v1.1/\(domain)"
        guard let url = URL(string: urlString) else { return nil }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }

        return try parseAutoconfigXML(data)
    }

    /// Query ISPDB (Internet Service Provider Database)
    private func queryISPDB(domain: String) async throws -> MailAutoconfigResult? {
        let urlString = "https://autoconfig.thunderbird.net/v1.1/\(domain)"
        guard let url = URL(string: urlString) else { return nil }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }

        return try parseAutoconfigXML(data)
    }

    /// Parse Mozilla autoconfig XML
    private func parseAutoconfigXML(_ data: Data) throws -> MailAutoconfigResult? {
        let parser = AutoconfigXMLParser()
        return try parser.parse(data)
    }
}

/// Result of autoconfig discovery
public struct MailAutoconfigResult: Sendable {
    public let incomingHost: String
    public let incomingPort: Int
    public let incomingSecurity: MailConnectionSecurity
    public let outgoingHost: String
    public let outgoingPort: Int
    public let outgoingSecurity: MailConnectionSecurity

    public init(
        incomingHost: String,
        incomingPort: Int,
        incomingSecurity: MailConnectionSecurity,
        outgoingHost: String,
        outgoingPort: Int,
        outgoingSecurity: MailConnectionSecurity
    ) {
        self.incomingHost = incomingHost
        self.incomingPort = incomingPort
        self.incomingSecurity = incomingSecurity
        self.outgoingHost = outgoingHost
        self.outgoingPort = outgoingPort
        self.outgoingSecurity = outgoingSecurity
    }
}

/// XML parser for Mozilla autoconfig format
private class AutoconfigXMLParser: NSObject, XMLParserDelegate {
    private var result: MailAutoconfigResult?
    private var currentElement = ""
    private var currentText = ""
    private var incomingHost = ""
    private var incomingPort = 993
    private var incomingSecurity: MailConnectionSecurity = .tls
    private var outgoingHost = ""
    private var outgoingPort = 587
    private var outgoingSecurity: MailConnectionSecurity = .startTLS
    private var isIncoming = false
    private var isOutgoing = false

    func parse(_ data: Data) throws -> MailAutoconfigResult? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else { return nil }

        guard !incomingHost.isEmpty, !outgoingHost.isEmpty else { return nil }

        return MailAutoconfigResult(
            incomingHost: incomingHost,
            incomingPort: incomingPort,
            incomingSecurity: incomingSecurity,
            outgoingHost: outgoingHost,
            outgoingPort: outgoingPort,
            outgoingSecurity: outgoingSecurity
        )
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""

        if elementName == "incomingServer" {
            isIncoming = true
            isOutgoing = false
        } else if elementName == "outgoingServer" {
            isIncoming = false
            isOutgoing = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if isIncoming {
            switch elementName {
            case "hostname":
                incomingHost = text
            case "port":
                incomingPort = Int(text) ?? 993
            case "socketType":
                incomingSecurity = parseSocketType(text)
            default:
                break
            }
        } else if isOutgoing {
            switch elementName {
            case "hostname":
                outgoingHost = text
            case "port":
                outgoingPort = Int(text) ?? 587
            case "socketType":
                outgoingSecurity = parseSocketType(text)
            default:
                break
            }
        }

        if elementName == "incomingServer" || elementName == "outgoingServer" {
            isIncoming = false
            isOutgoing = false
        }

        currentElement = ""
        currentText = ""
    }

    private func parseSocketType(_ type: String) -> MailConnectionSecurity {
        switch type.uppercased() {
        case "SSL", "TLS":
            return .tls
        case "STARTTLS":
            return .startTLS
        default:
            return .tls
        }
    }
}
