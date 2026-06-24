import Foundation
import ConnorGraphCore
import ConnorGraphAgent

extension MailRuntime: AgentMailRuntime {
    public func sendApprovalBridgePayload(draftID: MailDraftID) async throws -> MailSendApprovalBridge {
        let payload = try await sendApprovalPayload(draftID: draftID)
        return MailSendApprovalBridge(
            draftID: payload.draftID,
            title: payload.title,
            from: payload.from,
            to: payload.to,
            cc: payload.cc,
            bcc: payload.bcc,
            subject: payload.subject,
            bodyPreview: payload.bodyPreview,
            attachmentCount: payload.attachmentCount,
            riskSummary: payload.riskSummary,
            envelopeHash: payload.envelopeHash
        )
    }

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
