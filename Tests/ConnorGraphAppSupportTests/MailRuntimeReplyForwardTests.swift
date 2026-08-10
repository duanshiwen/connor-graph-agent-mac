import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Mail Runtime Reply/Forward Drafts")
struct MailRuntimeReplyForwardTests {
    private func makeRuntime(original: MailMessageDetail) -> MailRuntime {
        let accountID = original.summary.accountID
        let identityID = MailIdentityID(rawValue: "identity-1")
        let identity = MailIdentity(id: identityID, displayName: "Connor", address: MailAddress(name: "Connor", email: "connor@example.com"))
        let account = MailAccount(
            id: accountID,
            provider: .genericIMAPSMTP,
            displayName: "Connor Mail",
            identities: [identity],
            outgoing: MailServerEndpoint(host: "smtp.example.com", port: 587, security: .startTLS, protocolKind: .smtp),
            health: MailAccountHealth(status: .ready, summary: "ready")
        )
        let inbox = MailMailbox(id: MailMailboxID(rawValue: "inbox"), accountID: accountID, name: "Inbox", path: "INBOX", role: .inbox)
        return MailRuntime(
            repository: InMemoryMailSourceRepository(accounts: [account]),
            cache: InMemoryMailSourceCache(mailboxes: [inbox], messages: [original]),
            credentialStore: AppMailCredentialStore()
        )
    }

    private func originalMessage(
        id: String = "original-1",
        from: MailAddress,
        to: [MailAddress] = [MailAddress(email: "connor@example.com")],
        subject: String = "Hello",
        body: String = "Original body line",
        messageIDHeader: String? = "<orig@example.com>",
        references: [String] = ["<ref1@example.com>"]
    ) -> MailMessageDetail {
        let summary = MailMessageSummary(
            id: MailMessageID(rawValue: id),
            accountID: MailAccountID(rawValue: "account-1"),
            mailboxID: MailMailboxID(rawValue: "inbox"),
            threadID: MailThreadID(rawValue: "thread-1"),
            subject: subject,
            from: from,
            to: to,
            date: Date(timeIntervalSince1970: 1_752_000_000),
            snippet: "Original body line"
        )
        let headers = MailMessageHeaders(messageIDHeader: messageIDHeader, references: references)
        let body = MailMessageBody(
            plainText: MailBodyPart(mimeType: "text/plain", text: body, byteCount: body.utf8.count),
            redactedPreview: String(body.prefix(100))
        )
        return MailMessageDetail(summary: summary, headers: headers, body: body)
    }

    @Test func replyDraftPrefillsRecipientSubjectAndQuotesOriginal() async throws {
        let original = originalMessage(from: MailAddress(name: "Alice", email: "alice@example.com"))
        let runtime = makeRuntime(original: original)

        let draft = try await runtime.createReplyDraft(
            accountID: original.summary.accountID,
            identityID: MailIdentityID(rawValue: "identity-1"),
            messageID: original.id,
            body: "My reply",
            includeOriginal: true
        )

        #expect(draft.to.map(\.email) == ["alice@example.com"])
        #expect(draft.subject == "Re: Hello")
        #expect(draft.body.contains("My reply"))
        #expect(draft.body.contains("On "))
        #expect(draft.body.contains("> Original body line"))
        #expect(draft.inReplyToMessageID == original.id)
        #expect(draft.inReplyToHeader == "<orig@example.com>")
        #expect(draft.referencesHeaders.contains("<orig@example.com>"))
        #expect(draft.referencesHeaders.contains("<ref1@example.com>"))
    }

    @Test func replyDraftDoesNotDuplicateRePrefix() async throws {
        let original = originalMessage(from: MailAddress(email: "alice@example.com"), subject: "Re: Hello")
        let runtime = makeRuntime(original: original)

        let draft = try await runtime.createReplyDraft(
            accountID: original.summary.accountID,
            identityID: MailIdentityID(rawValue: "identity-1"),
            messageID: original.id,
            body: "Again",
            includeOriginal: false
        )

        #expect(draft.subject == "Re: Hello")
        #expect(!draft.body.contains("> Original body line"))
    }

    @Test func replyToOwnSentMessageFallsBackToOriginalRecipients() async throws {
        let original = originalMessage(
            from: MailAddress(name: "Connor", email: "connor@example.com"),
            to: [MailAddress(email: "alice@example.com"), MailAddress(email: "bob@example.com")]
        )
        let runtime = makeRuntime(original: original)

        let draft = try await runtime.createReplyDraft(
            accountID: original.summary.accountID,
            identityID: MailIdentityID(rawValue: "identity-1"),
            messageID: original.id,
            body: "Reply",
            includeOriginal: false
        )

        #expect(draft.to.map(\.email) == ["alice@example.com", "bob@example.com"])
    }

    @Test func forwardDraftPrefixesFwdAndIncludesOriginal() async throws {
        let original = originalMessage(
            from: MailAddress(name: "Alice", email: "alice@example.com"),
            to: [MailAddress(email: "connor@example.com")]
        )
        let runtime = makeRuntime(original: original)

        let draft = try await runtime.createForwardDraft(
            accountID: original.summary.accountID,
            identityID: MailIdentityID(rawValue: "identity-1"),
            messageID: original.id,
            to: [MailAddress(email: "bob@example.com")],
            body: "See below",
            includeOriginal: true
        )

        #expect(draft.to.map(\.email) == ["bob@example.com"])
        #expect(draft.subject == "Fwd: Hello")
        #expect(draft.inReplyToMessageID == nil)
        #expect(draft.body.contains("See below"))
        #expect(draft.body.contains("-------- Forwarded Message --------"))
        #expect(draft.body.contains("From: Alice <alice@example.com>"))
        #expect(draft.body.contains("Subject: Hello"))
        #expect(draft.body.contains("Original body line"))
    }
}
