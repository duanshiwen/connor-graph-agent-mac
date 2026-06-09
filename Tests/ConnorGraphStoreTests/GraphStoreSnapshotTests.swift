import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphStore

private func temporarySnapshotDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func graphStoreCanLoadSnapshot() throws {
    let store = try SQLiteGraphStore(path: temporarySnapshotDatabaseURL().path)
    try store.migrate()
    let node = GraphNode.workObject(id: "work-object-agent-os", title: "Agent OS", summary: "Graph-backed SwiftUI runtime")
    let answer = GraphNode.answer(id: "answer-sqlite-runtime", title: "SQLite Runtime", summary: "Use Application Support SQLite as graph source of truth")
    let edge = SemanticEdge.answeredBy(questionID: node.id, answerID: answer.id)
    let observe = ObserveLogEntry(
        id: "observe-sqlite",
        kind: .insight,
        source: .agent,
        content: "SQLite snapshot can back the app search index.",
        normalizedSummary: "SQLite snapshot backs app search"
    )

    try store.upsert(node: node)
    try store.upsert(node: answer)
    try store.upsert(edge: edge)
    try store.upsert(observeLogEntry: observe)

    let snapshot = try store.snapshot()

    #expect(snapshot.nodes.map(\.id).contains(node.id))
    #expect(snapshot.nodes.map(\.id).contains(answer.id))
    #expect(snapshot.edges.map(\.id).contains(edge.id))
    #expect(snapshot.observeLogEntries.map(\.id).contains(observe.id))
}
