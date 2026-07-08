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

    @Test func messagesCanFilterReceivedAndSentDirections() {
        let accountID = MailAccountID(rawValue: "account")
        let inboxID = MailMailboxID(rawValue: "inbox")
        let sentID = MailMailboxID(rawValue: "sent")
        let account = MailAccount(id: accountID, provider: .genericIMAPSMTP, displayName: "Test Mail", identities: [])
        let inbox = MailMailbox(id: inboxID, accountID: accountID, name: "Inbox", path: "INBOX", role: .inbox)
        let sent = MailMailbox(id: sentID, accountID: accountID, name: "Sent", path: "Sent", role: .sent)
        let received = Self.makeMessage(id: "received", accountID: accountID, mailboxID: inboxID, date: Date(timeIntervalSince1970: 100), subject: "Received")
        let sentMessage = Self.makeMessage(id: "sent-message", accountID: accountID, mailboxID: sentID, date: Date(timeIntervalSince1970: 200), subject: "Sent")

        let presentation = NativeMailBrowserPresentation(
            accounts: [account],
            mailboxes: [inbox, sent],
            messages: [received, sentMessage]
        )

        #expect(presentation.messages(accountID: nil, mailboxID: nil, query: "", direction: .all).map { $0.id.rawValue } == ["sent-message", "received"])
        #expect(presentation.messages(accountID: nil, mailboxID: nil, query: "", direction: .received).map { $0.id.rawValue } == ["received"])
        #expect(presentation.messages(accountID: nil, mailboxID: nil, query: "", direction: .sent).map { $0.id.rawValue } == ["sent-message"])
    }

    @Test func unqueriedDirectionMessagesUseCachedNewestFirstLists() {
        let accountID = MailAccountID(rawValue: "account")
        let inboxID = MailMailboxID(rawValue: "inbox")
        let sentID = MailMailboxID(rawValue: "sent")
        let account = MailAccount(id: accountID, provider: .genericIMAPSMTP, displayName: "Test Mail", identities: [])
        let inbox = MailMailbox(id: inboxID, accountID: accountID, name: "Inbox", path: "INBOX", role: .inbox)
        let sent = MailMailbox(id: sentID, accountID: accountID, name: "Sent", path: "Sent", role: .sent)
        let olderReceived = Self.makeMessage(id: "received-older", accountID: accountID, mailboxID: inboxID, date: Date(timeIntervalSince1970: 100), subject: "Received")
        let newerReceived = Self.makeMessage(id: "received-newer", accountID: accountID, mailboxID: inboxID, date: Date(timeIntervalSince1970: 300), subject: "Received")
        let sentMessage = Self.makeMessage(id: "sent-message", accountID: accountID, mailboxID: sentID, date: Date(timeIntervalSince1970: 200), subject: "Sent")

        let presentation = NativeMailBrowserPresentation(
            accounts: [account],
            mailboxes: [inbox, sent],
            messages: [olderReceived, sentMessage, newerReceived]
        )

        #expect(presentation.unqueriedMessages(direction: .all).map { $0.id.rawValue } == ["received-newer", "sent-message", "received-older"])
        #expect(presentation.unqueriedMessages(direction: .received).map { $0.id.rawValue } == ["received-newer", "received-older"])
        #expect(presentation.unqueriedMessages(direction: .sent).map { $0.id.rawValue } == ["sent-message"])
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
