import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphSearch

@Test func graphSearchFindsNodesByTitleAndSummary() throws {
    let index = InMemoryGraphSearchIndex(
        nodes: [
            GraphNode.workObject(id: "work-object-agent-os", title: "Agent OS", summary: "Graph-backed local agent operating system"),
            GraphNode.person(id: "person-shiwen", title: "诗闻", summary: "User profile")
        ],
        edges: [],
        observeLogEntries: []
    )

    let results = try index.search(query: "graph backed", options: .init(includeNodes: true, includeEdges: false, includeObserveLog: false))

    #expect(results.map(\.id) == ["node:work-object-agent-os"])
    #expect(results[0].kind == .node)
    #expect(results[0].reason.contains("node"))
}

@Test func graphSearchFindsEdgesByFact() throws {
    let edge = SemanticEdge(
        id: "edge-answer",
        sourceNodeID: "question-memory",
        targetNodeID: "answer-graph",
        relation: .answeredBy,
        fact: "Memory questions are answered by graph-backed context."
    )
    let index = InMemoryGraphSearchIndex(nodes: [], edges: [edge], observeLogEntries: [])

    let results = try index.search(query: "graph context", options: .init(includeNodes: false, includeEdges: true, includeObserveLog: false))

    #expect(results.map(\.id) == ["edge:edge-answer"])
    #expect(results[0].kind == .edge)
}

@Test func graphSearchExpandsOneHopNeighborhood() throws {
    let question = GraphNode.question(id: "question-memory", title: "How should memory work?")
    let answer = GraphNode.answer(id: "answer-graph", title: "Use graph-backed context")
    let edge = SemanticEdge.answeredBy(questionID: question.id, answerID: answer.id)
    let index = InMemoryGraphSearchIndex(nodes: [question, answer], edges: [edge], observeLogEntries: [])

    let results = try index.search(query: "memory", options: .init(includeNeighborhood: true))

    #expect(results.contains { $0.id == "node:question-memory" })
    #expect(results.contains { $0.id == "edge:\(edge.id)" })
    #expect(results.contains { $0.id == "node:answer-graph" })
}

@Test func graphSearchIncludesObserveLogEntries() throws {
    let entry = ObserveLogEntry(
        id: "obs-1",
        kind: .insight,
        source: .agent,
        content: "Recent insight: Ask flow should cite graph context.",
        normalizedSummary: "Ask flow cites graph context"
    )
    let index = InMemoryGraphSearchIndex(nodes: [], edges: [], observeLogEntries: [entry])

    let results = try index.search(query: "cite context", options: .init(includeNodes: false, includeEdges: false, includeObserveLog: true))

    #expect(results.map(\.id) == ["observe:obs-1"])
    #expect(results[0].kind == .observeLog)
}

@Test func contextAssemblerLimitsObserveLogAndKeepsSources() throws {
    let node = GraphNode.workObject(id: "work-object-agent-os", title: "Agent OS")
    let oldEntry = ObserveLogEntry(id: "obs-old", timestamp: Date(timeIntervalSince1970: 1), kind: .fragment, source: .agent, content: "Old context")
    let newEntry = ObserveLogEntry(id: "obs-new", timestamp: Date(timeIntervalSince1970: 2), kind: .insight, source: .agent, content: "New context")
    let results: [GraphSearchResult] = [
        .node(node, score: 1.0, reason: "matched node title"),
        .observeLog(oldEntry, score: 0.5, reason: "matched observe log"),
        .observeLog(newEntry, score: 0.9, reason: "matched observe log")
    ]

    let context = ContextAssembler(maxObserveLogEntries: 1).assemble(query: "agent os", results: results)

    #expect(context.query == "agent os")
    #expect(context.items.map(\.sourceID).contains("node:work-object-agent-os"))
    #expect(context.items.map(\.sourceID).contains("observe:obs-new"))
    #expect(!context.items.map(\.sourceID).contains("observe:obs-old"))
    #expect(context.renderedText.contains("Source: node:work-object-agent-os"))
    #expect(context.renderedText.contains("Source: observe:obs-new"))
}
