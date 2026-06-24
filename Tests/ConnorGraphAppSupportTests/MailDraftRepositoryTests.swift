import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Mail Draft Repository Tests")
struct MailDraftRepositoryTests {
    @Test func draftEnvelopeHashChangesWhenRecipientsSubjectBodyOrReplyHeadersChange() {
        let base = MailDraft(
            id: MailDraftID(rawValue: "draft-1"),
            accountID: MailAccountID(rawValue: "account-1"),
            identityID: MailIdentityID(rawValue: "identity-1"),
            to: [MailAddress(email: "alice@example.com")],
            subject: "Hello",
            body: "Body"
        )

        var changedRecipient = base
        changedRecipient.to = [MailAddress(email: "bob@example.com")]

        var changedSubject = base
        changedSubject.subject = "Different"

        var changedBody = base
        changedBody.body = "Different body"

        var changedReply = base
        changedReply.inReplyToHeader = "<previous@example.com>"

        #expect(base.envelopeHash() != changedRecipient.envelopeHash())
        #expect(base.envelopeHash() != changedSubject.envelopeHash())
        #expect(base.envelopeHash() != changedBody.envelopeHash())
        #expect(base.envelopeHash() != changedReply.envelopeHash())
        #expect(base.envelopeHash() == base.envelopeHash())
    }

    @Test func fileBackedDraftRepositoryPersistsDraftsAcrossInstances() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mail-drafts-\(UUID().uuidString)", isDirectory: true)
        let storeURL = directory.appendingPathComponent("mail-drafts.json")
        let fixedDate = Date(timeIntervalSince1970: 1_782_306_000)
        let draft = MailDraft(
            id: MailDraftID(rawValue: "draft-persisted"),
            accountID: MailAccountID(rawValue: "account-1"),
            identityID: MailIdentityID(rawValue: "identity-1"),
            to: [MailAddress(email: "alice@example.com")],
            subject: "Persistent",
            body: "This draft should survive repository recreation.",
            htmlBody: "<p>This draft should survive repository recreation.</p>",
            intentSummary: "Send a persistence test email.",
            createdAt: fixedDate,
            updatedAt: fixedDate
        )

        let writer = FileBackedMailDraftRepository(storeURL: storeURL)
        try await writer.save(draft)

        let reader = FileBackedMailDraftRepository(storeURL: storeURL)
        let reloaded = try #require(try await reader.draft(id: draft.id))
        #expect(reloaded.id == draft.id)
        #expect(reloaded.subject == draft.subject)
        #expect(reloaded.htmlBody == draft.htmlBody)
        #expect(reloaded.intentSummary == draft.intentSummary)
        #expect(reloaded.envelopeHash() == draft.envelopeHash())
        #expect(try await reader.listDrafts(accountID: draft.accountID, status: .draft).map(\.id) == [draft.id])
    }

    @Test func draftRepositoryRecordsStatusAndSendAttempts() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mail-draft-attempts-\(UUID().uuidString)", isDirectory: true)
        let storeURL = directory.appendingPathComponent("mail-drafts.json")
        let repository = FileBackedMailDraftRepository(storeURL: storeURL)
        let draft = MailDraft(
            id: MailDraftID(rawValue: "draft-attempt"),
            accountID: MailAccountID(rawValue: "account-1"),
            identityID: MailIdentityID(rawValue: "identity-1"),
            to: [MailAddress(email: "alice@example.com")],
            subject: "Attempt",
            body: "Body"
        )
        try await repository.save(draft)
        let attempt = MailSendAttempt(
            id: "attempt-1",
            draftID: draft.id,
            status: .failed,
            providerMessageID: nil,
            envelopeHash: draft.envelopeHash(),
            errorSummary: "SMTP unavailable"
        )

        try await repository.recordSendAttempt(attempt)
        let failed = try await repository.updateStatus(id: draft.id, status: .failed, lastSendError: "SMTP unavailable")

        #expect(failed.status == .failed)
        #expect(failed.lastSendError == "SMTP unavailable")
        #expect(try await repository.sendAttempts(draftID: draft.id).map(\.id) == ["attempt-1"])
    }
}
