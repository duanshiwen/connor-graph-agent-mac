import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphSearch
import ConnorGraphStore

private func temporaryHybridSearchDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

private func seededHybridSearchStore() throws -> SQLiteGraphStore {
    let store = try SQLiteGraphStore(path: temporaryHybridSearchDatabaseURL().path)
    try store.migrate()

    let episode = GraphEpisode(
        id: "episode-agent-os",
        groupID: "default",
        sourceType: .chatMessage,
        name: "Agent OS design note",
        content: "诗闻正在设计可靠的 Agent OS 图谱存储层。",
        sourceDescription: "chat",
        occurredAt: Date(timeIntervalSince1970: 1_000),
        ingestedAt: Date(timeIntervalSince1970: 1_001)
    )
    let source = GraphNodeV2(
        id: "node-shiwen",
        groupID: "default",
        type: .person,
        canonicalName: "诗闻",
        title: "诗闻",
        summary: "Agent OS 的设计者。"
    )
    let target = GraphNodeV2(
        id: "node-agent-os",
        groupID: "default",
        type: .workObject,
        canonicalName: "Agent OS",
        title: "Agent OS",
        summary: "可靠的本地优先图谱 Agent 系统。"
    )
    let fact = GraphFact(
        id: "fact-agent-os-storage",
        groupID: "default",
        sourceNodeID: source.id,
        targetNodeID: target.id,
        relation: .worksOn,
        fact: "诗闻正在设计 Agent OS 的 Graphiti-grade 本地图谱存储层。",
        confidence: 0.95,
        status: .active,
        validAt: Date(timeIntervalSince1970: 900),
        referenceTime: Date(timeIntervalSince1970: 1_000)
    )

    try store.upsert(episode: episode)
    try store.upsert(nodeV2: source)
    try store.upsert(nodeV2: target)
    try store.upsert(fact: fact, sourceEpisodeIDs: [episode.id])
    try store.processPendingFTSIndexTasks(limit: 20)
    return store
}

@Test func sqliteHybridSearchReturnsFactHitsFromFTS() async throws {
    let store = try seededHybridSearchStore()
    let service = SQLiteGraphHybridSearchService(store: store)

    let response = try await service.search(query: GraphSearchQuery(text: "Graphiti", groupID: "default", includeNodes: false, includeFacts: true, includeEpisodes: false))

    #expect(response.hits.map(\.ownerID) == ["fact-agent-os-storage"])
    #expect(response.hits.first?.ownerType == .fact)
    #expect(response.hits.first?.sourceEpisodeIDs == ["episode-agent-os"])
}

@Test func sqliteHybridSearchReturnsNodeAndEpisodeHits() async throws {
    let store = try seededHybridSearchStore()
    let service = SQLiteGraphHybridSearchService(store: store)

    let response = try await service.search(query: GraphSearchQuery(text: "可靠", groupID: "default", includeNodes: true, includeFacts: false, includeEpisodes: true))

    #expect(response.hits.contains { $0.ownerID == "node-agent-os" && $0.ownerType == .node })
    #expect(response.hits.contains { $0.ownerID == "episode-agent-os" && $0.ownerType == .episode })
}

@Test func sqliteHybridSearchAppliesGroupFilter() async throws {
    let store = try seededHybridSearchStore()
    try store.upsert(nodeV2: GraphNodeV2(id: "node-other", groupID: "other", type: .workObject, canonicalName: "Agent OS", title: "Agent OS", summary: "Graphiti-grade other group"))
    try store.processPendingFTSIndexTasks(limit: 20)
    let service = SQLiteGraphHybridSearchService(store: store)

    let response = try await service.search(query: GraphSearchQuery(text: "Graphiti", groupID: "default"))

    #expect(!response.hits.contains { $0.ownerID == "node-other" })
    #expect(response.hits.allSatisfy { $0.metadata["group_id"] == "default" })
}

@Test func sqliteHybridSearchFiltersInvalidFactsAtReferenceTime() async throws {
    let store = try seededHybridSearchStore()
    let invalidFact = GraphFact(
        id: "fact-invalid",
        groupID: "default",
        sourceNodeID: "node-shiwen",
        targetNodeID: "node-agent-os",
        relation: .worksOn,
        fact: "诗闻曾经使用过 Graphiti 旧方案。",
        status: .active,
        validAt: Date(timeIntervalSince1970: 100),
        invalidAt: Date(timeIntervalSince1970: 200)
    )
    try store.upsert(fact: invalidFact, sourceEpisodeIDs: ["episode-agent-os"])
    try store.processPendingFTSIndexTasks(limit: 20)
    let service = SQLiteGraphHybridSearchService(store: store)

    let response = try await service.search(query: GraphSearchQuery(text: "Graphiti", groupID: "default", referenceTime: Date(timeIntervalSince1970: 1_100), includeNodes: false, includeFacts: true, includeEpisodes: false))

    #expect(!response.hits.contains { $0.ownerID == "fact-invalid" })
    #expect(response.hits.contains { $0.ownerID == "fact-agent-os-storage" })
}
