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
        MailAccountHealth(status: endpoint.protocolKind == .imap ? .ready : .blocked, summary: "IMAP adapter skeleton validated endpoint \(endpoint.host):\(endpoint.port)", blockingReasons: endpoint.protocolKind == .imap ? [] : ["Endpoint protocol is not IMAP"])
    }
}

public struct MailSMTPAdapter: MailProtocolAdapter {
    public var protocolKind: MailProtocolKind { .smtp }
    public init() {}
    public func testConnection(endpoint: MailServerEndpoint) async throws -> MailAccountHealth {
        MailAccountHealth(status: endpoint.protocolKind == .smtp ? .ready : .blocked, summary: "SMTP adapter skeleton validated endpoint \(endpoint.host):\(endpoint.port)", blockingReasons: endpoint.protocolKind == .smtp ? [] : ["Endpoint protocol is not SMTP"])
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
