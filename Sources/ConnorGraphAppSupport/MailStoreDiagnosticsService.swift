import Foundation
import ConnorGraphCore

public struct MailStoreDiagnosticsSnapshot: Codable, Sendable, Equatable {
    public var currentStorePath: String
    public var currentStoreExists: Bool
    public var legacyStorePath: String
    public var legacyStoreExists: Bool
    public var legacyStoreNote: String
    public var accountCount: Int
    public var mailboxCount: Int
    public var messageCount: Int
    public var mailboxRoleCounts: [String: Int]

    public init(
        currentStorePath: String,
        currentStoreExists: Bool,
        legacyStorePath: String,
        legacyStoreExists: Bool,
        legacyStoreNote: String,
        accountCount: Int,
        mailboxCount: Int,
        messageCount: Int,
        mailboxRoleCounts: [String: Int]
    ) {
        self.currentStorePath = currentStorePath
        self.currentStoreExists = currentStoreExists
        self.legacyStorePath = legacyStorePath
        self.legacyStoreExists = legacyStoreExists
        self.legacyStoreNote = legacyStoreNote
        self.accountCount = accountCount
        self.mailboxCount = mailboxCount
        self.messageCount = messageCount
        self.mailboxRoleCounts = mailboxRoleCounts
    }
}

public struct MailStoreDiagnosticCounts: Sendable, Equatable {
    public var accounts: Int
    public var mailboxes: Int
    public var messages: Int
    public var mailboxRoles: [String: Int]

    public init(accounts: Int, mailboxes: Int, messages: Int, mailboxRoles: [String: Int]) {
        self.accounts = accounts
        self.mailboxes = mailboxes
        self.messages = messages
        self.mailboxRoles = mailboxRoles
    }
}

public struct MailStoreDiagnosticsService: Sendable {
    public var storagePaths: AppStoragePaths

    public init(storagePaths: AppStoragePaths) {
        self.storagePaths = storagePaths
    }

    public func snapshot() async throws -> MailStoreDiagnosticsSnapshot {
        let mailDirectory = storagePaths.applicationSupportDirectory.appendingPathComponent("mail", isDirectory: true)
        let currentURL = mailDirectory.appendingPathComponent("mail-source.sqlite")
        let legacyURL = mailDirectory.appendingPathComponent("mail.db")
        let store = FileBackedMailSourceStore(storagePaths: storagePaths)
        let counts = try await store.diagnosticCounts()

        return MailStoreDiagnosticsSnapshot(
            currentStorePath: currentURL.path,
            currentStoreExists: FileManager.default.fileExists(atPath: currentURL.path),
            legacyStorePath: legacyURL.path,
            legacyStoreExists: FileManager.default.fileExists(atPath: legacyURL.path),
            legacyStoreNote: "mail-source.sqlite is the current Connor mail UI/runtime store; mail.db is a legacy store if present and is not used by the current mail browser.",
            accountCount: counts.accounts,
            mailboxCount: counts.mailboxes,
            messageCount: counts.messages,
            mailboxRoleCounts: counts.mailboxRoles
        )
    }
}
