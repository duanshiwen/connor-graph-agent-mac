import Foundation

public struct MailAccountID: RawRepresentable, Codable, Sendable, Equatable, Hashable, Identifiable {
    public var rawValue: String
    public var id: String { rawValue }
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct MailIdentityID: RawRepresentable, Codable, Sendable, Equatable, Hashable, Identifiable {
    public var rawValue: String
    public var id: String { rawValue }
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct MailMailboxID: RawRepresentable, Codable, Sendable, Equatable, Hashable, Identifiable {
    public var rawValue: String
    public var id: String { rawValue }
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct MailMessageID: RawRepresentable, Codable, Sendable, Equatable, Hashable, Identifiable {
    public var rawValue: String
    public var id: String { rawValue }
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct MailThreadID: RawRepresentable, Codable, Sendable, Equatable, Hashable, Identifiable {
    public var rawValue: String
    public var id: String { rawValue }
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct MailDraftID: RawRepresentable, Codable, Sendable, Equatable, Hashable, Identifiable {
    public var rawValue: String
    public var id: String { rawValue }
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct MailAttachmentID: RawRepresentable, Codable, Sendable, Equatable, Hashable, Identifiable {
    public var rawValue: String
    public var id: String { rawValue }
    public init(rawValue: String) { self.rawValue = rawValue }
}

public enum MailProviderKind: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case genericIMAPSMTP
    case gmail
    case microsoft365
    case jmap
    case localFixture
}

public enum MailProtocolKind: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case imap
    case smtp
    case jmap
    case gmailAPI
    case microsoftGraph
}

public enum MailConnectionSecurity: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case tls
    case startTLS
    case none
}

public enum MailAuthMode: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case oauth2
    case password
    case appPassword
    case none
}

public struct MailCredentialBinding: Codable, Sendable, Equatable, Hashable {
    public var credentialNamespace: String
    public var accountName: String
    public var authMode: MailAuthMode

    public init(credentialNamespace: String, accountName: String, authMode: MailAuthMode) {
        self.credentialNamespace = credentialNamespace
        self.accountName = accountName
        self.authMode = authMode
    }

    @available(*, deprecated, renamed: "init(credentialNamespace:accountName:authMode:)")
    public init(keychainService: String, accountName: String, authMode: MailAuthMode) {
        self.init(credentialNamespace: keychainService, accountName: accountName, authMode: authMode)
    }

    private enum CodingKeys: String, CodingKey {
        case credentialNamespace
        case keychainService
        case accountName
        case authMode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        credentialNamespace = try container.decodeIfPresent(String.self, forKey: .credentialNamespace)
            ?? container.decode(String.self, forKey: .keychainService)
        accountName = try container.decode(String.self, forKey: .accountName)
        authMode = try container.decode(MailAuthMode.self, forKey: .authMode)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(credentialNamespace, forKey: .credentialNamespace)
        try container.encode(accountName, forKey: .accountName)
        try container.encode(authMode, forKey: .authMode)
    }
}

public struct MailServerEndpoint: Codable, Sendable, Equatable, Hashable {
    public var host: String
    public var port: Int
    public var security: MailConnectionSecurity
    public var protocolKind: MailProtocolKind

    public init(host: String, port: Int, security: MailConnectionSecurity, protocolKind: MailProtocolKind) {
        self.host = host
        self.port = port
        self.security = security
        self.protocolKind = protocolKind
    }
}

public struct MailAddress: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String { email.lowercased() }
    public var name: String?
    public var email: String

    public init(name: String? = nil, email: String) {
        self.name = name
        self.email = email
    }
}

public struct MailIdentity: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: MailIdentityID
    public var displayName: String
    public var address: MailAddress
    public var canSend: Bool

    public init(id: MailIdentityID, displayName: String, address: MailAddress, canSend: Bool = true) {
        self.id = id
        self.displayName = displayName
        self.address = address
        self.canSend = canSend
    }
}

public enum MailAccountHealthStatus: String, Codable, Sendable, Equatable, Hashable {
    case ready
    case degraded
    case blocked
    case unauthenticated
    case unknown
}

public struct MailAccountHealth: Codable, Sendable, Equatable, Hashable {
    public var status: MailAccountHealthStatus
    public var checkedAt: Date
    public var summary: String
    public var blockingReasons: [String]

    public init(status: MailAccountHealthStatus, checkedAt: Date = Date(), summary: String, blockingReasons: [String] = []) {
        self.status = status
        self.checkedAt = checkedAt
        self.summary = summary
        self.blockingReasons = blockingReasons
    }
}

public struct MailAccount: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: MailAccountID
    public var provider: MailProviderKind
    public var displayName: String
    public var identities: [MailIdentity]
    public var incoming: MailServerEndpoint?
    public var outgoing: MailServerEndpoint?
    public var credentialBinding: MailCredentialBinding?
    public var health: MailAccountHealth
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: MailAccountID,
        provider: MailProviderKind,
        displayName: String,
        identities: [MailIdentity],
        incoming: MailServerEndpoint? = nil,
        outgoing: MailServerEndpoint? = nil,
        credentialBinding: MailCredentialBinding? = nil,
        health: MailAccountHealth = MailAccountHealth(status: .unknown, summary: "Not checked"),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.provider = provider
        self.displayName = displayName
        self.identities = identities
        self.incoming = incoming
        self.outgoing = outgoing
        self.credentialBinding = credentialBinding
        self.health = health
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum MailMailboxRole: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case inbox
    case sent
    case drafts
    case archive
    case trash
    case spam
    case custom
}

public struct MailSyncCursor: Codable, Sendable, Equatable, Hashable {
    public var value: String
    public var updatedAt: Date
    public var uidValidity: String?

    public init(value: String, updatedAt: Date = Date(), uidValidity: String? = nil) {
        self.value = value
        self.updatedAt = updatedAt
        self.uidValidity = uidValidity
    }
}

public struct MailMailboxStatus: Codable, Sendable, Equatable, Hashable {
    public var messageCount: Int
    public var unreadCount: Int
    public var syncCursor: MailSyncCursor?
    public var lastSyncedAt: Date?

    public init(messageCount: Int = 0, unreadCount: Int = 0, syncCursor: MailSyncCursor? = nil, lastSyncedAt: Date? = nil) {
        self.messageCount = messageCount
        self.unreadCount = unreadCount
        self.syncCursor = syncCursor
        self.lastSyncedAt = lastSyncedAt
    }
}

public struct MailMailbox: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: MailMailboxID
    public var accountID: MailAccountID
    public var name: String
    public var path: String
    public var role: MailMailboxRole
    public var status: MailMailboxStatus

    public init(id: MailMailboxID, accountID: MailAccountID, name: String, path: String, role: MailMailboxRole, status: MailMailboxStatus = MailMailboxStatus()) {
        self.id = id
        self.accountID = accountID
        self.name = name
        self.path = path
        self.role = role
        self.status = status
    }
}

public struct MailMessageFlags: Codable, Sendable, Equatable, Hashable {
    public var isRead: Bool
    public var isFlagged: Bool
    public var isAnswered: Bool
    public var isDeleted: Bool

    public init(isRead: Bool = false, isFlagged: Bool = false, isAnswered: Bool = false, isDeleted: Bool = false) {
        self.isRead = isRead
        self.isFlagged = isFlagged
        self.isAnswered = isAnswered
        self.isDeleted = isDeleted
    }
}
