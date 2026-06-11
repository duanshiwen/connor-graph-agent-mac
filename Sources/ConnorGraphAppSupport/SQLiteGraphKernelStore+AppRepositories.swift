import Foundation
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphStore

extension SQLiteGraphKernelStore: GraphRuntimeRepository {
    public func upsert(observeLogEntry entry: ObserveLogEntry) throws {
        // Route observe log entries through the V3 extraction pipeline.
        // The extraction worker will process the content and commit via optimistic write.
        let sourceType: GraphExtractionSourceType = switch entry.source {
        case .user: .chat
        case .agent: .chat
        case .tool: .manual
        case .import: .document
        case .search: .webpage
        case .system: .manual
        }
        let source = GraphExtractionSource(
            id: entry.id,
            graphID: "default",
            sourceType: sourceType,
            title: entry.normalizedSummary.isEmpty ? String(entry.content.prefix(80)) : entry.normalizedSummary,
            content: entry.content,
            occurredAt: entry.timestamp,
            sessionID: entry.sessionID,
            workObjectID: entry.workObjectID,
            metadata: entry.metadata
        )
        _ = try enqueueExtractionJob(graphID: source.graphID, source: source, now: entry.timestamp)
    }

    public func upsert(graphWriteCandidate candidate: GraphWriteCandidate) throws {
        try upsertWriteCandidate(candidate)
    }
}

extension SQLiteGraphKernelStore: AgentRunEventRepository {
    public func upsert(agentRun run: AgentRun) throws {
        try upsert(run: run)
    }

    public func append(agentEvent event: PersistedAgentEvent) throws {
        try append(event: event)
    }
}

extension SQLiteGraphKernelStore: AgentPendingApprovalRepository {}


