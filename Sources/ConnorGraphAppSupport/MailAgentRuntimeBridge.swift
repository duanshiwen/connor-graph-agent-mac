import Foundation
import ConnorGraphCore
import ConnorGraphAgent

extension MailRuntime: AgentMailRuntime {
    public func searchMessages(_ request: MailRuntimeSearchRequestBridge, runID: String?, sessionID: String?) async throws -> [MailMessageSummary] {
        try await searchMessages(
            MailRuntimeSearchRequest(
                query: request.query,
                accountID: request.accountID,
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
