import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphStore

private func temporaryRuntimeFactoryDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func appGraphAgentRuntimeFactoryBuildsChatControllerFromSQLiteHybridSearch() async throws {
    let store = try SQLiteGraphStore(path: temporaryRuntimeFactoryDatabaseURL().path)
    try store.migrate()

    let episode = GraphEpisode(id: "episode-1", groupID: "default", sourceType: .chatMessage, name: "Design note", content: "诗闻正在设计 Graphiti-grade 本地图谱。", sourceDescription: "chat")
    let person = GraphNodeV2(id: "node-shiwen", groupID: "default", type: .person, canonicalName: "诗闻", title: "诗闻")
    let project = GraphNodeV2(id: "node-agent-os", groupID: "default", type: .workObject, canonicalName: "Agent OS", title: "Agent OS", summary: "Graphiti-grade local graph agent")
    let fact = GraphFact(id: "fact-agent-os", groupID: "default", sourceNodeID: person.id, targetNodeID: project.id, relation: .worksOn, fact: "诗闻正在设计 Agent OS 的 Graphiti-grade 本地图谱。")

    try store.upsert(episode: episode)
    try store.upsert(nodeV2: person)
    try store.upsert(nodeV2: project)
    try store.upsert(fact: fact, sourceEpisodeIDs: [episode.id])
    try store.processPendingFTSIndexTasks(limit: 20)

    let factory = AppGraphAgentRuntimeFactory(store: store, settingsRepository: AppLLMSettingsRepository())
    let controller = factory.makeChatController(session: AgentSession(id: "session-1"))

    let response = try await controller.agent.ask("Graphiti")

    #expect(response.context.items.map(\.sourceID).contains("fact:fact-agent-os"))
    #expect(response.answer.citations.contains("fact:fact-agent-os"))
    #expect(response.session.messages.last?.contextSnapshot?.contains("Fact[WORKS_ON] 诗闻正在设计 Agent OS 的 Graphiti-grade 本地图谱。") == true)
}
