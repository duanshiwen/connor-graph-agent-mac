import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Native Mail Browser Presentation Tests")
struct NativeMailBrowserPresentationTests {
    @Test func messagesArePresentedNewestFirstRegardlessOfInputOrder() {
        let accountID = MailAccountID(rawValue: "account")
        let mailboxID = MailMailboxID(rawValue: "inbox")
        let account = MailAccount(
            id: accountID,
            provider: .genericIMAPSMTP,
            displayName: "Test Mail",
            identities: []
        )
        let mailbox = MailMailbox(id: mailboxID, accountID: accountID, name: "Inbox", path: "INBOX", role: .inbox)
        let old = Self.makeMessage(id: "old", accountID: accountID, mailboxID: mailboxID, date: Date(timeIntervalSince1970: 100), subject: "Project")
        let newest = Self.makeMessage(id: "newest", accountID: accountID, mailboxID: mailboxID, date: Date(timeIntervalSince1970: 300), subject: "Project")
        let middle = Self.makeMessage(id: "middle", accountID: accountID, mailboxID: mailboxID, date: Date(timeIntervalSince1970: 200), subject: "Project")

        let presentation = NativeMailBrowserPresentation(
            accounts: [account],
            mailboxes: [mailbox],
            messages: [old, newest, middle]
        )

        #expect(presentation.messages.map { $0.id.rawValue } == ["newest", "middle", "old"])
        #expect(presentation.messages(accountID: accountID, mailboxID: mailboxID, query: "project").map { $0.id.rawValue } == ["newest", "middle", "old"])
        #expect(presentation.defaultMessageID(accountID: accountID, mailboxID: mailboxID)?.rawValue == "newest")
    }

    @Test func messagesUseStableIDTieBreakWhenDatesMatch() {
        let accountID = MailAccountID(rawValue: "account")
        let mailboxID = MailMailboxID(rawValue: "inbox")
        let sameDate = Date(timeIntervalSince1970: 100)
        let z = Self.makeMessage(id: "z", accountID: accountID, mailboxID: mailboxID, date: sameDate, subject: "Tie")
        let a = Self.makeMessage(id: "a", accountID: accountID, mailboxID: mailboxID, date: sameDate, subject: "Tie")

        let presentation = NativeMailBrowserPresentation(accounts: [], mailboxes: [], messages: [z, a])

        #expect(presentation.messages.map { $0.id.rawValue } == ["a", "z"])
    }

    private static func makeMessage(id: String, accountID: MailAccountID, mailboxID: MailMailboxID, date: Date, subject: String) -> MailMessageSummary {
        MailMessageSummary(
            id: MailMessageID(rawValue: id),
            accountID: accountID,
            mailboxID: mailboxID,
            subject: subject,
            from: MailAddress(name: "Sender", email: "sender@example.com"),
            to: [MailAddress(email: "receiver@example.com")],
            date: date,
            snippet: "snippet"
        )
    }
}
