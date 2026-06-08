import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphStore
import ConnorGraphAppSupport

private func temporaryPromotionQueueDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

private func makePromotionStore() throws -> SQLiteGraphStore {
    let store = try SQLiteGraphStore(path: temporaryPromotionQueueDatabaseURL().path)
    try store.migrate()
    return store
}

@Test func appPromotionQueueLoadsCandidates() throws {
    let store = try makePromotionStore()
    let entry = ObserveLogEntry(id: "obs-candidate", kind: .decisionHint, source: .agent, content: "Use review UI")
    try store.upsert(observeLogEntry: entry)

    let repository = AppPromotionQueueRepository(store: store)
    let candidates = try repository.loadCandidates()

    #expect(candidates.map(\.id) == [entry.id])
}

@Test func appPromotionQueueDismissesCandidate() throws {
    let store = try makePromotionStore()
    let entry = ObserveLogEntry(id: "obs-dismiss", kind: .decisionHint, source: .agent, content: "Dismiss me")
    try store.upsert(observeLogEntry: entry)

    let repository = AppPromotionQueueRepository(store: store)
    let dismissed = try repository.dismiss(entry)
    let loaded = try #require(try store.observeLogEntry(id: entry.id))

    #expect(dismissed.status == .dismissed)
    #expect(loaded.status == .dismissed)
}

@Test func appPromotionQueuePinsCandidateForAnotherThirtyDays() throws {
    let store = try makePromotionStore()
    let now = Date(timeIntervalSince1970: 10_000)
    let entry = ObserveLogEntry(
        id: "obs-pin",
        timestamp: now,
        kind: .decisionHint,
        source: .agent,
        content: "Pin me",
        expiresAt: now.addingTimeInterval(60)
    )
    try store.upsert(observeLogEntry: entry)

    let repository = AppPromotionQueueRepository(store: store)
    let pinned = try repository.pin(entry, now: now)
    let loaded = try #require(try store.observeLogEntry(id: entry.id))

    #expect(pinned.status == .active)
    #expect(pinned.expiresAt == now.addingTimeInterval(30 * 24 * 60 * 60))
    #expect(loaded.expiresAt == pinned.expiresAt)
}

@Test func appPromotionQueuePromotesCandidateFactIntoDraftEdge() throws {
    let store = try makePromotionStore()
    let source = GraphNode.workObject(id: "work-object-agent-os", title: "Agent OS")
    let target = GraphNode.answer(id: "answer-graph-memory", title: "Graph Memory")
    let entry = ObserveLogEntry(
        id: "obs-fact",
        kind: .candidateFact,
        source: .agent,
        content: "Agent OS uses graph memory.",
        relatedNodeIDs: [source.id, target.id]
    )
    try store.upsert(node: source)
    try store.upsert(node: target)
    try store.upsert(observeLogEntry: entry)

    let repository = AppPromotionQueueRepository(store: store)
    let result = try repository.promote(entry)
    let promotedEntry = try #require(try store.observeLogEntry(id: entry.id))
    let edge = try #require(try store.edge(id: result.edges[0].id))

    #expect(result.edges.count == 1)
    #expect(edge.sourceNodeID == source.id)
    #expect(edge.targetNodeID == target.id)
    #expect(promotedEntry.status == .promoted)
    #expect(promotedEntry.promotedNodeID == edge.id)
}
