import Foundation
import Testing
import ConnorGraphCore
@testable import ConnorGraphAppSupport

@Suite("Mail IMAP Initial Sync Date Tests")
struct MailIMAPInitialSyncServiceDateTests {
    @Test func fetchedMessageUsesInternalDateBeforeHeaderDateForListOrdering() {
        let headerDate = BlockingIMAPClient.parseDate("Mon, 06 Jul 2026 08:00:00 +0800")!
        let internalDate = BlockingIMAPClient.parseIMAPInternalDate(in: #"* 1 FETCH (UID 42 FLAGS () INTERNALDATE "06-Jul-2026 12:01:00 +0800" ENVELOPE NIL)"#)!
        let message = BlockingIMAPClient.FetchedMessage(
            uid: "42",
            flags: "",
            header: "Date: Mon, 06 Jul 2026 08:00:00 +0800\r\nSubject: 收件时间排序\r\nFrom: sender@example.com\r\nTo: shiwen@example.com",
            rawHeaderData: nil,
            snippet: "摘要",
            rawBodyData: nil,
            serverReceivedDate: internalDate,
            fallbackSequenceDate: headerDate
        )

        let detail = message.detail(
            accountID: MailAccountID(rawValue: "shiwen@example.com"),
            mailboxID: MailMailboxID(rawValue: "inbox"),
            fallbackRecipient: MailAddress(email: "shiwen@example.com")
        )

        #expect(detail.summary.date == internalDate)
        #expect(detail.summary.date > headerDate)
    }
}
