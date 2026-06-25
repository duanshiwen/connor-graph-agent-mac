import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport

@Suite("Browser History Agent Tools Tests")
struct BrowserHistoryAgentToolsTests {
    @Test func browserHistorySearchAndGetExposeSavedPageMarkdown() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("browser-history-agent-tools-")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = BrowserHistoryStore(historyURL: directory.appendingPathComponent("history.jsonl"))
        let record = BrowserHistoryRecord(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            url: "https://example.com/memory-os",
            title: "Memory OS Context Delivery",
            sessionID: "session-browser",
            sessionTitle: "Research Session",
            visitedAt: Date(timeIntervalSince1970: 2_026),
            contentMarkdown: "# Memory OS\n\nSaved browser page body about RSS, calendar, and browser history context.",
            contentFetchedAt: Date(timeIntervalSince1970: 2_100),
            contentFetchStatus: .fetched
        )
        _ = store.appendRecord(record)

        let recorder = BrowserHistorySpyNativeSourceReferenceRecorder()
        var registry = AgentToolRegistry()
        registry.registerBrowserHistoryTools(store: store, recorder: recorder)
        let names = Set(registry.definitions.map(\.name))
        #expect(names.contains("browser_history_search"))
        #expect(names.contains("browser_history_get"))

        let context = AgentToolExecutionContext(
            runID: "run-browser-history",
            sessionID: "session-browser",
            groupID: "group-browser-history",
            userPrompt: "find memory os page",
            toolCallID: "call-search",
            policyEngine: AgentPolicyEngine(permissionMode: .allowAll)
        )
        let search = try await registry.execute(
            AgentToolCall(id: "call-search", name: "browser_history_search", argumentsJSON: "{\"query\":\"Memory OS\",\"limit\":5}"),
            context: context
        )
        #expect(search.contentText.contains("browser history summaries"))
        #expect(search.contentJSON?.contains("11111111-1111-1111-1111-111111111111") == true)
        #expect(search.contentJSON?.contains("Saved browser page body") == true)
        var references = await recorder.references
        #expect(references.count == 1)
        #expect(references[0].sourceKind == .browserHistory)
        #expect(references[0].referenceStrength == .summaryCandidate)
        #expect(references[0].content.contains("Saved browser page body"))

        let get = try await registry.execute(
            AgentToolCall(id: "call-get", name: "browser_history_get", argumentsJSON: "{\"recordID\":\"11111111-1111-1111-1111-111111111111\"}"),
            context: AgentToolExecutionContext(
                runID: "run-browser-history",
                sessionID: "session-browser",
                groupID: "group-browser-history",
                userPrompt: "read page",
                toolCallID: "call-get",
                policyEngine: AgentPolicyEngine(permissionMode: .allowAll)
            )
        )
        #expect(get.contentText.contains("saved page markdown"))
        #expect(get.contentJSON?.contains("# Memory OS") == true)
        #expect(get.contentJSON?.contains("contentMarkdown") == true)
        references = await recorder.references
        #expect(references.count == 2)
        #expect(references[1].referenceStrength == .detailRead)
        #expect(references[1].content.contains("# Memory OS"))
    }
}

private actor BrowserHistorySpyNativeSourceReferenceRecorder: NativeSourceReferenceRecording {
    private(set) var references: [NativeSourceReference] = []
    func record(_ references: [NativeSourceReference]) async {
        self.references.append(contentsOf: references)
    }
}
