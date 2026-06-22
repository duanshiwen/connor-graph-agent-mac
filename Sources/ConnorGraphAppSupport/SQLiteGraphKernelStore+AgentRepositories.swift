import Foundation
import ConnorGraphAgent
import ConnorGraphStore

extension SQLiteGraphKernelStore: AgentRunEventRepository {
    public func upsert(agentRun run: AgentRun) throws {
        try upsert(run: run)
    }

    public func append(agentEvent event: PersistedAgentEvent) throws {
        try append(event: event)
    }
}

extension SQLiteGraphKernelStore: AgentPendingApprovalRepository {}
