import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphSearch
@testable import ConnorGraphStore

@Test func sqliteHybridSearchFactHitIncludesEndpointNodeContextMetadata() async throws {
    let store = try SQLiteGraphStore(path: temporaryGraphContextDatabaseURL().path)
    try store.migrate()

    let episode = GraphEpisode(id: "episode-graph-context", groupID: "default", sourceType: .chatMessage, name: "Graph context episode", content: "诗闻在设计 Agent OS。", sourceDescription: "chat")
    let source = GraphNodeV2(id: "node-shiwen-context", groupID: "default", type: .person, canonicalName: "shiwen", title: "诗闻", summary: "系统设计者")
    let target = GraphNodeV2(id: "node-agent-context", groupID: "default", type: .workObject, canonicalName: "agent-os", title: "Agent OS", summary: "本地优先 Agent 操作系统")
    let fact = GraphFact(id: "fact-graph-context", groupID: "default", sourceNodeID: source.id, targetNodeID: target.id, relation: .worksOn, fact: "诗闻正在设计 Agent OS 的图谱记忆。")

    try store.upsert(episode: episode)
    try store.upsert(nodeV2: source)
    try store.upsert(nodeV2: target)
    try store.upsert(fact: fact, sourceEpisodeIDs: [episode.id])
    try store.processPendingFTSIndexTasks(limit: 20)

    let service = SQLiteGraphHybridSearchService(store: store)
    let response = try await service.search(query: GraphSearchQuery(
        text: "图谱记忆",
        groupID: "default",
        includeNodes: false,
        includeFacts: true,
        includeEpisodes: false,
        limit: 1
    ))

    let hit = try #require(response.hits.first)
    #expect(hit.ownerID == fact.id)
    #expect(hit.metadata["graph_context"] == "fact_endpoints")
    #expect(hit.metadata["source_node_title"] == "诗闻")
    #expect(hit.metadata["source_node_type"] == NodeType.person.rawValue)
    #expect(hit.metadata["target_node_title"] == "Agent OS")
    #expect(hit.metadata["target_node_type"] == NodeType.workObject.rawValue)
    #expect(hit.metadata["graph_context_node_ids"] == "node-shiwen-context,node-agent-context")
}

@Test func sqliteHybridSearchNodeHitIncludesAdjacentFactContextMetadata() async throws {
    let store = try SQLiteGraphStore(path: temporaryGraphContextDatabaseURL().path)
    try store.migrate()

    let episode = GraphEpisode(id: "episode-node-context", groupID: "default", sourceType: .chatMessage, name: "Node context episode", content: "Agent OS node context", sourceDescription: "chat")
    let shiwen = GraphNodeV2(id: "node-shiwen-adjacent", groupID: "default", type: .person, canonicalName: "shiwen", title: "诗闻", summary: "设计者")
    let agentOS = GraphNodeV2(id: "node-agent-adjacent", groupID: "default", type: .workObject, canonicalName: "agent-os", title: "Agent OS", summary: "图谱检索系统")
    let graphiti = GraphNodeV2(id: "node-graphiti-adjacent", groupID: "default", type: .entity, canonicalName: "graphiti", title: "Graphiti", summary: "时间感知知识图谱")
    let worksOn = GraphFact(id: "fact-node-context-works-on", groupID: "default", sourceNodeID: shiwen.id, targetNodeID: agentOS.id, relation: .worksOn, fact: "诗闻正在设计 Agent OS。")
    let mentions = GraphFact(id: "fact-node-context-mentions", groupID: "default", sourceNodeID: agentOS.id, targetNodeID: graphiti.id, relation: .mentions, fact: "Agent OS 借鉴 Graphiti 的时间感知图谱思想。")

    try store.upsert(episode: episode)
    try store.upsert(nodeV2: shiwen)
    try store.upsert(nodeV2: agentOS)
    try store.upsert(nodeV2: graphiti)
    try store.upsert(fact: worksOn, sourceEpisodeIDs: [episode.id])
    try store.upsert(fact: mentions, sourceEpisodeIDs: [episode.id])
    try store.processPendingFTSIndexTasks(limit: 20)

    let service = SQLiteGraphHybridSearchService(store: store)
    let response = try await service.search(query: GraphSearchQuery(
        text: "图谱检索系统",
        groupID: "default",
        includeNodes: true,
        includeFacts: false,
        includeEpisodes: false,
        limit: 1
    ))

    let hit = try #require(response.hits.first)
    #expect(hit.ownerID == agentOS.id)
    #expect(hit.metadata["graph_context"] == "adjacent_facts")
    #expect(hit.metadata["adjacent_fact_ids"] == "fact-node-context-mentions,fact-node-context-works-on")
    #expect(hit.metadata["adjacent_fact_relations"] == "MENTIONS,WORKS_ON")
    #expect(hit.metadata["adjacent_node_ids"] == "node-graphiti-adjacent,node-shiwen-adjacent")
}

private func temporaryGraphContextDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("connor-graph-context-\(UUID().uuidString)")
        .appendingPathExtension("sqlite")
}
