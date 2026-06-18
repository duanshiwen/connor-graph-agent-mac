import Foundation
import ConnorGraphCore
import ConnorGraphAgent

extension RSSRuntime: AgentRSSRuntime {
    public func searchItems(_ request: RSSRuntimeSearchRequestBridge, runID: String?, sessionID: String?) async throws -> [RSSItemSummary] {
        try await searchItems(RSSRuntimeSearchRequest(query: request.query, sourceID: request.sourceID, includeHidden: request.includeHidden, limit: request.limit), runID: runID, sessionID: sessionID)
    }
}
