import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphStore

// Regression coverage for the mail-send approval flow at the live session-manager level.
// Sending mail follows the session permission policy: in ask mode `mail_send_draft`
// surfaces a .permissionRequested pending approval (capability .sendMail) and only sends
// after the user approves; in execute mode it is auto-approved and sends immediately.
@Suite("Mail Send Approval Flow")
struct MailSendApprovalFlowTests {
    @Test func mailSendDraftYieldsPermissionRequestedAndSendsAfterApprovalInAskMode() async throws {
        let store = try makeMailApprovalStore()
        let repository = AppChatSessionRepository(store: store)
        let session = AgentSession(id: "mail-approval-session", title: "Mail Approval", createdAt: Date(timeIntervalSince1970: 1_000))
        try repository.saveSession(session)

        let runtime = MailRuntime.fixture()
        let draft = try await runtime.createDraft(
            accountID: MailAccountID(rawValue: "fixture-account"),
            identityID: MailIdentityID(rawValue: "fixture-identity"),
            to: [MailAddress(email: "bob@example.com")],
            subject: "Approval send",
            body: "Should require approval"
        )

        var registry = AgentToolRegistry()
        registry.registerNativeMailTools(runtime: runtime)

        let loop = AgentLoopController(
            modelProvider: MailApprovalScriptedProvider(responses: [
                AgentModelResponse(
                    text: nil,
                    toolCalls: [AgentToolCall(id: "mail-send-call", name: "mail_send_draft", argumentsJSON: "{\"draftID\":\"\(draft.id.rawValue)\"}")],
                    usage: AgentModelUsage(promptTokens: 10, completionTokens: 3),
                    finishReason: .toolCalls
                ),
                AgentModelResponse(
                    text: "Mail sent after approval.",
                    toolCalls: [],
                    usage: AgentModelUsage(promptTokens: 20, completionTokens: 5),
                    finishReason: .stop
                )
            ]),
            toolRegistry: registry,
            configuration: AgentLoopConfiguration(permissionMode: .askToWrite)
        )
        var manager = NativeSessionManager(loopController: loop, sessionRepository: repository, session: session)

        let approvalTask = Task {
            var approval: AgentPendingApproval?
            for _ in 0..<300 {
                if let pending = try store.pendingApprovals(status: .pending, limit: 10).first {
                    approval = pending
                    break
                }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            let pending = try #require(approval, "No pending approval appeared for mail_send_draft in ask mode")
            #expect(pending.capability == .sendMail)
            #expect(pending.toolName == "mail_send_draft")
            #expect(pending.sessionID == session.id)
            #expect(pending.status == .pending)
            await loop.resolveApproval(pending, status: .approved)
        }

        let response = try await manager.submit("Send the email")
        try await approvalTask.value

        #expect(response.events.map(\.kind).contains(.permissionRequested))
        #expect(response.events.map(\.kind).contains(.permissionResolved))
        #expect(response.assistantMessage?.content == "Mail sent after approval.")
    }

    @Test func mailSendDraftAutoApprovesAndSendsInExecuteMode() async throws {
        let store = try makeMailApprovalStore()
        let repository = AppChatSessionRepository(store: store)
        let session = AgentSession(id: "mail-execute-session", title: "Mail Execute", createdAt: Date(timeIntervalSince1970: 1_000))
        try repository.saveSession(session)

        let runtime = MailRuntime.fixture()
        let draft = try await runtime.createDraft(
            accountID: MailAccountID(rawValue: "fixture-account"),
            identityID: MailIdentityID(rawValue: "fixture-identity"),
            to: [MailAddress(email: "bob@example.com")],
            subject: "Execute send",
            body: "Should send immediately"
        )

        var registry = AgentToolRegistry()
        registry.registerNativeMailTools(runtime: runtime)

        let loop = AgentLoopController(
            modelProvider: MailApprovalScriptedProvider(responses: [
                AgentModelResponse(
                    text: nil,
                    toolCalls: [AgentToolCall(id: "mail-send-call-execute", name: "mail_send_draft", argumentsJSON: "{\"draftID\":\"\(draft.id.rawValue)\"}")],
                    usage: AgentModelUsage(promptTokens: 10, completionTokens: 3),
                    finishReason: .toolCalls
                ),
                AgentModelResponse(
                    text: "Mail sent immediately.",
                    toolCalls: [],
                    usage: AgentModelUsage(promptTokens: 20, completionTokens: 5),
                    finishReason: .stop
                )
            ]),
            toolRegistry: registry,
            configuration: AgentLoopConfiguration(permissionMode: .trustedWrite)
        )
        var manager = NativeSessionManager(loopController: loop, sessionRepository: repository, session: session)

        // 执行模式（trustedWrite）下 mail_send_draft 自动放行并直接发送：
        // 不产出 .permissionRequested/.permissionResolved，不留待审批记录。
        let response = try await manager.submit("Send the email")

        #expect(!response.events.map(\.kind).contains(.permissionRequested))
        #expect(!response.events.map(\.kind).contains(.permissionResolved))
        #expect(response.assistantMessage?.content == "Mail sent immediately.")
        #expect(try store.pendingApprovals(status: .pending, limit: 10).isEmpty)
    }
}

private actor MailApprovalScriptedProvider: AgentModelProvider {
    let modelID = "mail-approval-scripted"
    let capabilities = AgentModelCapabilities(
        supportsStreaming: false,
        supportsToolCalling: true,
        supportsParallelToolCalls: false,
        supportsStructuredOutput: false,
        supportsVision: false
    )
    private var responses: [AgentModelResponse]

    init(responses: [AgentModelResponse]) {
        self.responses = responses
    }

    func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse {
        if let automatic = appSupportAutomaticPhaseResponse(for: request, nextResponse: responses.first) {
            return automatic
        }
        return responses.removeFirst()
    }
}

private func makeMailApprovalStore() throws -> SQLiteGraphKernelStore {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("mail-approval-\(UUID().uuidString).sqlite")
    let store = try SQLiteGraphKernelStore(path: url.path)
    try store.migrate()
    return store
}
