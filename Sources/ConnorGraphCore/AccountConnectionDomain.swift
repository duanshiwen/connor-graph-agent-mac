import Foundation

public struct ConnectedAccountID: RawRepresentable, Codable, Sendable, Equatable, Hashable, Identifiable {
    public var rawValue: String
    public var id: String { rawValue }
    public init(rawValue: String) { self.rawValue = rawValue }
}

public enum ConnectedAccountProviderKind: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case appleICloud
    case microsoft365
    case google
    case qq
    case netEase
    case genericIMAPSMTP
    case genericCalDAVCardDAV
    case localFixture

    public var defaultCapabilities: [ConnectedAccountCapabilityKind] {
        switch self {
        case .appleICloud:
            return [.mail, .calendar, .contacts]
        case .microsoft365, .google:
            return []
        case .qq, .netEase, .genericIMAPSMTP:
            return [.mail]
        case .genericCalDAVCardDAV:
            return [.calendar, .contacts]
        case .localFixture:
            return [.mail, .calendar, .contacts]
        }
    }

    public var isSupportedForNewConnection: Bool {
        switch self {
        case .microsoft365, .google:
            return false
        case .appleICloud, .qq, .netEase, .genericIMAPSMTP, .genericCalDAVCardDAV, .localFixture:
            return true
        }
    }
}

public enum ConnectedAccountCapabilityKind: String, Codable, Sendable, Equatable, Hashable, CaseIterable, Comparable {
    case mail
    case calendar
    case contacts

    public static func < (lhs: ConnectedAccountCapabilityKind, rhs: ConnectedAccountCapabilityKind) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    private var sortOrder: Int {
        switch self {
        case .mail: return 0
        case .calendar: return 1
        case .contacts: return 2
        }
    }
}

public enum ConnectedAccountCapabilityStatus: String, Codable, Sendable, Equatable, Hashable {
    case enabled
    case disabled
    case unavailable
    case needsConfiguration
}

public enum ConnectedAccountAuthMode: String, Codable, Sendable, Equatable, Hashable {
    case oauth2
    case password
    case appPassword
    case none
}

public struct ConnectedAccountCredentialBinding: Codable, Sendable, Equatable, Hashable {
    public var keychainService: String
    public var accountName: String
    public var authMode: ConnectedAccountAuthMode

    public init(keychainService: String, accountName: String, authMode: ConnectedAccountAuthMode) {
        self.keychainService = keychainService
        self.accountName = accountName
        self.authMode = authMode
    }
}

public struct ConnectedAccountCapability: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var kind: ConnectedAccountCapabilityKind
    public var status: ConnectedAccountCapabilityStatus
    public var endpointURL: URL?
    public var note: String?

    public var id: ConnectedAccountCapabilityKind { kind }

    public init(kind: ConnectedAccountCapabilityKind, status: ConnectedAccountCapabilityStatus = .enabled, endpointURL: URL? = nil, note: String? = nil) {
        self.kind = kind
        self.status = status
        self.endpointURL = endpointURL
        self.note = note
    }
}

public struct ConnectedAccount: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: ConnectedAccountID
    public var provider: ConnectedAccountProviderKind
    public var displayName: String
    public var primaryIdentifier: String
    public var credentialBinding: ConnectedAccountCredentialBinding?
    public var capabilities: [ConnectedAccountCapability]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: ConnectedAccountID,
        provider: ConnectedAccountProviderKind,
        displayName: String,
        primaryIdentifier: String,
        credentialBinding: ConnectedAccountCredentialBinding? = nil,
        capabilities: [ConnectedAccountCapability] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.provider = provider
        self.displayName = displayName
        self.primaryIdentifier = primaryIdentifier
        self.credentialBinding = credentialBinding
        self.capabilities = capabilities
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var enabledCapabilities: [ConnectedAccountCapabilityKind] {
        capabilities
            .filter { $0.status == .enabled }
            .map(\.kind)
            .sorted()
    }

    public func capability(_ kind: ConnectedAccountCapabilityKind) -> ConnectedAccountCapability? {
        capabilities.first { $0.kind == kind }
    }
}
