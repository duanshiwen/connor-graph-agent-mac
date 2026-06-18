import Foundation
import ConnorGraphCore

public protocol MailSourceRepository: Sendable {
    func listAccounts() async throws -> [MailAccount]
    func saveAccount(_ account: MailAccount) async throws
    func account(id: MailAccountID) async throws -> MailAccount?
}
