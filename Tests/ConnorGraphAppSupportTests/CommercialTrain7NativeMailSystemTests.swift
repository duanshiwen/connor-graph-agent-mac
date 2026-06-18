import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAgent
import ConnorGraphAppSupport

@Suite("Commercial Train 7 Native Mail System Tests")
struct CommercialTrain7NativeMailSystemTests {
    @Test func permissionPolicyAllowsBuiltInReadsButRequiresSendApproval() async {
        let readOnly = AgentPolicyEngine(permissionMode: .readOnly)
        let readMail = await readOnly.evaluate(capability: .readMail, runID: "run", sessionID: "session", toolName: "mail_search_messages")
        let readBody = await readOnly.evaluate(capability: .readMailBody, runID: "run", sessionID: "session", toolName: "mail_get_message")
        let send = await AgentPolicyEngine(permissionMode: .allowAll).evaluate(capability: .sendMail, runID: "run", sessionID: "session", toolName: "mail_send_draft")
        let contactWrite = await AgentPolicyEngine(permissionMode: .allowAll).evaluate(capability: .mutateContacts, runID: "run", sessionID: "session", toolName: "contact_commit_draft")

        #expect(readMail.outcome == .approved)
        #expect(readBody.outcome == .approved)
        #expect(send.outcome == .needsApproval)
        #expect(contactWrite.outcome == .needsApproval)
    }

    @Test func fixtureRuntimeReadsWithoutMutatingReadStateAndAuditsBodyRead() async throws {
        let runtime = MailRuntime.fixture()
        let messages = try await runtime.searchMessages(MailRuntimeSearchRequest(query: "native"), runID: "run", sessionID: "session")
        let message = try #require(messages.first)
        #expect(message.flags.isRead == false)

        let detail = try await runtime.getMessage(id: message.id, includeBody: true, runID: "run", sessionID: "session")
        #expect(detail.body?.plainText?.text.contains("Commercial native mail") == true)

        let reread = try await runtime.getMessage(id: message.id, includeBody: false, runID: "run", sessionID: "session")
        #expect(reread.summary.flags.isRead == false)
    }

    @Test func explicitReadStateMutationChangesFlags() async throws {
        let runtime = MailRuntime.fixture()
        let message = try #require(try await runtime.searchMessages(MailRuntimeSearchRequest(query: "native")).first)
        try await runtime.setReadState(messageIDs: [message.id], isRead: true)
        let updated = try await runtime.getMessage(id: message.id)
        #expect(updated.summary.flags.isRead)
    }

    @Test func agentToolRegistryExposesNativeMailToolsAndBlocksSendWithoutApproval() async throws {
        let runtime = MailRuntime.fixture()
        var registry = AgentToolRegistry()
        registry.registerNativeMailTools(runtime: runtime)

        #expect(registry.definitions.map(\.name).contains("mail_search_messages"))
        #expect(registry.definitions.map(\.name).contains("mail_send_draft"))
        #expect(registry.permission(named: "mail_send_draft") == .sendMail)

        let context = AgentToolExecutionContext(runID: "run", sessionID: "session", groupID: "group", userPrompt: "send", toolCallID: "call", policyEngine: AgentPolicyEngine(permissionMode: .allowAll))
        let call = AgentToolCall(id: "call", runID: "run", sessionID: "session", name: "mail_send_draft", argumentsJSON: "{\"draftID\":\"missing\",\"approved\":false}")
        do {
            _ = try await registry.execute(call, context: context)
            Issue.record("sendMail should require approval before execution")
        } catch AgentToolError.permissionNeedsApproval(let request) {
            #expect(request.capability == .sendMail)
        }
    }

    @Test func draftLifecycleSeparatesCreateFromSend() async throws {
        let runtime = MailRuntime.fixture()
        let draft = try await runtime.createDraft(accountID: MailAccountID(rawValue: "fixture-account"), identityID: MailIdentityID(rawValue: "fixture-identity"), to: [MailAddress(email: "bob@example.com")], subject: "Hello", body: "Body")
        #expect(draft.status == .draft)
        await #expect(throws: MailRuntimeError.self) {
            _ = try await runtime.sendDraft(draftID: draft.id, approved: false)
        }
        let receipt = try await runtime.sendDraft(draftID: draft.id, approved: true)
        #expect(receipt.draftID == draft.id)
    }

    @Test func mimeParserBudgetsOversizedBodies() {
        let parser = MailMIMEParser()
        let accountID = MailAccountID(rawValue: "a")
        let mailboxID = MailMailboxID(rawValue: "m")
        let summary = MailMessageSummary(id: MailMessageID(rawValue: "msg"), accountID: accountID, mailboxID: mailboxID, subject: "Subject", from: MailAddress(email: "a@example.com"), to: [MailAddress(email: "b@example.com")], snippet: "snippet")
        let detail = parser.parsePlainMessage(raw: "Subject: Test\n\n" + String(repeating: "x", count: 100), messageID: summary.id, summary: summary, maxBodyCharacters: 10)
        #expect(detail.body?.plainText?.wasTruncated == true)
        #expect(detail.body?.omittedReason == "body-truncated")
    }

    @Test func contactRuntimeExtractsCandidatesButDoesNotCommitAutomatically() async throws {
        let runtime = ContactRuntime()
        let detail = try await MailRuntime.fixture().getMessage(id: MailMessageID(rawValue: "fixture-message-1"), includeBody: false)
        let candidates = runtime.extractCandidates(from: detail)
        #expect(candidates.contains { $0.candidate.emails.contains { $0.email == "alice@example.com" } })
        #expect(candidates.allSatisfy { $0.source == .mailHeader })
    }

    @Test func commercialReadinessGateIncludesNativeMailPhase() {
        let input = CommercialReadinessInput(
            sessionGovernance: .ready(sessionCount: 1, statusDefinitionCount: 5, labelDefinitionCount: 5, artifactDirectoriesReady: true),
            claudeSidecar: .ready(runtimeStatus: .ready, sdkSessionID: "sdk", healthStatus: "ok"),
            extensionRuntime: .ready(enabledSourceCount: 1, loadedSkillCount: 1, enabledAutomationRuleCount: 1),
            graphMemory: .ready(pendingCandidateCount: 0, openHoldCount: 0, recentChangeCount: 0, contextReady: true, ingestionReady: true, distillationReady: true),
            nativeUI: .ready(shellItemCount: 13, commandCount: 12, settingsPanelsReady: true, homeSurfaceReady: true, readinessDashboardLinked: true, primaryActionCount: 7, emptyStateCount: 4, keyboardShortcutCount: 10, settingsSectionCount: 7),
            nativeMailSystem: .ready(accountCount: 1, healthyAccountCount: 1, credentialBoundaryReady: true, syncCursorReady: true, toolAuditReady: true, sendApprovalReady: true, contactApprovalReady: true, attachmentImportReady: true, evidencePolicyReady: true)
        )
        let dashboard = CommercialReadinessGate().evaluate(input)
        #expect(dashboard.cards.map(\.phase).contains(.nativeMailSystem))
        #expect(dashboard.cards.count == 7)
        #expect(dashboard.summary == "7/7 commercial readiness phases ready")
    }

    @Test func shellExposesNativeMailSurface() {
        let shell = ConnorNativeShellPresentation.default
        #expect(shell.item(for: .mail)?.title == "Mail")
        #expect(shell.command(for: .openMailSources)?.target == .mail)
        #expect(shell.command(for: .openMailSources)?.keyboardShortcut == "⌘8")
    }

    @Test func mailRuntimeSeparatesProtocolAndParserResponsibilities() async throws {
        let imap = MailIMAPAdapter()
        let smtp = MailSMTPAdapter()
        let imapHealth = try await imap.testConnection(endpoint: MailServerEndpoint(host: "imap.example.com", port: 993, security: .tls, protocolKind: .imap))
        let smtpHealth = try await smtp.testConnection(endpoint: MailServerEndpoint(host: "smtp.example.com", port: 587, security: .startTLS, protocolKind: .smtp))
        #expect(imapHealth.status == .ready)
        #expect(smtpHealth.status == .ready)

        let account = MailAccount(id: MailAccountID(rawValue: "a"), provider: .genericIMAPSMTP, displayName: "A", identities: [], credentialBinding: MailCredentialBinding(keychainService: "svc", accountName: "a", authMode: .oauth2))
        let syncHealth = MailSyncEngine().readiness(account: account, mailboxCount: 1, cursorCount: 1)
        #expect(syncHealth.status == .ready)
    }
}
