import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore
import ConnorGraphStore

private final class FactoryMailSettingsStore: LLMSettingsStore, @unchecked Sendable { private var values:[String:String]=[:]; func string(forKey key:String)->String?{values[key]}; func set(_ value:String,forKey key:String){values[key]=value} }
private final class FactoryMailCredentialStore: CredentialStore, @unchecked Sendable { func saveSecret(_ secret:String,service:String,account:String)throws{}; func readSecret(service:String,account:String)throws->String?{nil}; func deleteSecret(service:String,account:String)throws{} }

@Test func agentRuntimeFactoryUsesInjectedMailRuntime() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("factory-mail-runtime-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let paths = AppStoragePaths(applicationSupportDirectory: root); try paths.ensureDirectoryHierarchy()
    let graph = try SQLiteGraphKernelStore(path: root.appendingPathComponent("graph.sqlite").path); try graph.migrate()
    let accountID = MailAccountID(rawValue: "injected-mail")
    let account = MailAccount(id: accountID, provider: .localFixture, displayName: "Injected Mail", identities: [])
    let mailbox = MailMailbox(id: MailMailboxID(rawValue: "inbox"), accountID: accountID, name: "Inbox", path: "INBOX", role: .inbox)
    let summary = MailMessageSummary(id: MailMessageID(rawValue: "injected-message"), accountID: accountID, mailboxID: mailbox.id, subject: "Injected Mail Subject", from: MailAddress(email: "sender@example.com"), to: [], snippet: "Injected")
    let runtime = MailRuntime(repository: InMemoryMailSourceRepository(accounts: [account]), cache: InMemoryMailSourceCache(mailboxes: [mailbox], messages: [MailMessageDetail(summary: summary)]))
    let factory = AppGraphAgentRuntimeFactory(store: graph, settingsRepository: AppLLMSettingsRepository(settingsStore: FactoryMailSettingsStore(), credentialStore: FactoryMailCredentialStore()), storagePaths: paths, mailRuntime: runtime)
    let controller = factory.makeAgentLoopController(permissionMode: .readOnly)
    let result = try await controller.toolRegistry.execute(AgentToolCall(name: "mail_list_recent_messages", argumentsJSON: #"{"limit":10}"#), context: AgentToolExecutionContext(runID: "run", sessionID: "session", groupID: "default", userPrompt: "mail", toolCallID: "mail", policyEngine: AgentPolicyEngine(permissionMode: .allowAll)))
    #expect(result.contentJSON?.contains("injected-message") == true)
    #expect(result.contentJSON?.contains("Injected Mail Subject") == true)
    let fallback = FileBackedMailSourceStore(storagePaths: paths)
    #expect(try await fallback.allMessageIDs().isEmpty)
}

@Test func fallbackMailRuntimePersistsCreatedDraftsToLocalFile() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("factory-mail-draft-persistence-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let paths = AppStoragePaths(applicationSupportDirectory: root); try paths.ensureDirectoryHierarchy()
    let graph = try SQLiteGraphKernelStore(path: root.appendingPathComponent("graph.sqlite").path); try graph.migrate()
    let accountID = MailAccountID(rawValue: "fallback-mail")
    let identity = MailIdentity(id: MailIdentityID(rawValue: "fallback-identity"), displayName: "Fallback", address: MailAddress(name: "Fallback", email: "fallback@example.com"))
    let account = MailAccount(
        id: accountID,
        provider: .genericIMAPSMTP,
        displayName: "Fallback Mail",
        identities: [identity],
        outgoing: MailServerEndpoint(host: "smtp.example.com", port: 587, security: .startTLS, protocolKind: .smtp)
    )
    let mailStore = FileBackedMailSourceStore(storagePaths: paths)
    try await mailStore.saveAccount(account)

    let factory = AppGraphAgentRuntimeFactory(
        store: graph,
        settingsRepository: AppLLMSettingsRepository(settingsStore: FactoryMailSettingsStore(), credentialStore: FactoryMailCredentialStore()),
        storagePaths: paths
    )
    let controller = factory.makeAgentLoopController(permissionMode: .allowAll)
    let result = try await controller.toolRegistry.execute(
        AgentToolCall(
            name: "mail_create_draft",
            argumentsJSON: #"{"to":["alice@example.com"],"subject":"Persist me","body":"Draft body that must survive app restarts"}"#
        ),
        context: AgentToolExecutionContext(runID: "run", sessionID: "session", groupID: "default", userPrompt: "create mail draft", toolCallID: "draft", policyEngine: AgentPolicyEngine(permissionMode: .allowAll))
    )
    #expect(result.contentText.contains("Created draft") == true)

    // The draft must be recoverable from the local file by a brand-new repository,
    // proving it was persisted on this machine and not kept only in memory.
    let drafts = FileBackedMailDraftRepository(storeURL: paths.mailDraftsURL)
    let persisted = try #require(try await drafts.listDrafts(accountID: accountID, status: .draft).first)
    #expect(persisted.subject == "Persist me")
    #expect(persisted.body == "Draft body that must survive app restarts")
    #expect(FileManager.default.fileExists(atPath: paths.mailDraftsURL.path) == true)
}
