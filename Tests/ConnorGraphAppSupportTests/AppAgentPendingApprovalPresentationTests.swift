import Foundation
import Testing
import ConnorGraphAppSupport
import ConnorGraphCore

@Test func appPendingApprovalPresentationSummarizesApprovalForNativeUI() {
    let approval = AgentPendingApproval(
        id: "approval-1",
        requestID: "permission-tool-1",
        runID: "run-1",
        sessionID: "session-1",
        capability: .readSession,
        toolName: "Read",
        payloadJSON: "{ \"file_path\" : \"README.md\" }",
        status: .pending,
        createdAt: Date(timeIntervalSince1970: 1_000),
        updatedAt: Date(timeIntervalSince1970: 1_000)
    )

    let row = AppAgentPendingApprovalPresentation(approval, sessionTitle: "修复登录问题")

    #expect(row.id == "approval-1")
    #expect(row.requestID == "permission-tool-1")
    #expect(row.title == "请求执行：读取文件")
    #expect(row.detail.contains("权限：读取会话"))
    #expect(row.detail.contains("参数：{\"file_path\":\"README.md\"}"))
    #expect(row.toolDisplayName == "读取文件")
    #expect(row.capabilityLabel == "读取会话")
    #expect(row.capabilityDescription.contains("不会主动修改内容"))
    #expect(row.sessionTitle == "修复登录问题")
    #expect(row.statusLabel == "等待审批")
    #expect(row.severity == .warning)
    #expect(row.createdAt == Date(timeIntervalSince1970: 1_000))
}

@Test func appPendingApprovalPresentationSpecialCasesMailSendApproval() {
    let approval = AgentPendingApproval(
        requestID: "request-mail",
        runID: "run-1",
        sessionID: "session-1",
        capability: .sendMail,
        toolName: "mail_send_draft",
        payloadJSON: "{\"draftID\":\"draft-1\",\"to\":[\"alice@example.com\"],\"subject\":\"Hello\"}"
    )

    let row = AppAgentPendingApprovalPresentation(approval)

    #expect(row.title == "确认发送邮件")
    #expect(row.detail.contains("收件人：alice@example.com"))
    #expect(row.detail.contains("主题：Hello"))
    #expect(row.allowsAlwaysAllow == false)
}

@Test func appPendingApprovalPresentationRedactsMailBccAndIncludesEnvelopeHash() {
    let approval = AgentPendingApproval(
        requestID: "request-mail-redacted",
        runID: "run-1",
        sessionID: "session-1",
        capability: .sendMail,
        toolName: "mail_send_draft",
        payloadJSON: """
        {
          "draftID": "draft-1",
          "to": ["alice@example.com"],
          "bcc": ["hidden@example.com"],
          "subject": "Hello",
          "bodyPreview": "Short preview",
          "riskSummary": "External email send",
          "attachmentCount": 2,
          "envelopeHash": "hash-1"
        }
        """
    )

    let row = AppAgentPendingApprovalPresentation(approval)
    let mail = AppMailSendApprovalPresentation(approval)

    #expect(row.title == "确认发送邮件")
    #expect(row.detail.contains("信封摘要：hash-1"))
    #expect(row.detail.contains("密送：已隐藏 1 位收件人"))
    #expect(!row.detail.contains("hidden@example.com"))
    #expect(row.allowsAlwaysAllow == false)
    #expect(mail.bodyPreview == "Short preview")
    #expect(mail.riskSummary == "External email send")
    #expect(mail.attachmentCount == 2)
}

@Test func appMailSendApprovalPresentationParsesSnakeCaseRiskAndAttachmentFields() {
    let approval = AgentPendingApproval(
        requestID: "request-mail-snake",
        runID: "run-1",
        sessionID: "session-1",
        capability: .sendMail,
        toolName: "mail_send_draft",
        payloadJSON: """
        {
          "draft_id": "draft-2",
          "body_preview": "Preview body",
          "risk_summary": "Approval gated",
          "attachment_count": 3,
          "envelope_hash": "hash-2"
        }
        """
    )

    let mail = AppMailSendApprovalPresentation(approval)

    #expect(mail.draftID == "draft-2")
    #expect(mail.bodyPreview == "Preview body")
    #expect(mail.riskSummary == "Approval gated")
    #expect(mail.attachmentCount == 3)
    #expect(mail.envelopeHash == "hash-2")
}

@Test func appPendingApprovalPresentationShowsVerifiedCalendarTarget() {
    let approval = AgentPendingApproval(requestID: "request-calendar", runID: "run-1", sessionID: "session-1", capability: .mutateCalendar, toolName: "calendar_write", payloadJSON: "{\"operation\":\"delete_event\",\"eventID\":\"event:opaque/id\",\"expectedVersion\":\"version-1\",\"verifiedEventTitle\":\"Connor Test\",\"verifiedCalendarID\":\"calendar-test\"}")
    let row = AppAgentPendingApprovalPresentation(approval)
    #expect(row.title == "日历：删除日程")
    #expect(row.detail.contains("Connor Test"))
    #expect(row.detail.contains("日程 ID：event:opaque/id"))
    #expect(row.detail.contains("calendar-test"))
    #expect(row.allowsAlwaysAllow == false)
}

@Test func appPendingApprovalPresentationShowsPersonalityDiffAndDisablesAlwaysAllow() {
    let approval = AgentPendingApproval(
        requestID: "request-personality",
        runID: "run-1",
        sessionID: "session-1",
        capability: .mutatePersonality,
        toolName: "personality_commit_proposal",
        payloadJSON: """
        {
          "title": "更新康纳同学性格",
          "beforeSummary": "温和可靠",
          "afterSummary": "温和但更加直接"
        }
        """
    )

    let row = AppAgentPendingApprovalPresentation(approval)

    #expect(row.title == "更新康纳同学性格")
    #expect(row.detail.contains("固定姓名：康纳同学"))
    #expect(row.detail.contains("温和可靠 → 温和但更加直接"))
    #expect(row.capabilityLabel == "修改康纳同学性格")
    #expect(row.allowsAlwaysAllow == false)
}

@Test func appPendingApprovalPresentationMapsResolvedStatusesForNativeUI() {
    let statuses: [AgentPendingApprovalStatus] = [.pending, .approved, .denied, .cancelled]

    let severities = statuses.map { status in
        AppAgentPendingApprovalPresentation(AgentPendingApproval(
            requestID: "request-\(status.rawValue)",
            runID: "run-1",
            sessionID: "session-1",
            capability: .externalNetwork,
            status: status
        )).severity
    }

    #expect(severities == [.warning, .success, .error, .cancelled])
}
