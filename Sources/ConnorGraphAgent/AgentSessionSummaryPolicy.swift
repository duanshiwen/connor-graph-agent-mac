import ConnorGraphCore

public struct AgentSessionSummaryPolicy: Sendable, Equatable {
    public init() {}

    public func summaryForContext(_ summary: AgentSessionSummary?, session: AgentSession) -> AgentSessionSummary? {
        guard let summary else { return nil }
        return summary.freshness(for: session).isFresh ? summary : nil
    }
}
