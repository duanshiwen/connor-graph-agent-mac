import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAgent
import ConnorGraphStore
import ConnorGraphAppSupport

@Suite("Mail Memory OS End-to-End Tests")
struct MailMemoryOSEndToEndTests {
    @Test func mailGetMessagePersistsDetailReadIntoMemoryOSL0L1WithNativeReferenceMetadata() async throws {
        let store = try SQLiteMemoryOSStore(path: temporaryMailMemoryOSDatabaseURL().path)
        try store.migrate()
        let recorder = AppMemoryOSNativeSourceReferenceRecorder(facade: AppMemoryOSFacade(store: store))
        let summary = Self.mailSummary(id: "message-1", subject: "Memory OS Evidence Review")
        let runtime = MailRuntimeFixture(messages: [summary], details: [
            "message-1": MailMessageDetail(
                summary: summary,
                body: MailMessageBody(
                    plainText: MailBodyPart(mimeType: "text/plain", text: "The Memory OS evidence bridge should persist this mail body.", byteCount: 61),
                    htmlText: MailBodyPart(mimeType: "text/html", text: "<p>The Memory OS evidence bridge should persist this mail body.</p>", byteCount: 68),
                    redactedPreview: "The Memory OS evidence bridge should persist this mail body.",
                    bodyHash: "body-hash-1"
                )
            )
        ])
        let tool = MailGetMessageTool(runtime: runtime, recorder: recorder)

        let result = try await tool.execute(
            arguments: try AgentToolArguments(json: "{\"messageID\":\"message-1\",\"includeBody\":true}"),
            context: Self.context(toolCallID: "call-mail-get")
        )

        #expect(result.contentText.contains("Read message body"))
        #expect(result.contentJSON?.contains("The Memory OS evidence bridge") == true)
        #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l0_provenance_objects;").first?.first == "1")
        #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l1_capture_events;").first?.first == "1")

        let l0 = try #require(try store.query(sql: "SELECT source_id, title, content, metadata_json FROM memory_l0_provenance_objects LIMIT 1;").first)
        #expect(l0[0].contains("native-ref:mail:message-1:detail_read"))
        #expect(l0[1] == "Memory OS Evidence Review")
        #expect(l0[2].contains("Subject: Memory OS Evidence Review"))
        #expect(l0[2].contains("From: Alice <alice@example.com>"))
        #expect(l0[2].contains("Body:"))
        #expect(l0[2].contains("The Memory OS evidence bridge should persist this mail body."))
        #expect(l0[3].contains("\"native_source_kind\":\"mail\""))
        #expect(l0[3].contains("\"reference_strength\":\"detail_read\""))
        #expect(l0[3].contains("\"tool_name\":\"mail_get_message\""))
        #expect(l0[3].contains("\"tool_call_id\":\"call-mail-get\""))
        #expect(l0[3].contains("\"include_body\":\"true\""))
        #expect(l0[3].contains("\"body_hash\":\"body-hash-1\""))
    }

    @Test func mailSearchMessagesDoesNotPersistCandidateSummariesIntoMemoryOS() async throws {
        let store = try SQLiteMemoryOSStore(path: temporaryMailMemoryOSDatabaseURL().path)
        try store.migrate()
        let recorder = AppMemoryOSNativeSourceReferenceRecorder(facade: AppMemoryOSFacade(store: store))
        let runtime = MailRuntimeFixture(messages: [Self.mailSummary(id: "message-1", subject: "Candidate Only")], details: [:])
        let tool = MailSearchMessagesTool(runtime: runtime, recorder: recorder)

        let result = try await tool.execute(
            arguments: try AgentToolArguments(json: "{\"query\":\"Candidate\",\"limit\":5}"),
            context: Self.context(toolCallID: "call-mail-search")
        )

        #expect(result.contentText.contains("Found 1 mail message summaries"))
        #expect(result.contentJSON?.contains("Candidate Only") == true)
        #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l0_provenance_objects;").first?.first == "0")
        #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l1_capture_events;").first?.first == "0")
    }

    @Test func mailGetMessagePersistsHTMLOnlyBodyAsSafeEvidenceWithoutCredentialMetadata() async throws {
        let store = try SQLiteMemoryOSStore(path: temporaryMailMemoryOSDatabaseURL().path)
        try store.migrate()
        let recorder = AppMemoryOSNativeSourceReferenceRecorder(facade: AppMemoryOSFacade(store: store))
        let summary = Self.mailSummary(id: "message-html", subject: "HTML Evidence")
        let runtime = MailRuntimeFixture(messages: [summary], details: [
            "message-html": MailMessageDetail(
                summary: summary,
                body: MailMessageBody(
                    htmlText: MailBodyPart(mimeType: "text/html", text: "<article><h1>HTML Evidence</h1><script>steal()</script><p>Safe text retained.</p></article>", byteCount: 89),
                    redactedPreview: "HTML Evidence Safe text retained.",
                    bodyHash: "html-body-hash"
                )
            )
        ])
        let tool = MailGetMessageTool(runtime: runtime, recorder: recorder)

        _ = try await tool.execute(
            arguments: try AgentToolArguments(json: "{\"messageID\":\"message-html\",\"includeBody\":true}"),
            context: Self.context(toolCallID: "call-mail-html")
        )

        let l0 = try #require(try store.query(sql: "SELECT content, metadata_json FROM memory_l0_provenance_objects LIMIT 1;").first)
        #expect(l0[0].contains("HTML Evidence"))
        #expect(l0[0].contains("Safe text retained."))
        #expect(!l0[0].localizedCaseInsensitiveContains("password"))
        #expect(!l0[0].localizedCaseInsensitiveContains("access_token"))
        #expect(!l0[0].localizedCaseInsensitiveContains("refresh_token"))
        #expect(!l0[0].localizedCaseInsensitiveContains("secret"))
        #expect(!l0[1].localizedCaseInsensitiveContains("password"))
        #expect(!l0[1].localizedCaseInsensitiveContains("access_token"))
        #expect(!l0[1].localizedCaseInsensitiveContains("refresh_token"))
        #expect(!l0[1].localizedCaseInsensitiveContains("secret"))
    }

    private static func context(toolCallID: String) -> AgentToolExecutionContext {
        AgentToolExecutionContext(
            runID: "run-mail-memory-os",
            sessionID: "session-mail-memory-os",
            groupID: "group-mail-memory-os",
            userPrompt: "test",
            toolCallID: toolCallID,
            policyEngine: AgentPolicyEngine(permissionMode: .allowAll)
        )
    }

    private static func mailSummary(id: String, subject: String) -> MailMessageSummary {
        MailMessageSummary(
            id: MailMessageID(rawValue: id),
            accountID: MailAccountID(rawValue: "account-1"),
            mailboxID: MailMailboxID(rawValue: "inbox"),
            subject: subject,
            from: MailAddress(name: "Alice", email: "alice@example.com"),
            to: [MailAddress(name: "诗闻", email: "shiwen@example.com")],
            date: Date(timeIntervalSince1970: 1_000),
            snippet: "Snippet for \(id)"
        )
    }
}

private struct MailRuntimeFixture: AgentMailRuntime {
    var messages: [MailMessageSummary]
    var details: [String: MailMessageDetail]

    func listAccounts(runID: String?, sessionID: String?) async throws -> [MailAccount] { [] }
    func searchMessages(_ request: MailRuntimeSearchRequestBridge, runID: String?, sessionID: String?) async throws -> [MailMessageSummary] { Array(messages.prefix(request.limit)) }
    func getMessage(id: MailMessageID, includeBody: Bool, runID: String?, sessionID: String?) async throws -> MailMessageDetail {
        guard var detail = details[id.rawValue] else { throw AgentToolError.invalidArguments("missing message") }
        if !includeBody { detail.body = nil }
        return detail
    }
    func setReadState(messageIDs: [MailMessageID], isRead: Bool, runID: String?, sessionID: String?) async throws {}
    func createDraft(accountID: MailAccountID, identityID: MailIdentityID, to: [MailAddress], cc: [MailAddress], bcc: [MailAddress], replyTo: [MailAddress], subject: String, body: String, htmlBody: String?, inReplyToMessageID: MailMessageID?, attachmentIDs: [MailAttachmentID], intentSummary: String?, runID: String?, sessionID: String?) async throws -> MailDraft {
        MailDraft(id: MailDraftID(rawValue: "draft"), accountID: accountID, identityID: identityID, to: to, cc: cc, bcc: bcc, subject: subject, body: body, htmlBody: htmlBody, replyTo: replyTo, attachmentIDs: attachmentIDs, inReplyToMessageID: inReplyToMessageID, intentSummary: intentSummary)
    }
    func sendDraft(draftID: MailDraftID, approved: Bool, runID: String?, sessionID: String?) async throws -> MailSendReceipt {
        MailSendReceipt(draftID: draftID, providerMessageID: "sent", sentAt: Date(), envelopeHash: "hash")
    }
}

private func temporaryMailMemoryOSDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("mail-memory-os-e2e-\(UUID().uuidString).sqlite")
}
