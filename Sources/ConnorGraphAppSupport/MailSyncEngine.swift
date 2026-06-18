import Foundation
import ConnorGraphCore

public struct MailSyncEngine: Sendable, Equatable {
    public init() {}
    public func readiness(account: MailAccount, mailboxCount: Int, cursorCount: Int) -> MailAccountHealth {
        let blockers = [account.credentialBinding == nil ? "Missing credential binding" : nil, mailboxCount == 0 ? "No mailboxes discovered" : nil].compactMap { $0 }
        return MailAccountHealth(status: blockers.isEmpty ? .ready : .blocked, summary: "\(mailboxCount) mailboxes · \(cursorCount) cursors", blockingReasons: blockers)
    }
}
