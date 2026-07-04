import Foundation
import ConnorGraphCore

#if canImport(MailCore)
import MailCore
#endif

public enum MailBackendPreference: Sendable, Equatable {
    case automatic
    case mailCore2
    case legacy
}

public struct MailBackendStrategy: Sendable, Equatable {
    public var preference: MailBackendPreference
    public var isMailCore2Available: Bool

    public init(preference: MailBackendPreference = .automatic, isMailCore2Available: Bool = MailCore2Availability.isAvailable) {
        self.preference = preference
        self.isMailCore2Available = isMailCore2Available
    }

    public var primaryBackendName: String {
        switch preference {
        case .automatic:
            return isMailCore2Available ? "mailcore2" : "legacy"
        case .mailCore2:
            return "mailcore2"
        case .legacy:
            return "legacy"
        }
    }

    public var fallbackBackendName: String? {
        switch preference {
        case .automatic:
            return isMailCore2Available ? "legacy" : nil
        case .mailCore2:
            return "legacy"
        case .legacy:
            return nil
        }
    }
}

public enum MailCore2Availability: Sendable {
    public static var isAvailable: Bool {
        #if canImport(MailCore)
        return true
        #else
        return false
        #endif
    }
}

public enum MailProtocolBackendError: Error, Sendable, Equatable, CustomStringConvertible {
    case unavailable(String)
    case unsupported(String)

    public var description: String {
        switch self {
        case .unavailable(let message): "Mail protocol backend unavailable: \(message)"
        case .unsupported(let message): "Mail protocol backend unsupported: \(message)"
        }
    }
}

public struct MailBackendFetchedMessage: Sendable, Equatable {
    public var uid: String
    public var flags: String
    public var header: String
    public var rawHeaderData: Data?
    public var snippet: String
    public var rawBodyData: Data?
    public var fallbackSequenceDate: Date
    public var remoteMailbox: RemoteIMAPMailbox?

    public init(uid: String, flags: String = "", header: String = "", rawHeaderData: Data? = nil, snippet: String = "", rawBodyData: Data? = nil, fallbackSequenceDate: Date = Date(), remoteMailbox: RemoteIMAPMailbox? = nil) {
        self.uid = uid
        self.flags = flags
        self.header = header
        self.rawHeaderData = rawHeaderData
        self.snippet = snippet
        self.rawBodyData = rawBodyData
        self.fallbackSequenceDate = fallbackSequenceDate
        self.remoteMailbox = remoteMailbox
    }
}

public struct MailBackendMailboxSnapshot: Sendable, Equatable {
    public var mailbox: RemoteIMAPMailbox
    public var exists: Int
    public var unreadCount: Int
    public var uidValidity: String?
    public var highestUID: String?
    public var messages: [MailBackendFetchedMessage]

    public init(mailbox: RemoteIMAPMailbox, exists: Int = 0, unreadCount: Int = 0, uidValidity: String? = nil, highestUID: String? = nil, messages: [MailBackendFetchedMessage] = []) {
        self.mailbox = mailbox
        self.exists = exists
        self.unreadCount = unreadCount
        self.uidValidity = uidValidity
        self.highestUID = highestUID
        self.messages = messages
    }
}

public protocol MailProtocolBackend: Sendable {
    var backendName: String { get }

    func discoverMailboxes(account: MailAccount, credential: String) async throws -> [RemoteIMAPMailbox]
    func fetchMailboxSnapshots(account: MailAccount, credential: String, mailboxes: [RemoteIMAPMailbox], knownUIDsByMailboxID: [MailMailboxID: Set<String>], uidValidityByMailboxID: [MailMailboxID: String?], messageLimit: Int) async throws -> [MailBackendMailboxSnapshot]
    func fetchMessageBody(account: MailAccount, credential: String, uid: String, mailbox: RemoteIMAPMailbox, fallbackRecipient: MailAddress, snippet: String) async throws -> MailMessageDetail?
}

public struct MailCore2MailBackend: MailProtocolBackend {
    public let backendName = "mailcore2"

    public init() {}

    public func discoverMailboxes(account: MailAccount, credential: String) async throws -> [RemoteIMAPMailbox] {
        try ensureAvailable()
        throw MailProtocolBackendError.unsupported("MailCore2 mailbox discovery is introduced in a later task")
    }

    public func fetchMailboxSnapshots(account: MailAccount, credential: String, mailboxes: [RemoteIMAPMailbox], knownUIDsByMailboxID: [MailMailboxID: Set<String>], uidValidityByMailboxID: [MailMailboxID: String?], messageLimit: Int) async throws -> [MailBackendMailboxSnapshot] {
        try ensureAvailable()
        throw MailProtocolBackendError.unsupported("MailCore2 header sync is introduced in a later task")
    }

    public func fetchMessageBody(account: MailAccount, credential: String, uid: String, mailbox: RemoteIMAPMailbox, fallbackRecipient: MailAddress, snippet: String) async throws -> MailMessageDetail? {
        try ensureAvailable()
        throw MailProtocolBackendError.unsupported("MailCore2 body fetch is introduced in a later task")
    }

    private func ensureAvailable() throws {
        guard MailCore2Availability.isAvailable else {
            throw MailProtocolBackendError.unavailable("MailCore framework cannot be imported")
        }
    }

    #if canImport(MailCore)
    public func makeIMAPSession(hostname: String, port: UInt32, username: String, password: String) -> MCOIMAPSession {
        let session = MCOIMAPSession()
        session.hostname = hostname
        session.port = port
        session.username = username
        session.password = password
        session.connectionType = .TLS
        return session
    }
    #endif
}
