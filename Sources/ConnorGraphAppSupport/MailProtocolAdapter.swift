import Foundation
import ConnorGraphCore

public protocol MailProtocolAdapter: Sendable {
    var protocolKind: MailProtocolKind { get }
    func testConnection(endpoint: MailServerEndpoint) async throws -> MailAccountHealth
}

public struct MailIMAPAdapter: MailProtocolAdapter {
    public var protocolKind: MailProtocolKind { .imap }
    public init() {}
    public func testConnection(endpoint: MailServerEndpoint) async throws -> MailAccountHealth {
        guard endpoint.protocolKind == .imap else {
            return MailAccountHealth(status: .blocked, summary: "Endpoint protocol is not IMAP", blockingReasons: ["Endpoint protocol is not IMAP"])
        }
        return MailAccountHealth(
            status: .degraded,
            summary: "IMAP adapter skeleton validated endpoint \(endpoint.host):\(endpoint.port), but no remote login or message fetch has run",
            blockingReasons: ["IMAP network synchronization is not implemented yet"]
        )
    }
}

public struct MailSMTPAdapter: MailProtocolAdapter {
    public var protocolKind: MailProtocolKind { .smtp }
    public init() {}
    public func testConnection(endpoint: MailServerEndpoint) async throws -> MailAccountHealth {
        guard endpoint.protocolKind == .smtp else {
            return MailAccountHealth(status: .blocked, summary: "Endpoint protocol is not SMTP", blockingReasons: ["Endpoint protocol is not SMTP"])
        }
        return MailAccountHealth(
            status: .degraded,
            summary: "SMTP adapter skeleton validated endpoint \(endpoint.host):\(endpoint.port), but no remote login or send capability has run",
            blockingReasons: ["SMTP network authentication is not implemented yet"]
        )
    }
}

public struct MailJMAPAdapter: MailProtocolAdapter {
    public var protocolKind: MailProtocolKind { .jmap }
    public init() {}
    public func testConnection(endpoint: MailServerEndpoint) async throws -> MailAccountHealth { MailAccountHealth(status: .degraded, summary: "JMAP reserved adapter skeleton for \(endpoint.host)") }
}

public struct MailGmailAPIAdapter: MailProtocolAdapter {
    public var protocolKind: MailProtocolKind { .gmailAPI }
    public init() {}
    public func testConnection(endpoint: MailServerEndpoint) async throws -> MailAccountHealth { MailAccountHealth(status: .degraded, summary: "Gmail API reserved adapter skeleton for \(endpoint.host)") }
}

public struct MailMicrosoftGraphAdapter: MailProtocolAdapter {
    public var protocolKind: MailProtocolKind { .microsoftGraph }
    public init() {}
    public func testConnection(endpoint: MailServerEndpoint) async throws -> MailAccountHealth { MailAccountHealth(status: .degraded, summary: "Microsoft Graph reserved adapter skeleton for \(endpoint.host)") }
}
