import Foundation
import Testing
import ConnorGraphAppSupport
import ConnorGraphCore

@Test func mailSendApprovalPresentationParsesDraftAndOptionalPreviewFields() {
    let approval = AgentPendingApproval(
        requestID: "request-mail-1",
        runID: "run-1",
        sessionID: "session-1",
        capability: .sendMail,
        toolName: "mail_send_draft",
        payloadJSON: """
        {
          "draftID": "draft-1",
          "from": "connor@example.com",
          "to": ["alice@example.com", "bob@example.com"],
          "cc": ["carol@example.com"],
          "bcc": ["hidden@example.com"],
          "subject": "Quarterly update",
          "bodyPreview": "Here is the update...",
          "envelopeHash": "hash-1"
        }
        """
    )

    let presentation = AppMailSendApprovalPresentation(approval)

    #expect(presentation.isMailSendRequest)
    #expect(presentation.title == "确认发送邮件")
    #expect(presentation.draftID == "draft-1")
    #expect(presentation.from == "connor@example.com")
    #expect(presentation.to == ["alice@example.com", "bob@example.com"])
    #expect(presentation.cc == ["carol@example.com"])
    #expect(presentation.bccCount == 1)
    #expect(presentation.subjectSummary == "主题：Quarterly update")
    #expect(presentation.securitySummary.contains("Envelope: hash-1"))
}

@Test func mailSendApprovalPresentationFallsBackToDraftOnlyPayload() {
    let approval = AgentPendingApproval(
        requestID: "request-mail-2",
        runID: "run-1",
        sessionID: "session-1",
        capability: .sendMail,
        toolName: "mail_send_draft",
        payloadJSON: "{\"draftID\":\"draft-only\"}"
    )

    let presentation = AppMailSendApprovalPresentation(approval)

    #expect(presentation.draftID == "draft-only")
    #expect(presentation.recipientSummary == "收件人：草稿中配置")
    #expect(presentation.subjectSummary == "主题：草稿中配置")
    #expect(presentation.warning.contains("真实邮件"))
}
