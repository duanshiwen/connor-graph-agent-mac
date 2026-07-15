import Foundation
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphStore

enum AppDemoGraphSnapshotFactory {
    nonisolated static func make() -> GraphStoreSnapshot {
        let workObject = GraphEntity(
            id: "work-object-agent-os",
            graphID: "default",
            name: "康纳同学",
            stableKey: "project:work_object:agent-os",
            entityKind: .workObject,
            scope: .project,
            canonicalClassID: "project",
            summary: "A local-first operating system for graph-backed agents."
        )
        let question = GraphEntity(
            id: "question-memory",
            graphID: "default",
            name: "How should memory work?",
            stableKey: "project:entity:question-memory",
            entityKind: .entity,
            scope: .project,
            canonicalClassID: "question",
            summary: "Agent memory should be grounded in graph context."
        )
        let answer = GraphEntity(
            id: "answer-graph-memory",
            graphID: "default",
            name: "Use graph-backed context",
            stableKey: "project:entity:answer-graph-memory",
            entityKind: .entity,
            scope: .project,
            canonicalClassID: "answer",
            summary: "Use a local graph store as the runtime knowledge source of truth."
        )
        let fact = GraphStatement(
            id: "statement-question-memory-answered-by-answer-graph-memory",
            graphID: "default",
            subjectEntityID: question.id,
            predicate: .answeredBy,
            objectEntityID: answer.id,
            statementText: "question-memory is answered by answer-graph-memory",
            validAt: Date(timeIntervalSince1970: 1_700_000_000),
            justifications: [GraphJustification(type: .userStated, source: "demo", strength: 1.0)],
            sourceEpisodeIDs: ["episode-demo"]
        )
        let episode = GraphEpisodeV3(
            id: "episode-demo",
            graphID: "default",
            sourceType: .system,
            title: "Demo seed",
            content: "Graph store is runtime knowledge source of truth.",
            sourceDescription: "Built-in demo seed"
        )
        let observe = ObserveLogEntry(
            id: "observe-demo",
            kind: .insight,
            source: .agent,
            content: "Recent insight: graph store is the runtime knowledge layer.",
            normalizedSummary: "Graph store is runtime knowledge source of truth",
            workObjectID: workObject.id
        )
        return GraphStoreSnapshot(
            entities: [workObject, question, answer],
            statements: [fact],
            episodes: [episode],
            observeLogEntries: [observe]
        )
    }
}
