import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphStore

@Suite("Cloud Knowledge Phase 6 Tests")
struct CloudKnowledgePhase6Tests {
    @Test func canonicalBackendFixturesDecodeAndRequestUsesByteBudget() throws {
        let homeJSON = #"{"categories":[{"id":"c","slug":"agents","localized_names":{"zh-CN":"智能体"}}],"banners":[],"sections":[{"id":"s","slug":"featured","title":{"zh-CN":"精选"},"section_type":"hero","knowledge_bases":[{"id":"kb-1","name":"Connor","category_id":"agents","subscriber_count":10,"subscribed":false,"publication_status":"published"}]}]}"#
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let home = try decoder.decode(CloudMarketplaceHome.self, from: Data(homeJSON.utf8))
        #expect(home.categories.first?.name == "智能体" && home.sections.first?.layout == "hero" && home.sections.first?.knowledgeBases.first?.id == "kb-1")
        let answerJSON = #"{"request_id":"request","l2":[{"document_id":"00000000-0000-0000-0000-000000000001","knowledge_base_id":"kb-1","identity_id":"i2","revision_id":"r2","layer":"L2","kind":"operational_fact","stable_key":"state","text":"current","rank":1,"score":1,"retriever":"exact"}],"l3":[],"l4":[],"returned_bytes":7,"knowledge_base_ids":["kb-1"]}"#
        let answer = try decoder.decode(CloudKnowledgeAnswerResponse.self, from: Data(answerJSON.utf8))
        #expect(answer.requestID == "request" && answer.partitions.first?.results.first?.text == "current")
        let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
        let body = try #require(try JSONSerialization.jsonObject(with: encoder.encode(CloudKnowledgeAnswerRequest(requestID: "request", query: "Connor", knowledgeBaseIDs: ["kb-1"], contextBudget: 9000))) as? [String: Any])
        #expect(body["context_budget_bytes"] as? Int == 9000 && body["request_id"] as? String == "request")
    }
    @Test @MainActor func marketplaceHomeRendersDynamicBackendSectionsWithoutHardcodedCategories() async {
        let api = MarketplaceFakeAPI(); let cache = CloudKnowledgeAuthorizationCache(); let store = CloudKnowledgeMarketplaceStore(api: api, cache: cache)
        await store.loadHome()
        #expect(store.home.categories.map(\.name) == ["AI Agent", "经济学"])
        #expect(store.home.banners.map(\.title) == ["本周精选"])
        #expect(store.home.sections.map(\.layout) == ["hero", "grid"])
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

    @Test func answerToolRejectsKnowledgeBasesOutsideTheSessionSelection() async throws {
        let api = MarketplaceFakeAPI()
        let cache = CloudKnowledgeAuthorizationCache()
        await cache.authorize("kb-1")
        await cache.authorize("kb-2")
        let tool = CloudKnowledgeAnswerTool(
            client: CloudKnowledgeConsumptionClient(api: api, cache: cache),
            allowedKnowledgeBaseIDs: ["kb-1"]
        )
        let arguments = try AgentToolArguments(json: #"{"query":"Connor","knowledge_base_ids":["kb-2"],"context_budget":8000,"limit":20}"#)
        let context = AgentToolExecutionContext(
            runID: "run",
            sessionID: "session",
            groupID: "group",
            userPrompt: "query",
            toolCallID: "tool",
            policyEngine: AgentPolicyEngine(permissionMode: .allowAll)
        )

        await #expect(throws: AgentToolError.self) {
            try await tool.execute(arguments: arguments, context: context)
        }
        #expect(await api.answerCount == 0)
    }

    @Test func runtimeRegistersRemoteKnowledgeToolOnlyForNonemptySessionScope() throws {
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
        #expect(enabled.toolRegistry.definitions.map(\.name).contains("cloud_kb_answer"))
        #expect(!disabled.toolRegistry.definitions.map(\.name).contains("cloud_kb_answer"))
        #expect(enabled.toolRegistry.definition(named: "cloud_kb_answer")?.description.contains("kb-1") == true)
    }
}

private actor MarketplaceFakeAPI: CloudKnowledgeMarketplaceAPI {
    var answerCount = 0; var unsubscribeCount = 0
    func home() async throws -> CloudMarketplaceHome { .init(categories: [.init(id: "agent", name: "AI Agent", parentID: nil, icon: nil), .init(id: "economics", name: "经济学", parentID: nil, icon: nil)], banners: [.init(id: "b", title: "本周精选", subtitle: nil, imageURL: nil, actionURL: nil)], sections: [.init(id: "hero", title: "精选", layout: "hero", knowledgeBases: [base]), .init(id: "new", title: "最新", layout: "grid", knowledgeBases: [])]) }
    func categories() async throws -> [CloudMarketplaceCategory] { try await home().categories }
    func search(_ request: CloudMarketplaceSearchRequest) async throws -> [CloudMarketplaceKnowledgeBase] { [base] }
    func detail(id: String) async throws -> CloudMarketplaceKnowledgeBase { base }
    func subscribe(id: String) async throws {}
    func unsubscribe(id: String) async throws { unsubscribeCount += 1 }
    func answer(_ request: CloudKnowledgeAnswerRequest) async throws -> CloudKnowledgeAnswerResponse { answerCount += 1; return .init(requestID: "request", partitions: [.init(layer: .l2, results: [.init(identityID: "l2", layer: .l2, kind: "operational_fact", text: "current")]), .init(layer: .l3, results: [.init(identityID: "l3", layer: .l3, kind: "reusable_knowledge", text: "knowledge")]), .init(layer: .l4, results: [.init(identityID: "l4", layer: .l4, kind: "entity", text: "entity")])], returnedBytes: 30, knowledgeSequence: 4) }
    private var base: CloudMarketplaceKnowledgeBase { .init(id: "kb-1", name: "Connor", description: "Agent OS", categoryID: "agent", subscriberCount: 10, subscribed: true, publicationStatus: "published") }
}
