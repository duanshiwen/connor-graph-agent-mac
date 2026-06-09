import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphSearch
@testable import ConnorGraphStore

@Test func sqliteStoreUpsertsAndCountsGraphMentions() throws {
    let store = try SQLiteGraphStore(path: temporaryEpisodeMentionsDatabaseURL().path)
    try store.migrate()

    let episodeA = GraphEpisode(id: "episode-mentions-a", groupID: "default", sourceType: .chatMessage, name: "A", content: "A", sourceDescription: "chat")
    let episodeB = GraphEpisode(id: "episode-mentions-b", groupID: "default", sourceType: .chatMessage, name: "B", content: "B", sourceDescription: "chat")
    let node = GraphNodeV2(id: "node-mentioned-store", groupID: "default", type: .entity, canonicalName: "mentioned", title: "Mentioned")

    try store.upsert(episode: episodeA)
    try store.upsert(episode: episodeB)
    try store.upsert(nodeV2: node)
    try store.upsertMention(episodeID: episodeA.id, nodeID: node.id, groupID: "default")
    try store.upsertMention(episodeID: episodeB.id, nodeID: node.id, groupID: "default")

    #expect(try store.mentionCounts(groupID: "default", episodeIDs: [episodeA.id]) == [node.id: 1])
    #expect(try store.mentionCounts(groupID: "default", episodeIDs: [episodeA.id, episodeB.id]) == [node.id: 2])
    #expect(try store.episodeIDsMentioning(nodeIDs: [node.id], groupID: "default", limit: 10) == [episodeA.id, episodeB.id])
}

@Test func sqliteHybridSearchBoostsNodesMentionedInSelectedEpisodes() async throws {
    let store = try SQLiteGraphStore(path: temporaryEpisodeMentionsDatabaseURL().path)
    try store.migrate()

    let episode = GraphEpisode(id: "episode-node-mentioned", groupID: "default", sourceType: .chatMessage, name: "Selected", content: "Selected", sourceDescription: "chat")
    let mentioned = GraphNodeV2(id: "node-mentioned-rerank", groupID: "default", type: .entity, canonicalName: "mentioned", title: "Mentioned", summary: "Graphiti memory topic")
    let unmentioned = GraphNodeV2(id: "node-unmentioned-rerank", groupID: "default", type: .entity, canonicalName: "unmentioned", title: "Unmentioned", summary: "Graphiti memory topic")

    try store.upsert(episode: episode)
    try store.upsert(nodeV2: unmentioned)
    try store.upsert(nodeV2: mentioned)
    try store.upsertMention(episodeID: episode.id, nodeID: mentioned.id, groupID: "default")
    try store.processPendingFTSIndexTasks(limit: 20)

    let service = SQLiteGraphHybridSearchService(store: store)
    let response = try await service.search(query: GraphSearchQuery(
        text: "Graphiti memory topic",
        groupID: "default",
        includeNodes: true,
        includeFacts: false,
        includeEpisodes: false,
        limit: 2,
        reranking: GraphRerankingConfig(
            strategies: [.graphitiLocal, .episodeMentions],
            episodeMentionEpisodeIDs: [episode.id]
        )
    ))

    #expect(response.hits.first?.ownerID == mentioned.id)
    let hit = try #require(response.hits.first)
    #expect(hit.metadata["episode_mentions_count"] == "1")
    #expect(hit.metadata["episode_mentions_scope"] == "selected_episodes")
    #expect(hit.metadata["episode_mentions_boost"] == "0.002500")
    #expect(hit.metadata["episode_mentions_status"] == "applied")
    #expect(hit.metadata["graph_ranking_signals"]?.contains("episode_mentions") == true)
    #expect(hit.metadata["graph_reranking_strategies"] == "graphiti_local,episode_mentions")
}

@Test func sqliteHybridSearchBoostsFactsWhoseEndpointsAreMentioned() async throws {
    let store = try SQLiteGraphStore(path: temporaryEpisodeMentionsDatabaseURL().path)
    try store.migrate()

    let episode = GraphEpisode(id: "episode-fact-mentioned", groupID: "default", sourceType: .chatMessage, name: "Selected", content: "Selected", sourceDescription: "chat")
    let shiwen = GraphNodeV2(id: "node-shiwen-fact-mentioned", groupID: "default", type: .person, canonicalName: "shiwen", title: "诗闻")
    let mentionedTarget = GraphNodeV2(id: "node-mentioned-fact", groupID: "default", type: .entity, canonicalName: "mentioned", title: "Mentioned")
    let unmentionedTarget = GraphNodeV2(id: "node-unmentioned-fact", groupID: "default", type: .entity, canonicalName: "unmentioned", title: "Unmentioned")
    let mentionedFact = GraphFact(id: "fact-mentioned-endpoint", groupID: "default", sourceNodeID: shiwen.id, targetNodeID: mentionedTarget.id, relation: .mentions, fact: "Graphiti memory endpoint topic.")
    let unmentionedFact = GraphFact(id: "fact-unmentioned-endpoint", groupID: "default", sourceNodeID: shiwen.id, targetNodeID: unmentionedTarget.id, relation: .mentions, fact: "Graphiti memory endpoint topic.")

    try store.upsert(episode: episode)
    try store.upsert(nodeV2: shiwen)
    try store.upsert(nodeV2: mentionedTarget)
    try store.upsert(nodeV2: unmentionedTarget)
    try store.upsert(fact: unmentionedFact, sourceEpisodeIDs: [episode.id])
    try store.upsert(fact: mentionedFact, sourceEpisodeIDs: [episode.id])
    try store.upsertMention(episodeID: episode.id, nodeID: mentionedTarget.id, groupID: "default")
    try store.processPendingFTSIndexTasks(limit: 20)

    let service = SQLiteGraphHybridSearchService(store: store)
    let response = try await service.search(query: GraphSearchQuery(
        text: "Graphiti memory endpoint topic",
        groupID: "default",
        includeNodes: false,
        includeFacts: true,
        includeEpisodes: false,
        limit: 2,
        reranking: GraphRerankingConfig(
            strategies: [.graphitiLocal, .episodeMentions],
            episodeMentionEpisodeIDs: [episode.id]
        )
    ))

    #expect(response.hits.first?.ownerID == mentionedFact.id)
    let hit = try #require(response.hits.first)
    #expect(hit.metadata["episode_mentions_count"] == "1")
    #expect(hit.metadata["episode_mentions_boost"] == "0.002500")
    #expect(hit.metadata["episode_mentions_status"] == "applied")
    #expect(hit.metadata["graph_ranking_signals"]?.contains("episode_mentions") == true)
}

@Test func sqliteHybridSearchMarksEpisodeMentionsWithoutMatchesAsSkipped() async throws {
    let store = try SQLiteGraphStore(path: temporaryEpisodeMentionsDatabaseURL().path)
    try store.migrate()

    let episode = GraphEpisode(id: "episode-no-mentions", groupID: "default", sourceType: .chatMessage, name: "No mentions", content: "No mentions", sourceDescription: "chat")
    let unmentioned = GraphNodeV2(id: "node-no-mention", groupID: "default", type: .entity, canonicalName: "unmentioned", title: "Unmentioned", summary: "Graphiti memory topic")

    try store.upsert(episode: episode)
    try store.upsert(nodeV2: unmentioned)
    try store.processPendingFTSIndexTasks(limit: 20)

    let service = SQLiteGraphHybridSearchService(store: store)
    let response = try await service.search(query: GraphSearchQuery(
        text: "Graphiti memory topic",
        groupID: "default",
        includeNodes: true,
        includeFacts: false,
        includeEpisodes: false,
        limit: 1,
        reranking: GraphRerankingConfig(
            strategies: [.graphitiLocal, .episodeMentions],
            episodeMentionEpisodeIDs: [episode.id]
        )
    ))

    let hit = try #require(response.hits.first)
    #expect(hit.metadata["episode_mentions_count"] == "0")
    #expect(hit.metadata["episode_mentions_scope"] == "selected_episodes")
    #expect(hit.metadata["episode_mentions_boost"] == "0.000000")
    #expect(hit.metadata["episode_mentions_status"] == "skipped")
    #expect(hit.metadata["episode_mentions_skip_reason"] == "no_mentions")
}

private func temporaryEpisodeMentionsDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("connor-graph-episode-mentions-\(UUID().uuidString)")
        .appendingPathExtension("sqlite")
}
