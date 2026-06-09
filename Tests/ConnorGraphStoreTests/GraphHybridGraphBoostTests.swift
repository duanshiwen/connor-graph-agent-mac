import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphSearch
@testable import ConnorGraphStore

@Test func sqliteHybridSearchAppliesGraphBoostWhenFactEndpointMatchesQuery() async throws {
    let store = try SQLiteGraphStore(path: temporaryGraphBoostDatabaseURL().path)
    try store.migrate()

    let episode = GraphEpisode(id: "episode-graph-boost", groupID: "default", sourceType: .chatMessage, name: "Graph boost episode", content: "memory", sourceDescription: "chat")
    let shiwen = GraphNodeV2(id: "node-shiwen-boost", groupID: "default", type: .person, canonicalName: "shiwen", title: "诗闻")
    let agentOS = GraphNodeV2(id: "node-agent-boost", groupID: "default", type: .workObject, canonicalName: "agent-os", title: "Agent OS")
    let unrelated = GraphNodeV2(id: "node-unrelated-boost", groupID: "default", type: .entity, canonicalName: "unrelated", title: "Unrelated")
    let endpointMatchedFact = GraphFact(id: "fact-endpoint-boost", groupID: "default", sourceNodeID: shiwen.id, targetNodeID: agentOS.id, relation: .worksOn, fact: "诗闻正在设计长期记忆系统。")
    let unrelatedFact = GraphFact(id: "fact-unrelated-boost", groupID: "default", sourceNodeID: shiwen.id, targetNodeID: unrelated.id, relation: .mentions, fact: "诗闻提到长期记忆系统。")

    try store.upsert(episode: episode)
    try store.upsert(nodeV2: shiwen)
    try store.upsert(nodeV2: agentOS)
    try store.upsert(nodeV2: unrelated)
    try store.upsert(fact: unrelatedFact, sourceEpisodeIDs: [episode.id])
    try store.upsert(fact: endpointMatchedFact, sourceEpisodeIDs: [episode.id])
    try store.processPendingFTSIndexTasks(limit: 20)

    let service = SQLiteGraphHybridSearchService(store: store)
    let response = try await service.search(query: GraphSearchQuery(
        text: "Agent OS 长期记忆",
        groupID: "default",
        includeNodes: false,
        includeFacts: true,
        includeEpisodes: false,
        limit: 2
    ))

    let boostedHit = try #require(response.hits.first { $0.ownerID == endpointMatchedFact.id })
    #expect(boostedHit.metadata["graph_ranking"] == "boosted")
    #expect(boostedHit.metadata["graph_boost"] == "0.002000")
    #expect(boostedHit.metadata["graph_boost_reason"] == "endpoint_title_query_match")
    #expect(boostedHit.metadata["graph_ranking_signals"] == "endpoint_title_query_match")
    #expect(boostedHit.metadata["base_rrf_score"] != nil)
    #expect(boostedHit.metadata["final_score"] != nil)
    #expect((Double(boostedHit.metadata["final_score"] ?? "0") ?? 0) > (Double(boostedHit.metadata["base_rrf_score"] ?? "0") ?? 0))
}

@Test func sqliteHybridSearchLeavesGraphBoostAtZeroWhenNoGraphContextMatchesQuery() async throws {
    let store = try SQLiteGraphStore(path: temporaryGraphBoostDatabaseURL().path)
    try store.migrate()

    let episode = GraphEpisode(id: "episode-no-boost", groupID: "default", sourceType: .chatMessage, name: "No boost episode", content: "memory", sourceDescription: "chat")
    let shiwen = GraphNodeV2(id: "node-shiwen-no-boost", groupID: "default", type: .person, canonicalName: "shiwen", title: "诗闻")
    let unrelated = GraphNodeV2(id: "node-unrelated-no-boost", groupID: "default", type: .entity, canonicalName: "unrelated", title: "Unrelated")
    let fact = GraphFact(id: "fact-no-boost", groupID: "default", sourceNodeID: shiwen.id, targetNodeID: unrelated.id, relation: .mentions, fact: "诗闻提到长期记忆系统。")

    try store.upsert(episode: episode)
    try store.upsert(nodeV2: shiwen)
    try store.upsert(nodeV2: unrelated)
    try store.upsert(fact: fact, sourceEpisodeIDs: [episode.id])
    try store.processPendingFTSIndexTasks(limit: 20)

    let service = SQLiteGraphHybridSearchService(store: store)
    let response = try await service.search(query: GraphSearchQuery(
        text: "Graphiti 长期记忆",
        groupID: "default",
        includeNodes: false,
        includeFacts: true,
        includeEpisodes: false,
        limit: 1
    ))

    let hit = try #require(response.hits.first)
    #expect(hit.ownerID == fact.id)
    #expect(hit.metadata["graph_ranking"] == "rrf_only")
    #expect(hit.metadata["graph_boost"] == "0.000000")
    #expect(hit.metadata["graph_boost_reason"] == nil)
    #expect(hit.metadata["graph_ranking_signals"] == nil)
    #expect(hit.metadata["base_rrf_score"] == hit.metadata["final_score"])
}

@Test func sqliteHybridSearchAppliesAdjacentRelationGraphSignalForNodeHits() async throws {
    let store = try SQLiteGraphStore(path: temporaryGraphBoostDatabaseURL().path)
    try store.migrate()

    let episode = GraphEpisode(id: "episode-adjacent-relation-boost", groupID: "default", sourceType: .chatMessage, name: "Adjacent relation boost episode", content: "memory", sourceDescription: "chat")
    let shiwen = GraphNodeV2(id: "node-shiwen-adjacent-boost", groupID: "default", type: .person, canonicalName: "shiwen", title: "诗闻")
    let agentOS = GraphNodeV2(id: "node-agent-adjacent-boost", groupID: "default", type: .workObject, canonicalName: "agent-os", title: "Agent OS", summary: "Agent OS WORKS_ON 本地优先 Agent 操作系统。")
    let worksOnFact = GraphFact(id: "fact-adjacent-works-on-boost", groupID: "default", sourceNodeID: shiwen.id, targetNodeID: agentOS.id, relation: .worksOn, fact: "诗闻正在设计 Agent OS。")

    try store.upsert(episode: episode)
    try store.upsert(nodeV2: shiwen)
    try store.upsert(nodeV2: agentOS)
    try store.upsert(fact: worksOnFact, sourceEpisodeIDs: [episode.id])
    try store.processPendingFTSIndexTasks(limit: 20)

    let service = SQLiteGraphHybridSearchService(store: store)
    let response = try await service.search(query: GraphSearchQuery(
        text: "Agent OS WORKS_ON",
        groupID: "default",
        includeNodes: true,
        includeFacts: false,
        includeEpisodes: false,
        limit: 1
    ))

    let hit = try #require(response.hits.first)
    #expect(hit.ownerID == agentOS.id)
    #expect(hit.metadata["graph_context"] == "adjacent_facts")
    #expect(hit.metadata["adjacent_fact_relations"] == "WORKS_ON")
    #expect(hit.metadata["graph_ranking"] == "boosted")
    #expect(hit.metadata["graph_boost"] == "0.001000")
    #expect(hit.metadata["graph_boost_reason"] == "adjacent_relation_query_match")
    #expect(hit.metadata["graph_ranking_signals"] == "adjacent_relation_query_match")
    #expect(hit.metadata["base_rrf_score"] != nil)
    #expect(hit.metadata["final_score"] != nil)
    #expect((Double(hit.metadata["final_score"] ?? "0") ?? 0) > (Double(hit.metadata["base_rrf_score"] ?? "0") ?? 0))
}

@Test func sqliteHybridSearchAppliesCenterNodeDistanceSignalForFactHits() async throws {
    let store = try SQLiteGraphStore(path: temporaryGraphBoostDatabaseURL().path)
    try store.migrate()

    let episode = GraphEpisode(id: "episode-center-distance", groupID: "default", sourceType: .chatMessage, name: "Center distance episode", content: "memory", sourceDescription: "chat")
    let shiwen = GraphNodeV2(id: "node-shiwen-center-distance", groupID: "default", type: .person, canonicalName: "shiwen", title: "诗闻")
    let agentOS = GraphNodeV2(id: "node-agent-center-distance", groupID: "default", type: .workObject, canonicalName: "agent-os", title: "Agent OS")
    let unrelated = GraphNodeV2(id: "node-unrelated-center-distance", groupID: "default", type: .entity, canonicalName: "unrelated", title: "Unrelated")
    let connectedFact = GraphFact(id: "fact-center-distance-connected", groupID: "default", sourceNodeID: shiwen.id, targetNodeID: agentOS.id, relation: .worksOn, fact: "诗闻正在设计长期记忆系统。")
    let unrelatedFact = GraphFact(id: "fact-center-distance-unrelated", groupID: "default", sourceNodeID: shiwen.id, targetNodeID: unrelated.id, relation: .mentions, fact: "诗闻提到长期记忆系统。")

    try store.upsert(episode: episode)
    try store.upsert(nodeV2: shiwen)
    try store.upsert(nodeV2: agentOS)
    try store.upsert(nodeV2: unrelated)
    try store.upsert(fact: unrelatedFact, sourceEpisodeIDs: [episode.id])
    try store.upsert(fact: connectedFact, sourceEpisodeIDs: [episode.id])
    try store.processPendingFTSIndexTasks(limit: 20)

    let service = SQLiteGraphHybridSearchService(store: store)
    let response = try await service.search(query: GraphSearchQuery(
        text: "长期记忆",
        groupID: "default",
        includeNodes: false,
        includeFacts: true,
        includeEpisodes: false,
        limit: 2,
        centerNodeIDs: [agentOS.id]
    ))

    #expect(response.hits.first?.ownerID == connectedFact.id)
    let hit = try #require(response.hits.first { $0.ownerID == connectedFact.id })
    #expect(hit.metadata["graph_reranker"] == "graphiti_local")
    #expect(hit.metadata["graph_ranking"] == "boosted")
    #expect(hit.metadata["graph_boost"] == "0.003000")
    #expect(hit.metadata["graph_boost_reason"] == "center_node_1_hop_match")
    #expect(hit.metadata["graph_ranking_signals"] == "center_node_1_hop_match")
    #expect(hit.metadata["graph_ranking_signal_scores"] == "center_node_1_hop_match:0.003000")
    #expect(hit.metadata["base_rrf_score"] != nil)
    #expect(hit.metadata["final_score"] != nil)
    #expect((Double(hit.metadata["final_score"] ?? "0") ?? 0) > (Double(hit.metadata["base_rrf_score"] ?? "0") ?? 0))
}

@Test func sqliteHybridSearchAppliesCenterNodeExactSignalForNodeHits() async throws {
    let store = try SQLiteGraphStore(path: temporaryGraphBoostDatabaseURL().path)
    try store.migrate()

    let agentOS = GraphNodeV2(id: "node-agent-center-exact", groupID: "default", type: .workObject, canonicalName: "agent-os", title: "Agent OS", summary: "Graphiti local reranker search system")
    let unrelated = GraphNodeV2(id: "node-unrelated-center-exact", groupID: "default", type: .entity, canonicalName: "unrelated", title: "Unrelated", summary: "Graphiti local reranker search system")

    try store.upsert(nodeV2: unrelated)
    try store.upsert(nodeV2: agentOS)
    try store.processPendingFTSIndexTasks(limit: 20)

    let service = SQLiteGraphHybridSearchService(store: store)
    let response = try await service.search(query: GraphSearchQuery(
        text: "Graphiti local reranker",
        groupID: "default",
        includeNodes: true,
        includeFacts: false,
        includeEpisodes: false,
        limit: 2,
        centerNodeIDs: [agentOS.id]
    ))

    #expect(response.hits.first?.ownerID == agentOS.id)
    let hit = try #require(response.hits.first { $0.ownerID == agentOS.id })
    #expect(hit.metadata["graph_reranker"] == "graphiti_local")
    #expect(hit.metadata["graph_ranking"] == "boosted")
    #expect(hit.metadata["graph_boost"] == "0.004000")
    #expect(hit.metadata["graph_boost_reason"] == "center_node_exact_match")
    #expect(hit.metadata["graph_ranking_signals"] == "center_node_exact_match")
    #expect(hit.metadata["graph_ranking_signal_scores"] == "center_node_exact_match:0.004000")
}

private func temporaryGraphBoostDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("connor-graph-boost-\(UUID().uuidString)")
        .appendingPathExtension("sqlite")
}
