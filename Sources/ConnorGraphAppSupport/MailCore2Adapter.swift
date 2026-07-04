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
        #if canImport(MailCore)
        guard let endpoint = account.incoming, endpoint.protocolKind == .imap else { return nil }
        guard let email = account.identities.first?.address.email, !email.isEmpty else { return nil }
        guard let numericUID = UInt32(uid) else { return nil }

        var lastError: Error?
        for username in MailIMAPInitialSyncService.candidateUsernames(email: email, provider: account.provider) {
            let session = makeIMAPSession(hostname: endpoint.host, port: UInt32(endpoint.port), username: username, password: credential)
            do {
                let rawData = try await fetchParsedMessageData(session: session, folder: mailbox.path, uid: numericUID)
                return try detail(fromRawData: rawData, account: account, uid: uid, mailbox: mailbox, fallbackRecipient: fallbackRecipient, snippet: snippet)
            } catch {
                lastError = error
                continue
            }
        }
        if let lastError { throw lastError }
        return nil
        #else
        throw MailProtocolBackendError.unavailable("MailCore framework cannot be imported")
        #endif
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
        session.timeout = 60
        return session
    }

    private func fetchParsedMessageData(session: MCOIMAPSession, folder: String, uid: UInt32) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let operation = session.fetchParsedMessageOperation(withFolder: folder, uid: uid)
            operation?.start { error, parser in
                if let error {
                    continuation.resume(throwing: error)
                } else if let rawData = parser?.data() as Data? {
                    continuation.resume(returning: rawData)
                } else {
                    continuation.resume(throwing: MailProtocolBackendError.unavailable("MailCore2 returned no parser data"))
                }
            }
        }
    }

    private func detail(fromRawData rawData: Data, account: MailAccount, uid: String, mailbox: RemoteIMAPMailbox, fallbackRecipient: MailAddress, snippet: String) throws -> MailMessageDetail {
        let parser = MCOMessageParser(data: rawData)
        let bodyResult = try MailCore2MIMEParser().parseFullMessageBody(rawData: rawData, fallbackString: snippet)
        let header = parser?.header
        let from = Self.mailAddress(from: header?.from) ?? MailAddress(email: "unknown@example.com")
        let to = Self.mailAddresses(from: header?.to)
        let cc = Self.mailAddresses(from: header?.cc)
        let subject = Self.nilIfEmpty(header?.subject) ?? "（无主题）"
        let date = header?.date as Date? ?? Date()
        let messageID = Self.nilIfEmpty(header?.messageID) ?? "imap-uid-\(uid)"
        let mailboxID = mailbox.mailboxID(accountID: account.id)
        let cleanSnippet = String(Self.normalizedWhitespace(Self.stripHTML(bodyResult.plainText)).prefix(300))
        let summary = MailMessageSummary(
            id: mailbox.messageID(accountID: account.id, uid: uid),
            accountID: account.id,
            mailboxID: mailboxID,
            threadID: MailThreadID(rawValue: messageID),
            subject: subject,
            from: from,
            to: to.isEmpty ? [fallbackRecipient] : to,
            cc: cc,
            date: date,
            snippet: cleanSnippet.isEmpty ? "（无正文摘要）" : cleanSnippet,
            flags: MailMessageFlags(),
            hasAttachments: false
        )
        let body = MailMessageBody(
            plainText: MailBodyPart(mimeType: "text/plain", text: bodyResult.plainText, byteCount: bodyResult.plainText.utf8.count),
            htmlText: bodyResult.htmlText.map { MailBodyPart(mimeType: "text/html", text: $0, byteCount: $0.utf8.count) },
            redactedPreview: String(bodyResult.plainText.prefix(500)),
            bodyHash: String(abs(bodyResult.plainText.hashValue))
        )
        return MailMessageDetail(summary: summary, headers: MailMessageHeaders(messageIDHeader: messageID, rawHeaderHash: String(abs(rawData.hashValue))), body: body)
    }

    private static func mailAddress(from address: MCOAddress?) -> MailAddress? {
        guard let mailbox = address?.mailbox, !mailbox.isEmpty else { return nil }
        return MailAddress(name: nilIfEmpty(address?.displayName), email: mailbox)
    }

    private static func mailAddresses(from addresses: [Any]?) -> [MailAddress] {
        (addresses ?? []).compactMap { $0 as? MCOAddress }.compactMap(mailAddress(from:))
    }

    private static func nilIfEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func stripHTML(_ value: String) -> String {
        value.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
    }

    private static func normalizedWhitespace(_ value: String) -> String {
        value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    #endif
}
