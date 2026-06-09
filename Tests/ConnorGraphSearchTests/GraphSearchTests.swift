import Testing
import ConnorGraphSearch

@Test func agentContextRenderedTextKeepsSources() throws {
    let context = AgentContext(
        query: "agent os",
        items: [
            AgentContextItem(
                sourceID: "node:work-object-agent-os",
                kind: .node,
                content: "Node[work_object] Agent OS: Graph-backed local agent operating system",
                reason: "matched via hybrid"
            ),
            AgentContextItem(
                sourceID: "episode:observe-demo",
                kind: .observeLog,
                content: "Episode[observe_log] Recent context",
                reason: "matched via hybrid"
            )
        ]
    )

    #expect(context.query == "agent os")
    #expect(context.renderedText.contains("Source: node:work-object-agent-os"))
    #expect(context.renderedText.contains("Source: episode:observe-demo"))
}
