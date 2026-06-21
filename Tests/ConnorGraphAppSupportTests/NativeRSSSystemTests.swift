import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAgent
import ConnorGraphAppSupport

@Suite("Native RSS System Tests")
struct NativeRSSSystemTests {
    @Test func permissionPolicyAllowsReadsAndProtectsMutations() async {
        let readOnly = AgentPolicyEngine(permissionMode: .readOnly)
        let read = await readOnly.evaluate(capability: .readRSS, runID: "run", sessionID: "session", toolName: "rss_list_items")
        let content = await readOnly.evaluate(capability: .readRSSContent, runID: "run", sessionID: "session", toolName: "rss_get_item")
        let mutate = await readOnly.evaluate(capability: .mutateRSSState, runID: "run", sessionID: "session", toolName: "rss_set_read_state")
        let manage = await AgentPolicyEngine(permissionMode: .trustedWrite).evaluate(capability: .manageRSSSources, runID: "run", sessionID: "session", toolName: "rss_add_source")

        #expect(read.outcome == .approved)
        #expect(content.outcome == .approved)
        #expect(mutate.outcome == .denied)
        #expect(manage.outcome == .needsApproval)
    }

    @Test func fixtureRuntimeReadsContentAndMutatesStateExplicitly() async throws {
        let runtime = RSSRuntime.fixture()
        let items = try await runtime.searchItems(RSSRuntimeSearchRequest(query: "native"), runID: "run", sessionID: "session")
        let item = try #require(items.first)
        #expect(item.state.isRead == false)

        let detail = try await runtime.getItem(id: item.id, includeContent: true, runID: "run", sessionID: "session")
        #expect(detail.content?.plainText.localizedCaseInsensitiveContains("native RSS") == true)

        try await runtime.setReadState(itemIDs: [item.id], isRead: true)
        let updated = try await runtime.getItem(id: item.id)
        #expect(updated.summary.state.isRead)
    }

    @Test func agentToolRegistryExposesNativeRSSTools() async throws {
        let runtime = RSSRuntime.fixture()
        var registry = AgentToolRegistry()
        registry.registerNativeRSSTools(runtime: runtime)

        let toolNames = registry.definitions.map(\.name)
        #expect(!toolNames.contains("rss_search_items"))
        #expect(!toolNames.contains("rss_import_opml"))
        #expect(!toolNames.contains("rss_export_opml"))
        #expect(registry.permission(named: "rss_get_item") == .readRSSContent)
        #expect(registry.permission(named: "rss_add_source") == .manageRSSSources)

        let context = AgentToolExecutionContext(runID: "run", sessionID: "session", groupID: "group", userPrompt: "rss", toolCallID: "call", policyEngine: AgentPolicyEngine(permissionMode: .readOnly))
        let call = AgentToolCall(id: "call", runID: "run", sessionID: "session", name: "rss_list_items", argumentsJSON: "{\"limit\":1}")
        let result = try await registry.execute(call, context: context)
        #expect(result.contentText.contains("RSS item"))
    }

    @Test func parserHandlesRSSAtomAndJSONFeed() throws {
        let source = RSSSource(id: RSSSourceID(rawValue: "s"), feedURL: URL(string: "https://example.com/feed")!, displayName: "Example")
        let parser = RSSFeedParser()

        let rss = """
        <rss version="2.0"><channel><title>RSS Title</title><link>https://example.com</link><item><title>RSS Item</title><link>https://example.com/a</link><guid>a</guid><pubDate>Fri, 19 Jun 2026 00:00:00 +0800</pubDate><description><![CDATA[<p>Hello <b>RSS</b></p>]]></description></item></channel></rss>
        """
        let parsedRSS = try parser.parse(data: Data(rss.utf8), source: source)
        #expect(parsedRSS.metadata.format == .rss)
        #expect(parsedRSS.items.first?.summary.title == "RSS Item")
        #expect(parsedRSS.items.first?.content?.plainText.contains("Hello RSS") == true)

        let atom = """
        <feed xmlns="http://www.w3.org/2005/Atom"><title>Atom Title</title><link href="https://example.com"/><entry><title>Atom Item</title><id>atom-1</id><link href="https://example.com/atom"/><updated>2026-06-19T00:00:00+08:00</updated><summary>Atom summary</summary></entry></feed>
        """
        let parsedAtom = try parser.parse(data: Data(atom.utf8), source: source)
        #expect(parsedAtom.metadata.format == .atom)
        #expect(parsedAtom.items.first?.summary.title == "Atom Item")

        let json = """
        {"version":"https://jsonfeed.org/version/1.1","title":"JSON Title","home_page_url":"https://example.com","items":[{"id":"json-1","url":"https://example.com/json","title":"JSON Item","content_text":"JSON body","date_published":"2026-06-19T00:00:00+08:00","author":{"name":"Alice"}}]}
        """
        let parsedJSON = try parser.parse(data: Data(json.utf8), source: source)
        #expect(parsedJSON.metadata.format == .jsonFeed)
        #expect(parsedJSON.items.first?.summary.author == "Alice")
    }

    @Test func opmlRoundTripPreservesSubscriptions() throws {
        let service = RSSOPMLService()
        let doc = OPMLDocument(title: "Feeds", outlines: [OPMLSubscriptionOutline(title: "A", xmlURL: URL(string: "https://example.com/a.xml")!, htmlURL: URL(string: "https://example.com"))])
        let xml = service.export(document: doc)
        let parsed = try service.parse(xml)
        #expect(parsed.outlines.count == 1)
        #expect(parsed.outlines.first?.xmlURL.absoluteString == "https://example.com/a.xml")
    }

    @Test func runtimeUpdatesAndDeletesRSSSources() async throws {
        let sourceID = RSSSourceID(rawValue: "example-source")
        let itemID = RSSItemID(rawValue: "example-item")
        let source = RSSSource(id: sourceID, feedURL: URL(string: "https://example.com/feed.xml")!, displayName: "Example")
        let item = RSSItemDetail(summary: RSSItemSummary(id: itemID, sourceID: sourceID, title: "Example Item", snippet: "Cached feed item"))
        let runtime = RSSRuntime(repository: InMemoryRSSSourceRepository(sources: [source]), cache: InMemoryRSSSourceCache(items: [item]))

        let updated = try await runtime.updateSource(sourceID: sourceID, feedURL: URL(string: "https://example.org/rss.xml")!, displayName: "Example Updated")
        #expect(updated.id == sourceID)
        #expect(updated.feedURL.absoluteString == "https://example.org/rss.xml")
        #expect(updated.displayName == "Example Updated")
        #expect(updated.health.status == .unknown)

        try await runtime.deleteSource(sourceID: sourceID)
        let sources = try await runtime.listSources()
        let items = try await runtime.listItems(sourceID: nil, includeHidden: true)
        #expect(sources.isEmpty)
        #expect(items.isEmpty)
    }

    @Test func fileBackedRSSStorageSurvivesRuntimeRestart() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ConnorRSSStorageTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        try paths.ensureDirectoryHierarchy()
        let sourceID = RSSSourceID(rawValue: "swift-blog")
        let itemID = RSSItemID(rawValue: "swift-blog-item")
        let source = RSSSource(id: sourceID, feedURL: URL(string: "https://www.swift.org/blog/feed.xml")!, displayName: "Swift Blog")
        let item = RSSItemDetail(
            summary: RSSItemSummary(
                id: itemID,
                sourceID: sourceID,
                title: "Swift Persistence",
                link: URL(string: "https://swift.org/blog/persistence"),
                author: "Swift.org",
                snippet: "RSS sources should survive app restart."
            ),
            content: RSSItemContent(safeMarkdown: "Swift Persistence", plainText: "RSS sources should survive app restart.")
        )

        let repository = FileBackedRSSSourceRepository(storagePaths: paths)
        let cache = FileBackedRSSSourceCache(storagePaths: paths)
        try await repository.saveSource(source)
        let upsert = try await cache.upsertItems([item])
        #expect(upsert.inserted == 1)

        let restartedRepository = FileBackedRSSSourceRepository(storagePaths: paths)
        let restartedCache = FileBackedRSSSourceCache(storagePaths: paths)
        let restoredSources = try await restartedRepository.listSources()
        let restoredItems = try await restartedCache.listItems(sourceID: sourceID, includeHidden: false)

        #expect(restoredSources.map(\.id).contains(sourceID))
        #expect(restoredItems.map(\.id).contains(itemID))
        #expect(restoredItems.first?.title == "Swift Persistence")
    }

    @Test func presentationFiltersAndDefaults() {
        let runtime = RSSRuntime.fixture()
        let sourceID = RSSSourceID(rawValue: "fixture-rss-source")
        let source = RSSSource(id: sourceID, feedURL: URL(string: "https://example.com/feed.xml")!, displayName: "Fixture")
        let item = RSSItemSummary(id: RSSItemID(rawValue: "i"), sourceID: sourceID, title: "Swift RSS", author: "Alice", snippet: "Connor feed intelligence")
        let presentation = NativeRSSBrowserPresentation(sources: [source], items: [item])
        _ = runtime
        #expect(presentation.defaultSourceID() == sourceID)
        #expect(presentation.defaultItemID(sourceID: sourceID) == item.id)
        #expect(presentation.items(sourceID: nil, query: "connor").count == 1)
        #expect(NativeRSSBrowserPresentation.empty.emptyState(forQuery: "") == .noSources)
    }

    @Test func shellExposesNativeRSSSurface() {
        let shell = ConnorNativeShellPresentation.default
        #expect(shell.item(for: .rss)?.title == "RSS")
        #expect(shell.command(for: .openRSSSources)?.target == .rss)
        #expect(shell.command(for: .openRSSSources)?.keyboardShortcut == "⌘9")
    }
}
