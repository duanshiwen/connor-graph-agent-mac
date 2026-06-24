import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Mail SMTP and Composer Tests")
struct MailSMTPAndComposerTests {
    @Test func messageComposerExcludesBccAndNormalizesCRLF() throws {
        let draft = MailDraft(
            id: MailDraftID(rawValue: "draft-compose"),
            accountID: MailAccountID(rawValue: "account-1"),
            identityID: MailIdentityID(rawValue: "identity-1"),
            to: [MailAddress(name: "Alice", email: "alice@example.com")],
            cc: [MailAddress(email: "carol@example.com")],
            bcc: [MailAddress(email: "hidden@example.com")],
            subject: "Hello",
            body: "Line 1\nLine 2"
        )
        let message = try MailMessageComposer().compose(draft: draft, from: MailAddress(name: "Connor", email: "connor@example.com"), date: Date(timeIntervalSince1970: 0), messageID: "<draft-compose@connor.local>")

        #expect(message.rawMessage.contains("From: Connor <connor@example.com>\r\n"))
        #expect(message.rawMessage.contains("To: Alice <alice@example.com>\r\n"))
        #expect(message.rawMessage.contains("Cc: carol@example.com\r\n"))
        #expect(!message.rawMessage.localizedCaseInsensitiveContains("Bcc:"))
        #expect(!message.rawMessage.contains("hidden@example.com"))
        #expect(message.rawMessage.contains("Line 1\r\nLine 2"))
        #expect(message.envelopeRecipients.map(\.email) == ["alice@example.com", "carol@example.com", "hidden@example.com"])
    }

    @Test func messageComposerRejectsHeaderInjection() throws {
        let draft = MailDraft(
            id: MailDraftID(rawValue: "draft-injection"),
            accountID: MailAccountID(rawValue: "account-1"),
            identityID: MailIdentityID(rawValue: "identity-1"),
            to: [MailAddress(email: "alice@example.com")],
            subject: "Hello\r\nBcc: attacker@example.com",
            body: "Body"
        )

        #expect(throws: MailMessageComposerError.self) {
            _ = try MailMessageComposer().compose(draft: draft, from: MailAddress(email: "connor@example.com"))
        }
    }

    @Test func messageComposerBuildsMultipartAlternativeForHTML() throws {
        let draft = MailDraft(
            id: MailDraftID(rawValue: "draft-html"),
            accountID: MailAccountID(rawValue: "account-1"),
            identityID: MailIdentityID(rawValue: "identity-1"),
            to: [MailAddress(email: "alice@example.com")],
            subject: "HTML",
            body: "Plain",
            htmlBody: "<p>Plain</p>"
        )
        let message = try MailMessageComposer().compose(draft: draft, from: MailAddress(email: "connor@example.com"))
        #expect(message.rawMessage.contains("Content-Type: multipart/alternative;"))
        #expect(message.rawMessage.contains("Content-Type: text/plain; charset=utf-8"))
        #expect(message.rawMessage.contains("Content-Type: text/html; charset=utf-8"))
    }

    @Test func fakeSMTPClientCapturesRequestAndReturnsProviderMessageID() async throws {
        let request = MailSMTPSendRequest(
            endpoint: MailServerEndpoint(host: "smtp.example.com", port: 587, security: .startTLS, protocolKind: .smtp),
            username: "connor@example.com",
            password: "secret",
            from: MailAddress(email: "connor@example.com"),
            recipients: [MailAddress(email: "alice@example.com")],
            rawMessage: "From: connor@example.com\r\n\r\nHello",
            envelopeHash: "hash"
        )
        let client = FakeMailSMTPClient(response: MailSMTPSendResponse(providerMessageID: "server-id-1"))
        let response = try await client.send(request)
        #expect(response.providerMessageID == "server-id-1")
        #expect(await client.requests.count == 1)
        #expect(await client.requests.first?.username == "connor@example.com")
    }
}
