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
        guard !endpoint.host.isEmpty, endpoint.port > 0 else {
            return MailAccountHealth(status: .blocked, summary: "SMTP endpoint is incomplete", blockingReasons: ["Missing SMTP host or port"])
        }
        guard endpoint.security == .tls || endpoint.security == .startTLS else {
            return MailAccountHealth(status: .degraded, summary: "SMTP endpoint uses insecure transport", blockingReasons: ["SMTP requires TLS or STARTTLS for commercial sending"])
        }
        return MailAccountHealth(
            status: .ready,
            summary: "SMTP send channel configured for \(endpoint.host):\(endpoint.port) with \(endpoint.security.rawValue)",
            blockingReasons: []
        )
    }
}

public struct MailJMAPAdapter: MailProtocolAdapter {
    public var protocolKind: MailProtocolKind { .jmap }
    public init() {}
    public func testConnection(endpoint: MailServerEndpoint) async throws -> MailAccountHealth { MailAccountHealth(status: .degraded, summary: "JMAP reserved adapter skeleton for \(endpoint.host)") }
}

public enum MailProtocolSupportPolicy {
    public static let supportedProtocols: Set<MailProtocolKind> = [.imap, .smtp, .jmap]

    public static func isSupported(_ kind: MailProtocolKind) -> Bool {
        supportedProtocols.contains(kind)
    }
}
