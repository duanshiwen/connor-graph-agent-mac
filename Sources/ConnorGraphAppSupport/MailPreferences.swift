import Foundation
import ConnorGraphCore

public struct MailPreferences: Codable, Equatable, Sendable {
    public var defaultSendAccountID: MailAccountID?
    public var defaultSendIdentityID: MailIdentityID?

    public init(defaultSendAccountID: MailAccountID? = nil, defaultSendIdentityID: MailIdentityID? = nil) {
        self.defaultSendAccountID = defaultSendAccountID
        self.defaultSendIdentityID = defaultSendIdentityID
    }
}

public protocol MailPreferencesStore: Sendable {
    func load() async throws -> MailPreferences
    func save(_ preferences: MailPreferences) async throws
}

public actor FileBackedMailPreferencesStore: MailPreferencesStore {
    private let preferencesURL: URL
    private let fileManager: FileManager

    public init(preferencesURL: URL, fileManager: FileManager = .default) {
        self.preferencesURL = preferencesURL
        self.fileManager = fileManager
    }

    public init(storagePaths: AppStoragePaths, fileManager: FileManager = .default) {
        self.preferencesURL = storagePaths.mailPreferencesURL
        self.fileManager = fileManager
    }

    public func load() async throws -> MailPreferences {
        guard fileManager.fileExists(atPath: preferencesURL.path) else { return MailPreferences() }
        let data = try Data(contentsOf: preferencesURL)
        return try JSONDecoder().decode(MailPreferences.self, from: data)
    }

    public func save(_ preferences: MailPreferences) async throws {
        let directory = preferencesURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(preferences)
        try data.write(to: preferencesURL, options: [.atomic])
    }
}

public enum MailDefaultSendAccountReconciler {
    public static func reconcile(preferences: MailPreferences, accounts: [MailAccount]) -> MailPreferences {
        let sendableAccounts = accounts.filter { account in
            account.outgoing != nil && account.identities.contains(where: \.canSend)
        }
        guard !sendableAccounts.isEmpty else { return MailPreferences() }

        if let defaultAccountID = preferences.defaultSendAccountID,
           let account = sendableAccounts.first(where: { $0.id == defaultAccountID }) {
            let identity = preferredIdentity(in: account, identityID: preferences.defaultSendIdentityID)
            return MailPreferences(defaultSendAccountID: account.id, defaultSendIdentityID: identity?.id)
        }

        guard sendableAccounts.count == 1, let account = sendableAccounts.first else {
            return MailPreferences()
        }
        return MailPreferences(defaultSendAccountID: account.id, defaultSendIdentityID: preferredIdentity(in: account, identityID: nil)?.id)
    }

    private static func preferredIdentity(in account: MailAccount, identityID: MailIdentityID?) -> MailIdentity? {
        if let identityID, let identity = account.identities.first(where: { $0.id == identityID && $0.canSend }) {
            return identity
        }
        return account.identities.first(where: \.canSend)
    }
}

public extension AppStoragePaths {
    var mailPreferencesURL: URL {
        configDirectory.appendingPathComponent("mail-preferences.json")
    }
}
