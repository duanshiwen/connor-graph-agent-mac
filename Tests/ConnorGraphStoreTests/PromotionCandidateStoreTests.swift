import Foundation
import Testing
import ConnorGraphMemory
import ConnorGraphStore

private func temporaryPromotionDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func graphStoreLoadsPromotionCandidates() throws {
    let store = try SQLiteGraphStore(path: temporaryPromotionDatabaseURL().path)
    try store.migrate()
    let candidateFact = ObserveLogEntry(id: "obs-fact", kind: .candidateFact, source: .agent, content: "A fact", relatedNodeIDs: ["a", "b"])
    let decisionHint = ObserveLogEntry(id: "obs-decision", kind: .decisionHint, source: .agent, content: "A decision")
    let userPreference = ObserveLogEntry(id: "obs-pref", kind: .userPreference, source: .user, content: "A preference", relatedNodeIDs: ["person-shiwen"])
    let insight = ObserveLogEntry(id: "obs-insight", kind: .insight, source: .agent, content: "Not promotable")
    let dismissed = ObserveLogEntry(id: "obs-dismissed", kind: .candidateFact, source: .agent, content: "Dismissed", status: .dismissed)

    for entry in [candidateFact, decisionHint, userPreference, insight, dismissed] {
        try store.upsert(observeLogEntry: entry)
    }

    let candidates = try store.promotionCandidates()

    #expect(candidates.map(\.id) == ["obs-decision", "obs-fact", "obs-pref"])
}

@Test func graphStoreUpdatesObserveLogEntryStatus() throws {
    let store = try SQLiteGraphStore(path: temporaryPromotionDatabaseURL().path)
    try store.migrate()
    var entry = ObserveLogEntry(id: "obs-update", kind: .candidateFact, source: .agent, content: "Update me", relatedNodeIDs: ["a", "b"])
    try store.upsert(observeLogEntry: entry)

    entry.status = .dismissed
    try store.update(observeLogEntry: entry)

    let loadedEntry = try store.observeLogEntry(id: entry.id)
    let loaded = try #require(loadedEntry)
    #expect(loaded.status == .dismissed)
}
