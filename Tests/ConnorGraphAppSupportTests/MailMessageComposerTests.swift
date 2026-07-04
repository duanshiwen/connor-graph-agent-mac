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

    @Test func composerBuildsMultipartMixedWithAttachments() throws {
        let draft = MailDraft(
            id: MailDraftID(rawValue: "draft-attachment"),
            accountID: MailAccountID(rawValue: "account-1"),
            identityID: MailIdentityID(rawValue: "identity-1"),
            to: [MailAddress(email: "alice@example.com")],
            subject: "Attachment",
            body: "Plain body",
            htmlBody: "<p>Plain body</p>",
            attachmentIDs: [MailAttachmentID(rawValue: "attachment-1")]
        )
        let attachment = OutboundMailAttachment(
            id: MailAttachmentID(rawValue: "attachment-1"),
            filename: "brief.txt",
            mimeType: "text/plain",
            data: Data("hello attachment".utf8),
            contentHash: "attachment-hash"
        )

        let message = try MailMessageComposer().compose(draft: draft, from: MailAddress(email: "connor@example.com"), attachments: [attachment])

        #expect(message.rawMessage.contains("Content-Type: multipart/mixed"))
        #expect(message.rawMessage.contains("Content-Type: multipart/alternative"))
        #expect(message.rawMessage.contains("Content-Disposition: attachment; filename=\"brief.txt\""))
        #expect(message.rawMessage.contains("Content-Transfer-Encoding: base64"))
        #expect(message.rawMessage.contains(Data("hello attachment".utf8).base64EncodedString()))
    }

    @Test func composerRejectsAttachmentFilenameHeaderInjection() {
        let draft = MailDraft(
            id: MailDraftID(rawValue: "draft-attachment"),
            accountID: MailAccountID(rawValue: "account-1"),
            identityID: MailIdentityID(rawValue: "identity-1"),
            to: [MailAddress(email: "alice@example.com")],
            subject: "Attachment",
            body: "Plain body",
            attachmentIDs: [MailAttachmentID(rawValue: "attachment-1")]
        )
        let attachment = OutboundMailAttachment(
            id: MailAttachmentID(rawValue: "attachment-1"),
            filename: "brief.txt\r\nBcc: attacker@example.com",
            mimeType: "text/plain",
            data: Data("hello".utf8)
        )

        #expect(throws: MailMessageComposerError.self) {
            _ = try MailMessageComposer().compose(draft: draft, from: MailAddress(email: "connor@example.com"), attachments: [attachment])
        }
    }

    @Test func dotStuffingEscapesLinesStartingWithDot() {
        let input = "Hello\r\n.World\r\n..Already\r\nBye"
        #expect(MailMessageComposer.dotStuff(input) == "Hello\r\n..World\r\n...Already\r\nBye")
    }
}
