import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAgent

private struct DuplicateDummyTool: AgentTool {
    var name: String
    var description: String
    var permission: AgentPermissionCapability { .readGraph }
    var inputSchema: AgentToolInputSchema { .object(properties: [:], required: []) }
    func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "ok")
    }
}

@Suite("Native Source Search Tool Governance Tests")
struct NativeSourceSearchToolGovernanceTests {
    @Test func registryRecordsDuplicateRegistrationDiagnostics() {
        var registry = AgentToolRegistry()
        registry.register(DuplicateDummyTool(name: "same_tool", description: "first"))
        registry.register(DuplicateDummyTool(name: "same_tool", description: "second"))

        #expect(registry.duplicateRegistrations.count == 1)
        #expect(registry.duplicateRegistrations.first?.name == "same_tool")
        #expect(registry.duplicateRegistrations.first?.replacedDescription == "first")
        #expect(registry.definition(named: "same_tool")?.description == "second")
    }

    @Test func nativeSearchToolsExposeTemporalFiltersWithoutDuplicateSearchTools() {
        var registry = AgentToolRegistry()
        registry.registerNativeMailTools(runtime: MailRuntimeSearchFixture())
        registry.registerNativeRSSTools(runtime: RSSRuntimeSearchFixture())
        registry.registerNativeCalendarTools(runtime: InMemoryAgentCalendarRuntime())

        let names = registry.definitions.map(\.name)
        #expect(Set(names).count == names.count)
        #expect(registry.duplicateRegistrations.isEmpty)
        #expect(names.contains("mail_search_messages"))
        #expect(names.contains("rss_search_items"))
        #expect(names.contains("calendar_read"))
        #expect(!names.contains("mail_index_search"))
        #expect(!names.contains("rss_index_search"))
        #expect(!names.contains("calendar_index_search"))

        let mailSchema = registry.definition(named: "mail_search_messages")?.inputSchema
        let rssSchema = registry.definition(named: "rss_search_items")?.inputSchema
        let calendarSchema = registry.definition(named: "calendar_read")?.inputSchema
        #expect(schema(mailSchema, contains: "startDate"))
        #expect(schema(rssSchema, contains: "timePreset"))
        #expect(schema(calendarSchema, contains: "timeFilterMode"))
    }

    @Test func systemPromptDoesNotExposeInternalNativeSearchMethods() {
        let prompt = AgentInstructionSection.defaultConnorInstruction
        #expect(!prompt.contains("mail_search_messages"))
        #expect(!prompt.contains("rss_search_items"))
        #expect(!prompt.contains("search_events"))
        #expect(!prompt.localizedCaseInsensitiveContains("timePreset"))
        #expect(!prompt.localizedCaseInsensitiveContains("startDate"))
        #expect(!prompt.localizedCaseInsensitiveContains("Native Source Search"))
    }

    private func schema(_ schema: AgentToolInputSchema?, contains key: String) -> Bool {
        guard case .object(let properties, _) = schema else { return false }
        return properties.keys.contains(key)
    }
}

private struct MailRuntimeSearchFixture: AgentMailRuntime {
    func listAccounts(runID: String?, sessionID: String?) async throws -> [MailAccount] { [] }
    func searchMessages(_ request: MailRuntimeSearchRequestBridge, runID: String?, sessionID: String?) async throws -> [MailMessageSummary] { [] }
    func getMessage(id: MailMessageID, includeBody: Bool, runID: String?, sessionID: String?) async throws -> MailMessageDetail { throw AgentToolError.invalidArguments("fixture") }
    func setReadState(messageIDs: [MailMessageID], isRead: Bool, runID: String?, sessionID: String?) async throws {}
    func createDraft(accountID: MailAccountID, identityID: MailIdentityID, to: [MailAddress], subject: String, body: String, runID: String?, sessionID: String?) async throws -> MailDraft { MailDraft(id: MailDraftID(rawValue: "d"), accountID: accountID, identityID: identityID, to: to, subject: subject, body: body) }
    func sendDraft(draftID: MailDraftID, approved: Bool, runID: String?, sessionID: String?) async throws -> MailSendReceipt { MailSendReceipt(draftID: draftID, providerMessageID: "p", envelopeHash: "h") }
}

private struct RSSRuntimeSearchFixture: AgentRSSRuntime {
    func listSources(runID: String?, sessionID: String?) async throws -> [RSSSource] { [] }
    func addSource(feedURL: URL, displayName: String?, runID: String?, sessionID: String?) async throws -> RSSSource { RSSSource(id: RSSSourceID(rawValue: "s"), feedURL: feedURL, displayName: displayName ?? "s") }
    func syncSource(sourceID: RSSSourceID, runID: String?, sessionID: String?) async throws -> RSSFetchResult { throw AgentToolError.invalidArguments("fixture") }
    func listItems(sourceID: RSSSourceID?, includeHidden: Bool, limit: Int, runID: String?, sessionID: String?) async throws -> [RSSItemSummary] { [] }
    func searchItems(_ request: RSSRuntimeSearchRequestBridge, runID: String?, sessionID: String?) async throws -> [RSSItemSummary] { [] }
    func getItem(id: RSSItemID, includeContent: Bool, runID: String?, sessionID: String?) async throws -> RSSItemDetail { throw AgentToolError.invalidArguments("fixture") }
    func setReadState(itemIDs: [RSSItemID], isRead: Bool, runID: String?, sessionID: String?) async throws {}
    func setStarState(itemIDs: [RSSItemID], isStarred: Bool, runID: String?, sessionID: String?) async throws {}
    func setHiddenState(itemIDs: [RSSItemID], isHidden: Bool, runID: String?, sessionID: String?) async throws {}
    func importOPML(_ xml: String, runID: String?, sessionID: String?) async throws -> OPMLDocument { OPMLDocument(title: "", outlines: []) }
    func exportOPML(runID: String?, sessionID: String?) async throws -> String { "" }
    func evidenceCandidate(for itemID: RSSItemID) async throws -> RSSEvidenceCandidate { throw AgentToolError.invalidArguments("fixture") }
}
