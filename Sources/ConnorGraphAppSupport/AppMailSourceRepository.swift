import Foundation
import ConnorGraphCore

public protocol MailSourceRepository: Sendable {
    func listAccounts() async throws -> [MailAccount]
    func saveAccount(_ account: MailAccount) async throws
    func account(id: MailAccountID) async throws -> MailAccount?
}

/// Combined protocol for all mail store operations used by AppViewModel
public protocol MailStoreProtocol: MailSourceRepository, TimeAwareMailSourceCache {
    func saveMessagesBatch(_ messages: [MailMessageDetail]) async throws
    func allMessageIDs() async throws -> [MailMessageID]
    func presentation() async throws -> NativeMailBrowserPresentation
}
