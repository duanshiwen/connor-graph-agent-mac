import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore

private func temporaryRepositoryDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func graphStoreV2SavesAndLoadsEpisode() throws {
    let store = try SQLiteGraphStore(path: temporaryRepositoryDatabaseURL().path)
    try store.migrate()
    let episode = GraphEpisode(
        id: "episode-1",
        groupID: "default",
        sourceType: .chatMessage,
        sourceID: "message-1",
        name: "User message",
        content: "诗闻正在设计 Agent OS 图谱存储层。",
        sourceDescription: "chat",
        occurredAt: Date(timeIntervalSince1970: 1_000),
        ingestedAt: Date(timeIntervalSince1970: 1_001),
        sessionID: "session-1",
        workObjectID: "agent-os",
        status: .active,
        metadata: ["lang": "zh"]
    )

    try store.upsert(episode: episode)
    let loaded = try #require(try store.graphEpisode(id: episode.id))

    #expect(loaded == episode)
}

@Test func graphStoreV2SavesAndLoadsNode() throws {
    let store = try SQLiteGraphStore(path: temporaryRepositoryDatabaseURL().path)
    try store.migrate()
    let node = GraphNodeV2(
        id: "node-agent-os",
        groupID: "default",
        stableKey: "project:agent-os",
        type: .workObject,
        canonicalName: "Agent OS",
        title: "Agent OS",
        summary: "本地优先的 Agent 操作系统。",
        labels: ["Project", "WorkObject"],
        attributes: ["domain": "agent-runtime"],
        status: .active,
        confidence: 0.92,
        createdAt: Date(timeIntervalSince1970: 2_000),
        updatedAt: Date(timeIntervalSince1970: 2_001),
        validFrom: Date(timeIntervalSince1970: 1_900),
        metadata: ["source": "test"]
    )

    try store.upsert(nodeV2: node)
    let loaded = try #require(try store.graphNodeV2(id: node.id))

    #expect(loaded == node)
}

@Test func graphStoreV2SavesFactWithEpisodeProvenance() throws {
    let store = try SQLiteGraphStore(path: temporaryRepositoryDatabaseURL().path)
    try store.migrate()
    let source = GraphNodeV2(id: "node-shiwen", groupID: "default", type: .person, canonicalName: "诗闻", title: "诗闻")
    let target = GraphNodeV2(id: "node-agent-os", groupID: "default", type: .workObject, canonicalName: "Agent OS", title: "Agent OS")
    let episode = GraphEpisode(id: "episode-1", groupID: "default", sourceType: .chatMessage, name: "User message", content: "诗闻正在做 Agent OS。", sourceDescription: "chat")
    let fact = GraphFact(
        id: "fact-1",
        groupID: "default",
        sourceNodeID: source.id,
        targetNodeID: target.id,
        relation: .worksOn,
        fact: "诗闻正在设计 Agent OS 的图谱存储层。",
        confidence: 0.9,
        status: .active,
        createdAt: Date(timeIntervalSince1970: 3_000),
        updatedAt: Date(timeIntervalSince1970: 3_001),
        validAt: Date(timeIntervalSince1970: 2_999),
        referenceTime: Date(timeIntervalSince1970: 2_999),
        attributes: ["scope": "storage"],
        metadata: ["source": "test"]
    )

    try store.upsert(episode: episode)
    try store.upsert(nodeV2: source)
    try store.upsert(nodeV2: target)
    try store.upsert(fact: fact, sourceEpisodeIDs: [episode.id])

    let loaded = try #require(try store.graphFact(id: fact.id))
    let sources = try store.sourceEpisodeIDs(factID: fact.id)

    #expect(loaded == fact)
    #expect(sources == [episode.id])
}

@Test func graphStoreV2SchedulesIndexTasksForEpisodeNodeAndFactWrites() throws {
    let store = try SQLiteGraphStore(path: temporaryRepositoryDatabaseURL().path)
    try store.migrate()

    try store.upsert(episode: GraphEpisode(id: "episode-1", groupID: "default", sourceType: .chatMessage, name: "Message", content: "Agent OS", sourceDescription: "chat"))
    try store.upsert(nodeV2: GraphNodeV2(id: "node-1", groupID: "default", type: .workObject, canonicalName: "Agent OS", title: "Agent OS"))
    try store.upsert(nodeV2: GraphNodeV2(id: "node-2", groupID: "default", type: .person, canonicalName: "诗闻", title: "诗闻"))
    try store.upsert(fact: GraphFact(id: "fact-1", groupID: "default", sourceNodeID: "node-2", targetNodeID: "node-1", relation: .worksOn, fact: "诗闻设计 Agent OS。"), sourceEpisodeIDs: ["episode-1"])

    let tasks = try store.pendingIndexTasks(limit: 10)

    #expect(tasks.map(\.ownerID).contains("episode-1"))
    #expect(tasks.map(\.ownerID).contains("node-1"))
    #expect(tasks.map(\.ownerID).contains("node-2"))
    #expect(tasks.map(\.ownerID).contains("fact-1"))
}

@Test func graphStoreV2IndexesAndSearchesFTSForNodesFactsAndEpisodes() throws {
    let store = try SQLiteGraphStore(path: temporaryRepositoryDatabaseURL().path)
    try store.migrate()

    try store.upsert(episode: GraphEpisode(id: "episode-1", groupID: "default", sourceType: .chatMessage, name: "Message", content: "诗闻正在设计可靠的图谱存储层。", sourceDescription: "chat"))
    try store.upsert(nodeV2: GraphNodeV2(id: "node-1", groupID: "default", type: .workObject, canonicalName: "Agent OS", title: "Agent OS", summary: "可靠的本地图谱存储产品"))
    try store.upsert(nodeV2: GraphNodeV2(id: "node-2", groupID: "default", type: .person, canonicalName: "诗闻", title: "诗闻"))
    try store.upsert(fact: GraphFact(id: "fact-1", groupID: "default", sourceNodeID: "node-2", targetNodeID: "node-1", relation: .worksOn, fact: "诗闻设计可靠的 Agent OS 图谱存储层。"), sourceEpisodeIDs: ["episode-1"])

    try store.processPendingFTSIndexTasks(limit: 10)

    #expect(try store.searchNodeFTS(query: "Agent", groupID: "default", limit: 10).map(\.id) == ["node-1"])
    #expect(try store.searchFactFTS(query: "Agent", groupID: "default", limit: 10).map(\.id) == ["fact-1"])
    #expect(try store.searchEpisodeFTS(query: "可靠", groupID: "default", limit: 10).map(\.id) == ["episode-1"])
}
