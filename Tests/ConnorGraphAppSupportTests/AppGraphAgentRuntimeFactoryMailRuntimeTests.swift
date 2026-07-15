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
