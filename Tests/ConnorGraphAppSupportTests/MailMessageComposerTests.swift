import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Mail Message Composer Tests")
struct MailMessageComposerTests {
    @Test func composerBuildsRFC5322MessageWithoutBccHeader() throws {
        let draft = MailDraft(
            id: MailDraftID(rawValue: "draft-1"),
            accountID: MailAccountID(rawValue: "account-1"),
            identityID: MailIdentityID(rawValue: "identity-1"),
            to: [MailAddress(name: "Alice", email: "alice@example.com")],
            cc: [MailAddress(email: "carol@example.com")],
            bcc: [MailAddress(email: "secret@example.com")],
            subject: "你好 Connor",
            body: "Hello\n.World",
            htmlBody: "<p>Hello</p>",
            replyTo: [MailAddress(email: "reply@example.com")],
            messageIDHeader: "<draft-1@connor.local>",
            inReplyToHeader: "<previous@example.com>",
            referencesHeaders: ["<root@example.com>", "<previous@example.com>"]
        )
        let from = MailAddress(name: "Connor", email: "connor@example.com")

        let message = try MailMessageComposer().compose(draft: draft, from: from, date: Date(timeIntervalSince1970: 1_782_306_000))

        #expect(message.rawMessage.contains("From: Connor <connor@example.com>"))
        #expect(message.rawMessage.contains("To: Alice <alice@example.com>"))
        #expect(message.rawMessage.contains("Cc: carol@example.com"))
        #expect(!message.rawMessage.contains("Bcc:"))
        #expect(message.rawMessage.contains("Subject: =?UTF-8?B?"))
        #expect(message.rawMessage.contains("Reply-To: reply@example.com"))
        #expect(message.rawMessage.contains("In-Reply-To: <previous@example.com>"))
        #expect(message.envelopeRecipients.map { $0.email }.contains("secret@example.com"))
    }

    @Test func composerRejectsHeaderInjection() {
        let draft = MailDraft(
            id: MailDraftID(rawValue: "draft-1"),
            accountID: MailAccountID(rawValue: "account-1"),
            identityID: MailIdentityID(rawValue: "identity-1"),
            to: [MailAddress(email: "alice@example.com")],
            subject: "Hello\r\nBcc: attacker@example.com",
            body: "Body"
        )
        let from = MailAddress(email: "connor@example.com")

        #expect(throws: MailMessageComposerError.self) {
            _ = try MailMessageComposer().compose(draft: draft, from: from)
        }
    }

    @Test func dotStuffingEscapesLinesStartingWithDot() {
        let input = "Hello\r\n.World\r\n..Already\r\nBye"
        #expect(MailMessageComposer.dotStuff(input) == "Hello\r\n..World\r\n...Already\r\nBye")
    }
}
