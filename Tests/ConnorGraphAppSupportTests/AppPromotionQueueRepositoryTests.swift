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

@Test func appPromotionQueuePromotesCandidateFactIntoDraftGraphFact() throws {
    let store = try makePromotionStore()
    let source = GraphNodeV2(id: "work-object-agent-os", groupID: "default", type: .workObject, canonicalName: "Agent OS", title: "Agent OS")
    let target = GraphNodeV2(id: "answer-graph-memory", groupID: "default", type: .answer, canonicalName: "Graph Memory", title: "Graph Memory")
    let entry = ObserveLogEntry(
        id: "obs-fact",
        kind: .candidateFact,
        source: .agent,
        content: "Agent OS uses graph memory.",
        relatedNodeIDs: [source.id, target.id]
    )
    try store.upsert(nodeV2: source)
    try store.upsert(nodeV2: target)
    try store.upsert(observeLogEntry: entry)

    let repository = AppPromotionQueueRepository(store: store)
    let result = try repository.promote(entry)
    let promotedEntry = try #require(try store.observeLogEntry(id: entry.id))
    let fact = try #require(try store.graphFact(id: result.graphFacts[0].id))

    #expect(result.graphFacts.count == 1)
    #expect(fact.sourceNodeID == source.id)
    #expect(fact.targetNodeID == target.id)
    #expect(promotedEntry.status == .promoted)
    #expect(promotedEntry.promotedNodeID == fact.id)
}
