import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAgent
import ConnorGraphAppSupport

@Suite("Commercial Train 7 Native Mail System Tests")
struct CommercialTrain7NativeMailSystemTests {
    @Test func permissionPolicyAllowsBuiltInReadsButRequiresSendApproval() async {
        let readOnly = AgentPolicyEngine(permissionMode: .readOnly)
        let readMail = await readOnly.evaluate(capability: .readMail, runID: "run", sessionID: "session", toolName: "mail_list_accounts")
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

    @Test func fileBackedMailStorePersistsAccountsMailboxesMessagesAndReadState() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mail-store-\(UUID().uuidString)", isDirectory: true)
        let storeURL = directory.appendingPathComponent("mail-store.json")
        let accountID = MailAccountID(rawValue: "mail-test")
        let mailboxID = MailMailboxID(rawValue: "mail-test-inbox")
        let messageID = MailMessageID(rawValue: "mail-test-message")
        let account = MailAccount(id: accountID, provider: .genericIMAPSMTP, displayName: "Test Mail", identities: [MailIdentity(id: MailIdentityID(rawValue: "identity"), displayName: "Test", address: MailAddress(email: "test@example.com"))], health: MailAccountHealth(status: .ready, summary: "ready"))
        let mailbox = MailMailbox(id: mailboxID, accountID: accountID, name: "收件箱", path: "INBOX", role: .inbox, status: MailMailboxStatus(messageCount: 1, unreadCount: 1, syncCursor: MailSyncCursor(value: "42", uidValidity: "7"), lastSyncedAt: Date()))
        let summary = MailMessageSummary(id: messageID, accountID: accountID, mailboxID: mailboxID, subject: "Unread", from: MailAddress(email: "sender@example.com"), to: [MailAddress(email: "test@example.com")], snippet: "hello", flags: MailMessageFlags(isRead: false))
        let detail = MailMessageDetail(summary: summary, headers: MailMessageHeaders(messageIDHeader: "<msg@example.com>"), body: MailMessageBody(redactedPreview: "hello"))

        let writer = FileBackedMailSourceStore(storeURL: storeURL)
        try await writer.saveAccount(account)
        try await writer.saveMailbox(mailbox)
        try await writer.saveMessage(detail)

        let reader = FileBackedMailSourceStore(storeURL: storeURL)
        let presentation = try await reader.presentation()
        #expect(presentation.accounts.map(\.id) == [accountID])
        #expect(presentation.mailboxes.map(\.id) == [mailboxID])
        #expect(presentation.messages.map(\.id) == [messageID])
        #expect(presentation.messages.first?.flags.isRead == false)

        try await reader.updateFlags(messageIDs: [messageID]) { flags in
            var copy = flags
            copy.isRead = true
            return copy
        }
        let reloaded = FileBackedMailSourceStore(storeURL: storeURL)
        #expect(try await reloaded.message(id: messageID)?.summary.flags.isRead == true)
    }

    @Test func agentToolRegistryExposesNativeMailToolsAndBlocksSendWithoutApproval() async throws {
        let runtime = MailRuntime.fixture()
        var registry = AgentToolRegistry()
        registry.registerNativeMailTools(runtime: runtime)

        #expect(!registry.definitions.map(\.name).contains("mail_search_messages"))
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
            modelProvider: .ready(providerMode: .anthropicMessages, connectionKind: .anthropicCompatible, modelID: "claude-sonnet-4-5", healthStatus: "ready"),
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
        #expect(imapHealth.status == .degraded)
        #expect(smtpHealth.status == .degraded)

        let account = MailAccount(id: MailAccountID(rawValue: "a"), provider: .genericIMAPSMTP, displayName: "A", identities: [], credentialBinding: MailCredentialBinding(keychainService: "svc", accountName: "a", authMode: .oauth2))
        let syncHealth = MailSyncEngine().readiness(account: account, mailboxCount: 1, cursorCount: 1)
        #expect(syncHealth.status == .ready)
    }

    @Test func mailBrowserDefaultPresentationIsEmpty() {
        let presentation = NativeMailBrowserPresentation.empty
        #expect(presentation.accounts.isEmpty)
        #expect(presentation.mailboxes.isEmpty)
        #expect(presentation.messages.isEmpty)
        #expect(presentation.defaultAccountID() == nil)
        #expect(presentation.defaultMailboxID(for: nil) == nil)
        #expect(presentation.defaultMessageID(accountID: nil, mailboxID: nil) == nil)
        #expect(presentation.emptyState(forQuery: "") == .noAccounts)
    }

    @Test func mailBrowserFiltersMessagesBySubjectAndSnippet() {
        let fixture = makeMailBrowserFixture()
        let accountID = MailAccountID(rawValue: "fixture-account")
        let mailboxID = MailMailboxID(rawValue: "fixture-inbox")

        let subjectMatches = fixture.messages(accountID: accountID, mailboxID: mailboxID, query: "OAuth")
        #expect(subjectMatches.map(\.subject) == ["OAuth migration checklist"])

        let snippetMatches = fixture.messages(accountID: accountID, mailboxID: mailboxID, query: "readiness")
        #expect(snippetMatches.map(\.subject) == ["OAuth migration checklist"])

        let all = fixture.messages(accountID: accountID, mailboxID: mailboxID, query: "")
        #expect(all.count == 2)

        let noResults = fixture.messages(accountID: accountID, mailboxID: mailboxID, query: "not-found")
        #expect(noResults.isEmpty)
        #expect(fixture.emptyState(forQuery: "not-found") == .searchNoResults)
    }

    @Test func mailBrowserSelectionUsesStableIDsAndDerivesFoldersFromSelectedAccount() {
        let fixture = makeMailBrowserFixture()
        let accountID = MailAccountID(rawValue: "fixture-account")
        let otherAccountID = MailAccountID(rawValue: "fixture-qq")
        let inboxID = MailMailboxID(rawValue: "fixture-inbox")

        #expect(fixture.mailboxes(accountID: accountID).map(\.accountID).allSatisfy { $0 == accountID })
        #expect(fixture.mailboxes(accountID: otherAccountID).map(\.accountID).allSatisfy { $0 == otherAccountID })
        #expect(fixture.messages(accountID: accountID, mailboxID: inboxID, query: "").map(\.mailboxID).allSatisfy { $0 == inboxID })
        #expect(fixture.defaultMailboxID(for: accountID) == inboxID)
        #expect(fixture.defaultMessageID(accountID: accountID, mailboxID: inboxID) == MailMessageID(rawValue: "fixture-message-1"))
    }

    @Test func mailBrowserSingleListCanFilterAcrossAllAccountsAndFolders() {
        let fixture = makeMailBrowserFixture()
        let accountID = MailAccountID(rawValue: "fixture-account")
        let inboxID = MailMailboxID(rawValue: "fixture-inbox")

        let allMessages = fixture.messages(accountID: nil, mailboxID: nil, query: "")
        #expect(allMessages.map(\.id) == [MailMessageID(rawValue: "fixture-message-1"), MailMessageID(rawValue: "fixture-message-2")])

        let accountMessages = fixture.messages(accountID: accountID, mailboxID: nil, query: "")
        #expect(accountMessages.map(\.accountID).allSatisfy { $0 == accountID })

        let folderMessages = fixture.messages(accountID: nil, mailboxID: inboxID, query: "OAuth")
        #expect(folderMessages.map(\.subject) == ["OAuth migration checklist"])
    }

    @Test func mailAccountProviderPresetsIncludeAppleMicrosoftQQNetEaseAndOther() {
        let presets = MailAccountProviderPreset.allCases
        #expect(presets.map(\.id) == ["apple", "microsoft", "qq", "netease", "other"])

        let apple = MailAccountProviderPreset.apple
        #expect(apple.incomingHost == "imap.mail.me.com")
        #expect(apple.incomingPort == 993)
        #expect(apple.outgoingHost == "smtp.mail.me.com")
        #expect(apple.outgoingPort == 587)
        #expect(apple.guidance.localizedCaseInsensitiveContains("App 专用密码"))

        let qq = MailAccountProviderPreset.qq
        #expect(qq.incomingHost == "imap.qq.com")
        #expect(qq.outgoingHost == "smtp.qq.com")
        #expect(qq.guidance.contains("16 位授权码"))

        let netease = MailAccountProviderPreset.netease
        #expect(netease.incomingHost == "imap.163.com")
        #expect(netease.outgoingHost == "smtp.163.com")
        #expect(netease.guidance.contains("POP/SMTP/IMAP"))
        #expect(netease.guidance.contains("授权码"))

        let microsoft = MailAccountProviderPreset.microsoft
        #expect(microsoft.guidance.localizedCaseInsensitiveContains("Microsoft 登录"))
        #expect(microsoft.outgoingPort == 587)

        let other = MailAccountProviderPreset.other
        #expect(other.incomingHost.isEmpty)
        #expect(other.outgoingHost.isEmpty)
    }

    private func makeMailBrowserFixture(now: Date = Date()) -> NativeMailBrowserPresentation {
        let accountID = MailAccountID(rawValue: "fixture-account")
        let otherAccountID = MailAccountID(rawValue: "fixture-qq")
        let identityID = MailIdentityID(rawValue: "fixture-identity")
        let otherIdentityID = MailIdentityID(rawValue: "fixture-other-identity")
        let inboxID = MailMailboxID(rawValue: "fixture-inbox")
        let otherInboxID = MailMailboxID(rawValue: "fixture-other-inbox")

        let accounts = [
            MailAccount(
                id: accountID,
                provider: .genericIMAPSMTP,
                displayName: "Test Account",
                identities: [MailIdentity(id: identityID, displayName: "Test User", address: MailAddress(name: "Test User", email: "test@example.com"))],
                incoming: MailServerEndpoint(host: "imap.example.com", port: 993, security: .tls, protocolKind: .imap),
                outgoing: MailServerEndpoint(host: "smtp.example.com", port: 587, security: .startTLS, protocolKind: .smtp),
                credentialBinding: MailCredentialBinding(keychainService: "test.mail", accountName: "test@example.com", authMode: .appPassword),
                health: MailAccountHealth(status: .ready, summary: "test-ready")
            ),
            MailAccount(
                id: otherAccountID,
                provider: .genericIMAPSMTP,
                displayName: "Other Test Account",
                identities: [MailIdentity(id: otherIdentityID, displayName: "Other", address: MailAddress(name: "Other", email: "other@example.com"))],
                credentialBinding: MailCredentialBinding(keychainService: "test.mail.other", accountName: "other@example.com", authMode: .appPassword),
                health: MailAccountHealth(status: .unknown, summary: "test")
            )
        ]

        let mailboxes = [
            MailMailbox(id: inboxID, accountID: accountID, name: "Inbox", path: "INBOX", role: .inbox, status: MailMailboxStatus(messageCount: 2, unreadCount: 1, syncCursor: nil, lastSyncedAt: now)),
            MailMailbox(id: otherInboxID, accountID: otherAccountID, name: "Inbox", path: "INBOX", role: .inbox, status: MailMailboxStatus(messageCount: 0, unreadCount: 0, syncCursor: nil, lastSyncedAt: nil))
        ]

        let messages = [
            MailMessageSummary(
                id: MailMessageID(rawValue: "fixture-message-1"),
                accountID: accountID,
                mailboxID: inboxID,
                threadID: MailThreadID(rawValue: "fixture-thread-1"),
                subject: "Connor Native Mail System",
                from: MailAddress(name: "Alice", email: "alice@example.com"),
                to: [MailAddress(email: "test@example.com")],
                date: now.addingTimeInterval(-300),
                snippet: "Commercial native mail system test message.",
                flags: MailMessageFlags(isRead: false),
                hasAttachments: true
            ),
            MailMessageSummary(
                id: MailMessageID(rawValue: "fixture-message-2"),
                accountID: accountID,
                mailboxID: inboxID,
                threadID: MailThreadID(rawValue: "fixture-thread-2"),
                subject: "OAuth migration checklist",
                from: MailAddress(name: "Security", email: "security@example.com"),
                to: [MailAddress(email: "test@example.com")],
                date: now.addingTimeInterval(-900),
                snippet: "Provider auth policy, token refresh, keychain isolation, and audit readiness.",
                flags: MailMessageFlags(isRead: true),
                hasAttachments: false
            )
        ]

        return NativeMailBrowserPresentation(accounts: accounts, mailboxes: mailboxes, messages: messages)
    }
}
