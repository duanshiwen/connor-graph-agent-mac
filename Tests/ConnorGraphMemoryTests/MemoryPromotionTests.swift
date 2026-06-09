import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory

@Test func candidateFactPromotesToGraphFactDraft() throws {
    let entry = ObserveLogEntry(
        id: "obs-fact",
        kind: .candidateFact,
        source: .agent,
        content: "Agent OS uses graph-backed memory.",
        relatedNodeIDs: ["work-object-agent-os", "entity-graph-memory"],
        confidence: 0.8
    )

    let result = try MemoryPromotionService().promoteCandidateFact(entry)

    #expect(result.graphNodes.isEmpty)
    #expect(result.graphFacts.count == 1)
    #expect(result.graphFacts[0].sourceNodeID == "work-object-agent-os")
    #expect(result.graphFacts[0].targetNodeID == "entity-graph-memory")
    #expect(result.graphFacts[0].relation == .relatedTo)
    #expect(result.graphFacts[0].fact == "Agent OS uses graph-backed memory.")
    #expect(result.graphFacts[0].confidence == 0.8)
    #expect(result.graphFacts[0].status == .draft)
    #expect(result.promotedEntry.status == .promoted)
    #expect(result.promotedEntry.promotedNodeID == result.graphFacts[0].id)
}

@Test func decisionHintPromotesToDecisionNodeDraft() throws {
    let entry = ObserveLogEntry(
        id: "obs-decision",
        kind: .decisionHint,
        source: .agent,
        content: "Use SwiftUI for the native macOS client.",
        workObjectID: "work-object-agent-os"
    )

    let result = try MemoryPromotionService().promoteDecisionHint(entry)

    #expect(result.graphNodes.count == 1)
    #expect(result.graphNodes[0].type == .decision)
    #expect(result.graphNodes[0].status == .draft)
    #expect(result.graphNodes[0].title == "Use SwiftUI for the native macOS client.")
    #expect(result.graphFacts.contains { $0.sourceNodeID == result.graphNodes[0].id && $0.targetNodeID == "work-object-agent-os" && $0.relation == .belongsTo })
    #expect(result.promotedEntry.status == .promoted)
    #expect(result.promotedEntry.promotedNodeID == result.graphNodes[0].id)
}

@Test func userPreferencePromotesToPersonPreferenceFact() throws {
    let entry = ObserveLogEntry(
        id: "obs-pref",
        kind: .userPreference,
        source: .user,
        content: "诗闻 prefers concise but systematic implementation updates.",
        relatedNodeIDs: ["person-shiwen"],
        confidence: 0.9
    )

    let result = try MemoryPromotionService().promoteUserPreference(entry)

    #expect(result.graphNodes.count == 1)
    #expect(result.graphNodes[0].type == .preference)
    #expect(result.graphNodes[0].status == .draft)
    #expect(result.graphFacts.count == 1)
    #expect(result.graphFacts[0].sourceNodeID == "person-shiwen")
    #expect(result.graphFacts[0].targetNodeID == result.graphNodes[0].id)
    #expect(result.graphFacts[0].relation == .hasPreference)
    #expect(result.graphFacts[0].confidence == 0.9)
}

@Test func promotionRejectsWrongObserveLogKind() throws {
    let entry = ObserveLogEntry(id: "obs-insight", kind: .insight, source: .agent, content: "Not promotable as candidate fact")

    #expect(throws: MemoryPromotionError.unsupportedKind(expected: .candidateFact, actual: .insight)) {
        try MemoryPromotionService().promoteCandidateFact(entry)
    }
}

@Test func promotionQueueCanDismissEntry() throws {
    let entry = ObserveLogEntry(id: "obs-dismiss", kind: .fragment, source: .agent, content: "Dismiss me")

    let dismissed = MemoryPromotionService().dismiss(entry)

    #expect(dismissed.status == .dismissed)
    #expect(dismissed.promotedNodeID == nil)
}

@Test func promotionQueueCanPinEntryForAnotherThirtyDays() throws {
    let now = Date(timeIntervalSince1970: 10_000)
    let entry = ObserveLogEntry(
        id: "obs-pin",
        timestamp: now,
        kind: .insight,
        source: .agent,
        content: "Pin me",
        expiresAt: now.addingTimeInterval(60)
    )

    let pinned = MemoryPromotionService().pin(entry, at: now, additionalDays: 30)

    #expect(pinned.status == .active)
    #expect(pinned.expiresAt == now.addingTimeInterval(30 * 24 * 60 * 60))
}
