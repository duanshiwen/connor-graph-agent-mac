import Foundation
import Testing
import ConnorGraphMemory

@Test func observeLogEntryDefaultsToThirtyDayExpiry() throws {
    let timestamp = Date(timeIntervalSince1970: 1_000)
    let entry = ObserveLogEntry(
        id: "obs-1",
        timestamp: timestamp,
        kind: .insight,
        source: .agent,
        content: "Graph store should be the runtime knowledge source of truth."
    )

    #expect(entry.expiresAt == timestamp.addingTimeInterval(30 * 24 * 60 * 60))
    #expect(entry.status == .active)
}

@Test func observeLogKindSupportsRequiredCases() throws {
    let kinds: Set<ObserveLogKind> = [
        .operation,
        .toolEvent,
        .insight,
        .fragment,
        .observation,
        .candidateFact,
        .decisionHint,
        .userPreference
    ]

    #expect(kinds.count == 8)
}

@Test func rollingMemoryPolicyClassifiesActiveExpiredAndExpiringSoon() throws {
    let now = Date(timeIntervalSince1970: 10_000)
    let active = ObserveLogEntry(
        id: "active",
        timestamp: now,
        kind: .operation,
        source: .user,
        content: "Active item",
        expiresAt: now.addingTimeInterval(10 * 24 * 60 * 60)
    )
    let expiringSoon = ObserveLogEntry(
        id: "soon",
        timestamp: now,
        kind: .insight,
        source: .agent,
        content: "Soon item",
        expiresAt: now.addingTimeInterval(2 * 24 * 60 * 60)
    )
    let expired = ObserveLogEntry(
        id: "expired",
        timestamp: now.addingTimeInterval(-40 * 24 * 60 * 60),
        kind: .fragment,
        source: .agent,
        content: "Expired item",
        expiresAt: now.addingTimeInterval(-1)
    )
    let policy = RollingMemoryPolicy(expiringSoonWindow: 3 * 24 * 60 * 60)

    #expect(policy.classification(for: active, at: now) == .active)
    #expect(policy.classification(for: expiringSoon, at: now) == .expiringSoon)
    #expect(policy.classification(for: expired, at: now) == .expired)
}

@Test func promotedEntryCarriesPromotedNodeIdAndStatus() throws {
    let entry = ObserveLogEntry(
        id: "obs-candidate",
        kind: .candidateFact,
        source: .agent,
        content: "Agent OS uses graph-backed memory."
    )

    let promoted = entry.promoted(toNodeID: "edge-agent-os-memory")

    #expect(promoted.status == .promoted)
    #expect(promoted.promotedNodeID == "edge-agent-os-memory")
}
