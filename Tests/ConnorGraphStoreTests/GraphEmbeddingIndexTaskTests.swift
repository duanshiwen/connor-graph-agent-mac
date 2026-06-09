import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphSearch
@testable import ConnorGraphStore

private struct DeterministicTestEmbeddingProvider: EmbeddingProvider {
    let model = "deterministic-test-v1"
    let dimensions = 3

    func embedding(for text: String) async throws -> [Double] {
        let lowercased = text.lowercased()
        return [
            lowercased.contains("graphiti") ? 1.0 : 0.0,
            lowercased.contains("agent os") ? 1.0 : 0.0,
            Double(text.count % 7) / 7.0
        ]
    }
}

@Test func graphStoreSchedulesEmbeddingIndexTasksForEpisodeNodeAndFactWrites() throws {
    let store = try SQLiteGraphStore(path: temporaryEmbeddingIndexTaskDatabaseURL().path)
    try store.migrate()

    let episode = GraphEpisode(id: "episode-index", groupID: "default", sourceType: .chatMessage, name: "Graphiti episode", content: "诗闻讨论 Graphiti memory。", sourceDescription: "chat")
    let source = GraphNodeV2(id: "node-shiwen-index", groupID: "default", type: .person, canonicalName: "诗闻", title: "诗闻")
    let target = GraphNodeV2(id: "node-agent-index", groupID: "default", type: .workObject, canonicalName: "Agent OS", title: "Agent OS", summary: "Graphiti-grade local graph")
    let fact = GraphFact(id: "fact-index", groupID: "default", sourceNodeID: source.id, targetNodeID: target.id, relation: .worksOn, fact: "诗闻正在设计 Agent OS 的 Graphiti memory 系统。")

    try store.upsert(episode: episode)
    try store.upsert(nodeV2: source)
    try store.upsert(nodeV2: target)
    try store.upsert(fact: fact, sourceEpisodeIDs: [episode.id])

    let embeddingTasks = try store.pendingIndexTasks(limit: 20).filter { $0.taskType == .embeddingUpsert }
    #expect(Set(embeddingTasks.map(\.ownerID)) == [episode.id, source.id, target.id, fact.id])
    #expect(Set(embeddingTasks.map(\.ownerType)) == [.episode, .node, .fact])
}

@Test func graphStoreProcessesPendingEmbeddingIndexTasksWithProvider() async throws {
    let store = try SQLiteGraphStore(path: temporaryEmbeddingIndexTaskDatabaseURL().path)
    try store.migrate()

    let episode = GraphEpisode(id: "episode-embed", groupID: "default", sourceType: .chatMessage, name: "Graphiti episode", content: "Graphiti memory context", sourceDescription: "chat")
    let source = GraphNodeV2(id: "node-shiwen-embed", groupID: "default", type: .person, canonicalName: "诗闻", title: "诗闻")
    let target = GraphNodeV2(id: "node-agent-embed", groupID: "default", type: .workObject, canonicalName: "Agent OS", title: "Agent OS")
    let fact = GraphFact(id: "fact-embed", groupID: "default", sourceNodeID: source.id, targetNodeID: target.id, relation: .worksOn, fact: "诗闻正在设计 Agent OS 的 Graphiti memory 系统。")

    try store.upsert(episode: episode)
    try store.upsert(nodeV2: source)
    try store.upsert(nodeV2: target)
    try store.upsert(fact: fact, sourceEpisodeIDs: [episode.id])

    let processed = try await store.processPendingEmbeddingIndexTasks(provider: DeterministicTestEmbeddingProvider(), limit: 20)

    #expect(processed == 4)
    let results = try store.searchEmbeddings(
        queryVector: [1.0, 1.0, 0.0],
        groupID: "default",
        embeddingModel: "deterministic-test-v1",
        ownerTypes: [.fact],
        limit: 3
    )
    #expect(results.map(\.embedding.ownerID) == [fact.id])
    #expect(results.first?.embedding.id == "embedding:deterministic-test-v1:fact:fact-embed")
    #expect(results.first?.embedding.contentHash.isEmpty == false)

    let remainingEmbeddingTasks = try store.pendingIndexTasks(limit: 20).filter { $0.taskType == .embeddingUpsert }
    #expect(remainingEmbeddingTasks.isEmpty)
}

private func temporaryEmbeddingIndexTaskDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("connor-embedding-index-task-\(UUID().uuidString)")
        .appendingPathExtension("sqlite")
}
