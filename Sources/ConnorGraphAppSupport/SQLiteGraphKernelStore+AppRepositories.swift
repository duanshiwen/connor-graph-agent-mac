import Foundation
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphStore

extension SQLiteGraphKernelStore: GraphRuntimeRepository {
    public func upsert(observeLogEntry entry: ObserveLogEntry) throws {
        // Observe log v3 persistence will move into the graph job/evidence pipeline.
        // Kept as a no-op during V3 cutover so tools do not reintroduce V2 graph writes.
    }

    public func upsert(graphWriteCandidate candidate: GraphWriteCandidate) throws {
        // Reviewed candidate flow is being replaced by optimistic extraction/write pipeline.
        // Kept as a no-op during V3 cutover so the tool surface compiles without V2 storage.
    }
}

extension SQLiteGraphKernelStore: AgentRunEventRepository {
    public func upsert(agentRun run: AgentRun) throws {}
    public func append(agentEvent event: PersistedAgentEvent) throws {}
}

public struct NoopAgentAuditLog: AgentAuditLog, Sendable {
    public init() {}
    public func record(_ event: AgentAuditEvent) async {}
}
