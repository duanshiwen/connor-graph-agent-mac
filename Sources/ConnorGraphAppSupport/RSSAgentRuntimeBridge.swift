import Foundation
import ConnorGraphCore
import ConnorGraphAgent

extension RSSRuntime: AgentRSSRuntime {
    public func searchItems(_ request: RSSRuntimeSearchRequestBridge, runID: String?, sessionID: String?) async throws -> [RSSItemSummary] {
        try await searchItems(
            RSSRuntimeSearchRequest(
                query: request.query,
                sourceID: request.sourceID,
                includeHidden: request.includeHidden,
                limit: request.limit,
                startDate: request.startDate,
                endDate: request.endDate,
                timePreset: request.timePreset.flatMap(NativeSearchTimePreset.init(rawValue:)),
                timeSort: request.timeSort.flatMap(NativeSearchTemporalSort.init(rawValue:)) ?? .relevanceThenTimeDesc
            ),
            runID: runID,
            sessionID: sessionID
        )
    }
}
