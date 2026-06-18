import Foundation
import ConnorGraphCore
import ConnorGraphAgent

extension MailRuntime: AgentMailRuntime {
    public func searchMessages(_ request: MailRuntimeSearchRequestBridge, runID: String?, sessionID: String?) async throws -> [MailMessageSummary] {
        try await searchMessages(MailRuntimeSearchRequest(query: request.query, accountID: request.accountID, limit: request.limit), runID: runID, sessionID: sessionID)
    }
}
