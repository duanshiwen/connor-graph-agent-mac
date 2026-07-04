import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAgent

@Suite("Mail Agent Tools Tests")
struct MailAgentToolsTests {
    @Test func registryRegistersSearchAndSendTools() {
        var registry = AgentToolRegistry()
        registry.registerNativeMailTools(runtime: RecordingMailRuntime())
        let names = registry.definitions.map(\.name)
        #expect(names.contains("mail_search_messages"))
        #expect(names.contains("mail_create_draft"))
        #expect(names.contains("mail_send_draft"))
    }

    @Test func createDraftToolPassesCommercialFields() async throws {
        let runtime = RecordingMailRuntime()
        let tool = MailCreateDraftTool(runtime: runtime)
        let context = AgentToolExecutionContext(runID: "run", sessionID: "session", groupID: "group", userPrompt: "draft", toolCallID: "call", policyEngine: AgentPolicyEngine(permissionMode: .allowAll), approvedCapabilities: [.createMailDraft])
        let arguments = try AgentToolArguments(json: """
        {
          "accountID": "account-1",
          "identityID": "identity-1",
          "to": ["alice@example.com"],
          "cc": ["carol@example.com"],
          "bcc": ["hidden@example.com"],
          "replyTo": ["reply@example.com"],
          "subject": "Hello",
          "body": "Plain",
          "htmlBody": "<p>Plain</p>",
          "inReplyToMessageID": "message-1",
          "attachmentIDs": ["attachment-1"],
          "intentSummary": "Follow up"
        }
        """)

        _ = try await tool.execute(arguments: arguments, context: context)
        let request = try #require(await runtime.lastCreateDraft)
        #expect(request.cc.map(\.email) == ["carol@example.com"])
        #expect(request.bcc.map(\.email) == ["hidden@example.com"])
        #expect(request.replyTo.map(\.email) == ["reply@example.com"])
        #expect(request.htmlBody == "<p>Plain</p>")
        #expect(request.inReplyToMessageID == MailMessageID(rawValue: "message-1"))
        #expect(request.attachmentIDs == [MailAttachmentID(rawValue: "attachment-1")])
        #expect(request.intentSummary == "Follow up")
    }

    @Test func getMessageRejectsNumericResultIndexWithActionableGuidance() async throws {
        let runtime = RecordingMailRuntime()
        let tool = MailGetMessageTool(runtime: runtime)
        let context = AgentToolExecutionContext(runID: "run", sessionID: "session", groupID: "group", userPrompt: "read mail", toolCallID: "call", policyEngine: AgentPolicyEngine(permissionMode: .allowAll), approvedCapabilities: [.readMailBody])
        let arguments = try AgentToolArguments(json: "{\"messageID\":\"1\",\"includeBody\":true}")

        do {
            _ = try await tool.execute(arguments: arguments, context: context)
            Issue.record("Expected numeric messageID to be rejected with actionable guidance")
        } catch AgentToolError.invalidArguments(let message) {
            #expect(message.contains("exact messageID"))
            #expect(message.contains("mail_search_messages"))
            #expect(message.contains("result index"))
            #expect(message.contains("1"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func sendDraftApprovalPayloadIncludesMailSummary() async throws {
        let runtime = RecordingMailRuntime()
        let tool = MailSendDraftTool(runtime: runtime)
        let context = AgentToolExecutionContext(runID: "run", sessionID: "session", groupID: "group", userPrompt: "send", toolCallID: "call", policyEngine: AgentPolicyEngine(permissionMode: .allowAll), approvedCapabilities: [])
        let call = AgentToolCall(id: "call", runID: "run", sessionID: "session", name: "mail_send_draft", argumentsJSON: "{\"draftID\":\"draft-1\"}")

        let payload = await tool.approvalPayloadJSON(for: call, context: context)

        #expect(payload.contains("alice@example.com"))
        #expect(payload.contains("envelope-1"))
        #expect(payload.contains("Quarterly update"))
    }

    @Test func sendDraftToolBuildsApprovalPayloadFromRuntimeDraft() async throws {
        let runtime = RecordingMailRuntime()
        await runtime.setApprovalPayload(MailSendApprovalBridge(
            draftID: MailDraftID(rawValue: "draft-1"),
            title: "Send email approval",
            from: "connor@example.com",
            to: ["alice@example.com"],
            subject: "Runtime subject",
            bodyPreview: "Runtime body",
            riskSummary: "approval gated",
            envelopeHash: "runtime-hash"
        ))
        let tool = MailSendDraftTool(runtime: runtime)
        let context = AgentToolExecutionContext(runID: "run", sessionID: "session", groupID: "group", userPrompt: "send", toolCallID: "call", policyEngine: AgentPolicyEngine(permissionMode: .allowAll), approvedCapabilities: [])
        let payload = await tool.approvalPayloadJSON(for: AgentToolCall(name: "mail_send_draft", argumentsJSON: "{\"draftID\":\"draft-1\",\"subject\":\"model supplied\"}"), context: context)

        #expect(payload.contains("Runtime subject"))
        #expect(payload.contains("runtime-hash"))
        #expect(!payload.contains("model supplied"))
    }

    @Test func sendDraftIgnoresModelApprovedFlagAndUsesApprovalContext() async throws {
        let runtime = RecordingMailRuntime()
        let tool = MailSendDraftTool(runtime: runtime)
        let arguments = try AgentToolArguments(json: "{\"draftID\":\"draft-1\",\"approved\":true}")
        let unapproved = AgentToolExecutionContext(runID: "run", sessionID: "session", groupID: "group", userPrompt: "send", toolCallID: "call", policyEngine: AgentPolicyEngine(permissionMode: .allowAll), approvedCapabilities: [])
        let approved = unapproved.approving(.sendMail)

        await #expect(throws: AgentToolError.self) {
            _ = try await tool.execute(arguments: arguments, context: unapproved)
        }
        #expect(await runtime.lastSendApproved == false)

        _ = try await tool.execute(arguments: arguments, context: approved)
        #expect(await runtime.lastSendApproved == true)
    }
}

private actor RecordingMailRuntime: AgentMailRuntime {
    struct CreateDraftRequest: Sendable, Equatable {
        var accountID: MailAccountID
        var identityID: MailIdentityID
        var to: [MailAddress]
        var cc: [MailAddress]
        var bcc: [MailAddress]
        var replyTo: [MailAddress]
        var subject: String
        var body: String
        var htmlBody: String?
        var inReplyToMessageID: MailMessageID?
        var attachmentIDs: [MailAttachmentID]
        var intentSummary: String?
    }

    var lastCreateDraft: CreateDraftRequest?
    var lastSendApproved: Bool?
    var approvalPayload: MailSendApprovalBridge?

    func setApprovalPayload(_ payload: MailSendApprovalBridge) {
        self.approvalPayload = payload
    }

    func listAccounts(runID: String?, sessionID: String?) async throws -> [MailAccount] { [] }
    func searchMessages(_ request: MailRuntimeSearchRequestBridge, runID: String?, sessionID: String?) async throws -> [MailMessageSummary] { [] }
    func getMessage(id: MailMessageID, includeBody: Bool, runID: String?, sessionID: String?) async throws -> MailMessageDetail { throw AgentToolError.invalidArguments("message not found") }
    func setReadState(messageIDs: [MailMessageID], isRead: Bool, runID: String?, sessionID: String?) async throws {}

    func createDraft(accountID: MailAccountID, identityID: MailIdentityID, to: [MailAddress], cc: [MailAddress], bcc: [MailAddress], replyTo: [MailAddress], subject: String, body: String, htmlBody: String?, inReplyToMessageID: MailMessageID?, attachmentIDs: [MailAttachmentID], intentSummary: String?, runID: String?, sessionID: String?) async throws -> MailDraft {
        lastCreateDraft = CreateDraftRequest(accountID: accountID, identityID: identityID, to: to, cc: cc, bcc: bcc, replyTo: replyTo, subject: subject, body: body, htmlBody: htmlBody, inReplyToMessageID: inReplyToMessageID, attachmentIDs: attachmentIDs, intentSummary: intentSummary)
        return MailDraft(id: MailDraftID(rawValue: "draft-1"), accountID: accountID, identityID: identityID, to: to, cc: cc, bcc: bcc, subject: subject, body: body, htmlBody: htmlBody, replyTo: replyTo, attachmentIDs: attachmentIDs, inReplyToMessageID: inReplyToMessageID, intentSummary: intentSummary)
    }

    func sendApprovalBridgePayload(draftID: MailDraftID) async throws -> MailSendApprovalBridge {
        approvalPayload ?? MailSendApprovalBridge(draftID: draftID, title: "Send email approval", from: "connor@example.com", to: ["alice@example.com"], cc: [], bcc: [], subject: "Quarterly update", bodyPreview: "Preview", attachmentCount: 0, riskSummary: "approval required", envelopeHash: "envelope-1")
    }

    func sendDraft(draftID: MailDraftID, approved: Bool, runID: String?, sessionID: String?) async throws -> MailSendReceipt {
        lastSendApproved = approved
        guard approved else { throw AgentToolError.permissionDenied("Mail send approval required") }
        return MailSendReceipt(draftID: draftID, providerMessageID: "sent", envelopeHash: "hash")
    }
}


private enum RecordingMailRuntimeError: Error {
    case approvalRequired
    case messageNotFound
}
