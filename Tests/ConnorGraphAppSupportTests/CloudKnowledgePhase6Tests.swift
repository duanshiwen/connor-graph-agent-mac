import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphStore

@Suite("Cloud Knowledge Phase 6 Tests")
struct CloudKnowledgePhase6Tests {
    @Test func canonicalBackendFixturesDecodeAndRequestUsesByteBudget() throws {
        let homeJSON = #"{"categories":[{"id":"c","slug":"agents","localized_names":{"zh-CN":"智能体"}}],"banners":[],"sections":[{"id":"s","slug":"featured","title":{"zh-CN":"精选"},"section_type":"hero","knowledge_bases":[{"id":"kb-1","name":"Connor","category_id":"agents","subscriber_count":10,"subscribed":false,"publication_status":"published"}]}]}"#
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase; decoder.dateDecodingStrategy = .iso8601
        let home = try decoder.decode(CloudMarketplaceHome.self, from: Data(homeJSON.utf8))
        #expect(home.categories.first?.name == "智能体" && home.sections.first?.layout == "hero" && home.sections.first?.knowledgeBases.first?.id == "kb-1")
        let answerJSON = #"{"request_id":"request","l2":[{"document_id":"00000000-0000-0000-0000-000000000001","knowledge_base_id":"kb-1","identity_id":"i2","revision_id":"r2","layer":"L2","kind":"operational_fact","stable_key":"state","text":"current","rank":1,"score":1,"retriever":"exact","updated_at":"2026-07-17T06:32:10Z"}],"l3":[],"l4":[],"returned_bytes":7,"knowledge_base_ids":["kb-1"]}"#
        let answer = try decoder.decode(CloudKnowledgeAnswerResponse.self, from: Data(answerJSON.utf8))
        #expect(answer.requestID == "request" && answer.partitions.first?.results.first?.text == "current")
        #expect(answer.partitions.first?.results.first?.updatedAt != nil)
        let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
        let body = try #require(try JSONSerialization.jsonObject(with: encoder.encode(CloudKnowledgeAnswerRequest(requestID: "request", query: "Connor", knowledgeBaseIDs: ["kb-1"], contextBudget: 9000))) as? [String: Any])
        #expect(body["context_budget_bytes"] as? Int == 9000)
        #expect(body["request_id"] as? String == "request")
        #expect(body["knowledge_base_ids"] as? [String] == ["kb-1"])
        #expect(body["knowledge_base_i_ds"] == nil)
    }

    @Test func marketplaceLibraryKeepsSubscribedOwnedKnowledgeBaseInBothSections() throws {
        let json = #"{"subscribed":[{"id":"kb-owned","name":"Owned","subscribed":true,"owned":true,"publication_status":"published"}],"owned":[]}"#
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let library = try decoder.decode(CloudMarketplaceLibrary.self, from: Data(json.utf8))

        #expect(library.subscribed.map(\.id) == ["kb-owned"])
        #expect(library.owned.map(\.id) == ["kb-owned"])
        #expect(library.owned.first?.subscribed == true)
        #expect(library.owned.first?.owned == true)
    }

    @Test @MainActor func marketplaceHomeRendersDynamicBackendSectionsWithoutHardcodedCategories() async {
        let api = MarketplaceFakeAPI(); let cache = CloudKnowledgeAuthorizationCache(); let store = CloudKnowledgeMarketplaceStore(api: api, cache: cache)
        await store.loadHome()
        #expect(store.home.categories.map(\.name) == ["AI Agent", "经济学"])
        #expect(store.home.banners.map(\.title) == ["本周精选"])
        #expect(store.home.sections.map(\.layout) == ["hero", "grid"])
        #expect(store.searchResults.map(\.id) == ["kb-1"])
        #expect(await api.searchRequests == [.init(query: "", limit: 100)])
        #expect(await cache.isAuthorized("kb-1"))
    }

    @Test func answerPreservesL2L3L4PartitionsAndCachesAuthorizedConsumption() async throws {
        let api = MarketplaceFakeAPI(); let cache = CloudKnowledgeAuthorizationCache(); await cache.authorize("kb-1"); await cache.authorize("kb-2")
        let client = CloudKnowledgeConsumptionClient(api: api, cache: cache)
        let first = try await client.answer(.init(query: "Connor", knowledgeBaseIDs: ["kb-1", "kb-2"]))
        let second = try await client.answer(.init(query: "Connor", knowledgeBaseIDs: ["kb-2", "kb-1"]))
        #expect(first.partitions.map(\.layer) == [.l2, .l3, .l4])
        #expect(second == first)
        #expect(await api.answerCount == 1)
        await cache.revoke("kb-1")
        #expect(await cache.value(key: "kb-1,kb-2|Connor|8000|20") == nil)
    }

    @Test @MainActor func unsubscribeRevokesAuthorizationAndCachedAnswersImmediately() async throws {
        let api = MarketplaceFakeAPI(); let cache = CloudKnowledgeAuthorizationCache(); await cache.authorize("kb-1")
        let client = CloudKnowledgeConsumptionClient(api: api, cache: cache); _ = try await client.answer(.init(query: "Connor", knowledgeBaseIDs: ["kb-1"]))
        let store = CloudKnowledgeMarketplaceStore(api: api, cache: cache); await store.loadDetail(id: "kb-1"); await store.unsubscribe(id: "kb-1")
        #expect(await cache.isAuthorized("kb-1") == false)
        await #expect(throws: (any Error).self) { try await client.answer(.init(query: "Connor", knowledgeBaseIDs: ["kb-1"])) }
        #expect(await api.unsubscribeCount == 1)
    }

    @Test @MainActor func clearingSessionRemovesMarketplaceStateAuthorizationAndAnswers() async throws {
        let api = MarketplaceFakeAPI(); let cache = CloudKnowledgeAuthorizationCache(); let store = CloudKnowledgeMarketplaceStore(api: api, cache: cache)
        await store.loadHome(); await store.loadDetail(id: "kb-1")
        let client = CloudKnowledgeConsumptionClient(api: api, cache: cache); _ = try await client.answer(.init(query: "Connor", knowledgeBaseIDs: ["kb-1"]))
        await store.clearSession()
        #expect(store.home.sections.isEmpty && store.selected == nil && store.searchResults.isEmpty)
        #expect(await cache.isAuthorized("kb-1") == false)
        await #expect(throws: (any Error).self) { try await client.answer(.init(query: "Connor", knowledgeBaseIDs: ["kb-1"])) }
    }

    @Test func contextToolsInjectTheSessionKnowledgeScopeAndKeepLayersSeparate() async throws {
        let api = MarketplaceFakeAPI()
        let cache = CloudKnowledgeAuthorizationCache()
        await cache.authorize("kb-1")
        await cache.authorize("kb-2")
        let recentTool = CloudKnowledgeRecentContextTool(
            client: CloudKnowledgeConsumptionClient(api: api, cache: cache),
            knowledgeBaseIDs: ["kb-1"]
        )
        let knowledgeTool = CloudKnowledgeKnowledgeContextTool(
            client: CloudKnowledgeConsumptionClient(api: api, cache: cache),
            knowledgeBaseIDs: ["kb-1"]
        )
        let arguments = try AgentToolArguments(json: #"{"query":"Connor","context_budget":8000,"limit":20}"#)
        let context = AgentToolExecutionContext(
            runID: "run",
            sessionID: "session",
            groupID: "group",
            userPrompt: "query",
            toolCallID: "tool",
            policyEngine: AgentPolicyEngine(permissionMode: .allowAll)
        )

        let recent = try await recentTool.execute(arguments: arguments, context: context)
        let knowledge = try await knowledgeTool.execute(arguments: arguments, context: context)
        #expect(recent.contentText.contains("## L2"))
        #expect(!recent.contentText.contains("## L3"))
        #expect(knowledge.contentText.contains("## L3"))
        #expect(knowledge.contentText.contains("## L4"))
        #expect(!knowledge.contentText.contains("## L2"))
        #expect(await api.contextRequests.map(\.knowledgeBaseIDs) == [["kb-1"], ["kb-1"]])
        #expect(await api.contextChannels == [.recentContext, .knowledgeContext])

        let emptyTool = CloudKnowledgeRecentContextTool(
            client: CloudKnowledgeConsumptionClient(api: api, cache: cache),
            knowledgeBaseIDs: []
        )
        let empty = try await emptyTool.execute(arguments: arguments, context: context)
        #expect(empty.contentText.contains("No remote knowledge bases are selected"))
        #expect(empty.contentText.contains("Do not use remote knowledge context from earlier user runs"))
        #expect(await api.contextRequests.count == 2)
    }

    @Test func runtimeAlwaysRegistersRemoteKnowledgeToolsAndReflectsCurrentSessionScope() throws {
        let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("cloud-consumption-runtime-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        let store = try SQLiteGraphKernelStore(path: databaseURL.path)
        try store.migrate()
        let api = MarketplaceFakeAPI()
        let cache = CloudKnowledgeAuthorizationCache()
        let factory = AppGraphAgentRuntimeFactory(
            store: store,
            settingsRepository: AppLLMSettingsRepository(),
            cloudKnowledgeConsumptionClient: CloudKnowledgeConsumptionClient(api: api, cache: cache)
        )

        let enabled = factory.makeAgentLoopController(remoteKnowledgeBaseIDs: ["kb-1"])
        let disabled = factory.makeAgentLoopController(remoteKnowledgeBaseIDs: [])
        let enabledNames = enabled.toolRegistry.definitions.map(\.name)
        let disabledNames = disabled.toolRegistry.definitions.map(\.name)
        #expect(enabledNames.contains("cloud_kb_recent_context"))
        #expect(enabledNames.contains("cloud_kb_knowledge_context"))
        #expect(!enabledNames.contains("cloud_kb_answer"))
        #expect(disabledNames.contains("cloud_kb_recent_context"))
        #expect(disabledNames.contains("cloud_kb_knowledge_context"))
        #expect(disabled.toolRegistry.definition(named: "cloud_kb_recent_context")?.description.contains("No remote knowledge bases are selected") == true)
    }
}

private actor MarketplaceFakeAPI: CloudKnowledgeMarketplaceAPI {
    var answerCount = 0; var unsubscribeCount = 0
    var searchRequests: [CloudMarketplaceSearchRequest] = []
    var contextRequests: [CloudKnowledgeAnswerRequest] = []
    var contextChannels: [CloudKnowledgeSearchChannel] = []
    func home() async throws -> CloudMarketplaceHome { .init(categories: [.init(id: "agent", name: "AI Agent", parentID: nil, icon: nil), .init(id: "economics", name: "经济学", parentID: nil, icon: nil)], banners: [.init(id: "b", title: "本周精选", subtitle: nil, imageURL: nil, actionURL: nil)], sections: [.init(id: "hero", title: "精选", layout: "hero", knowledgeBases: [base]), .init(id: "new", title: "最新", layout: "grid", knowledgeBases: [])]) }
    func categories() async throws -> [CloudMarketplaceCategory] { try await home().categories }
    func search(_ request: CloudMarketplaceSearchRequest) async throws -> [CloudMarketplaceKnowledgeBase] { searchRequests.append(request); return [base] }
    func detail(id: String) async throws -> CloudMarketplaceKnowledgeBase { base }
    func subscribe(id: String) async throws {}
    func unsubscribe(id: String) async throws { unsubscribeCount += 1 }
    func answer(_ request: CloudKnowledgeAnswerRequest) async throws -> CloudKnowledgeAnswerResponse { answerCount += 1; return .init(requestID: "request", partitions: [.init(layer: .l2, results: [.init(identityID: "l2", layer: .l2, kind: "operational_fact", text: "current")]), .init(layer: .l3, results: [.init(identityID: "l3", layer: .l3, kind: "reusable_knowledge", text: "knowledge")]), .init(layer: .l4, results: [.init(identityID: "l4", layer: .l4, kind: "entity", text: "entity")])], returnedBytes: 30, knowledgeSequence: 4) }
    func context(_ request: CloudKnowledgeAnswerRequest, channel: CloudKnowledgeSearchChannel) async throws -> CloudKnowledgeAnswerResponse {
        contextRequests.append(request)
        contextChannels.append(channel)
        return try await answer(request)
    }
    private var base: CloudMarketplaceKnowledgeBase { .init(id: "kb-1", name: "Connor", description: "Agent OS", categoryID: "agent", subscriberCount: 10, subscribed: true, publicationStatus: "published") }
}
