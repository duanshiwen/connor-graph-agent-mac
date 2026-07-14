import SwiftUI
import ConnorGraphCore
import ConnorGraphAgent
import ConnorGraphAppSupport

struct AgentChatPermissionRequestCard: View {
    var approval: AgentPendingApproval
    @Bindable var model: ChatFeatureModel
    var chatActions: ChatFeatureActions
    var onExpandReview: (() -> Void)? = nil
    @State private var isPayloadExpanded = false

    private var mailApproval: AppMailSendApprovalPresentation {
        AppMailSendApprovalPresentation(approval)
    }

    private var approvalPresentation: AppAgentPendingApprovalPresentation {
        AppAgentPendingApprovalPresentation(approval)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceM) {
            header

            details
                .frame(maxHeight: 122)

            actions
        }
        .padding(AgentChatLayout.spaceM)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous)
                .stroke(Color.orange.opacity(0.22), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(alignment: .center, spacing: AgentChatLayout.spaceM) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: AgentChatTypography.controlIconSize + 2, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.orange)
                .frame(width: AgentChatLayout.iconButtonSize, height: AgentChatLayout.iconButtonSize)

            HStack(spacing: AgentChatLayout.spaceS) {
                Text(mailApproval.isMailSendRequest ? "确认发送邮件" : "需要权限")
                    .font(AgentChatTypography.calloutEmphasis)
                Text(approval.capability.rawValue)
                    .font(AgentChatTypography.monoMeta)
                    .padding(.horizontal, AgentChatLayout.spaceS)
                    .padding(.vertical, AgentChatLayout.spaceXS)
                    .background(Color.orange.opacity(0.12), in: Capsule())
                    .foregroundStyle(.orange)
            }
        }
    }

    private var details: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                if mailApproval.isMailSendRequest {
                    mailSummaryDetails
                } else {
                    if let toolName = approval.toolName, !toolName.isEmpty {
                        Label("Tool: \(toolName)", systemImage: "wrench.and.screwdriver")
                    } else {
                        Label("Request: \(approval.requestID)", systemImage: "number")
                    }

                    Label("Session: \(approval.sessionID)", systemImage: "bubble.left.and.bubble.right")

                    payloadDisclosure
                }
            }
            .font(AgentChatTypography.meta)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.visible)
    }

    private var mailSummaryDetails: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
            Label(mailApproval.recipientSummary, systemImage: "person.crop.circle.badge.checkmark")
            Label(mailApproval.subjectSummary, systemImage: "text.quote")
            if let preview = mailApproval.bodyPreview?.trimmingCharacters(in: .whitespacesAndNewlines), !preview.isEmpty {
                Text(preview)
                    .font(AgentChatTypography.meta)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .textSelection(.enabled)
                    .padding(AgentChatLayout.spaceM)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusS, style: .continuous))
            }
            Text(mailApproval.securitySummary)
                .font(AgentChatTypography.monoMeta)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    private var payloadDisclosure: some View {
        DisclosureGroup(isExpanded: $isPayloadExpanded) {
            Text(approval.payloadJSON)
                .font(AgentChatTypography.monoMeta)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AgentChatLayout.spaceM)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusS, style: .continuous))
        } label: {
            Text(approvalPresentation.detail)
                .font(AgentChatTypography.monoMeta)
                .lineLimit(2)
                .truncationMode(.middle)
                .padding(.horizontal, AgentChatLayout.spaceM)
                .frame(height: AgentChatLayout.chipHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusS, style: .continuous))
        }
    }

    private var actions: some View {
        HStack(spacing: AgentChatLayout.spaceS) {
            Button {
                onExpandReview?()
            } label: {
                Label("放大审阅", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(onExpandReview == nil)
            .help("放大查看完整权限请求细节；缩小或按 Esc 不会批准或拒绝。")

            Button {
                chatActions.orchestration.approvePendingApproval(approval)
            } label: {
                Label(mailApproval.isMailSendRequest ? "允许发送" : "Allow", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            if approvalPresentation.allowsAlwaysAllow {
                Button {
                    chatActions.orchestration.alwaysAllowPendingApproval(approval)
                } label: {
                    Label("Always Allow", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("将当前 Agent 会话权限提升为执行，并批准这个请求")
            }

            Button(role: .destructive) {
                chatActions.orchestration.denyPendingApproval(approval)
            } label: {
                Label(mailApproval.isMailSendRequest ? "取消发送" : "Deny", systemImage: "xmark")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            Spacer(minLength: AgentChatLayout.spaceS)

            Text(approvalPresentation.allowsAlwaysAllow ? "Always Allow 会记住当前会话权限模式" : (mailApproval.isMailSendRequest ? "可放大审阅；发送邮件需要逐次确认" : "可放大审阅；此操作需要逐次审批"))
                .font(AgentChatTypography.meta)
                .foregroundStyle(.secondary)
        }
    }

    private var compactPayload: String {
        let trimmed = approval.payloadJSON
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "{}" : trimmed
    }
}

struct AgentPermissionExpandedReviewOverlay: View {
    var approval: AgentPendingApproval
    @Bindable var model: ChatFeatureModel
    var chatActions: ChatFeatureActions
    var onCollapse: () -> Void

    private var mailApproval: AppMailSendApprovalPresentation {
        AppMailSendApprovalPresentation(approval)
    }

    private var approvalPresentation: AppAgentPendingApprovalPresentation {
        AppAgentPendingApprovalPresentation(approval)
    }

    var body: some View {
        ZStack {
            Color(nsColor: .textBackgroundColor)
                .opacity(0.94)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: AgentChatLayout.spaceL) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: AgentChatLayout.spaceL) {
                        if mailApproval.isMailSendRequest {
                            MailApprovalExpandedContent(mail: mailApproval, approval: approval)
                        } else {
                            GenericApprovalExpandedContent(approval: approval, presentation: approvalPresentation)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, AgentChatLayout.spaceS)
                }
                .scrollIndicators(.visible)

                Divider()

                actionBar
            }
            .padding(AgentChatLayout.spaceXL)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusXL, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AgentChatLayout.radiusXL, style: .continuous)
                    .stroke(Color.orange.opacity(0.26), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 28, x: 0, y: 14)
            .padding(AgentChatLayout.spaceL)
        }
        .focusable()
        .onExitCommand(perform: onCollapse)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: AgentChatLayout.spaceM) {
            Image(systemName: mailApproval.isMailSendRequest ? "envelope.badge.shield.half.filled" : "shield.lefthalf.filled")
                .font(.system(size: 22, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.orange)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: AgentChatLayout.spaceXS) {
                Text(mailApproval.isMailSendRequest ? "审阅并确认发送邮件" : "权限审批详情")
                    .font(AgentChatTypography.title)
                Text(approvalPresentation.detail)
                    .font(AgentChatTypography.meta)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            Spacer(minLength: AgentChatLayout.spaceM)

            Button(action: onCollapse) {
                Label("缩小", systemImage: "arrow.down.right.and.arrow.up.left")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)
            .help("缩小审阅视图；也可以按 Esc。不会批准或拒绝。")
        }
    }

    private var actionBar: some View {
        HStack(spacing: AgentChatLayout.spaceM) {
            Text("Esc 或缩小：返回小卡片，不改变审批状态。")
                .font(AgentChatTypography.meta)
                .foregroundStyle(.secondary)

            Spacer(minLength: AgentChatLayout.spaceM)

            Button(role: .destructive) {
                chatActions.orchestration.denyPendingApproval(approval)
                onCollapse()
            } label: {
                Label(mailApproval.isMailSendRequest ? "取消发送" : "Deny", systemImage: "xmark")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button {
                chatActions.orchestration.approvePendingApproval(approval)
                onCollapse()
            } label: {
                Label(mailApproval.isMailSendRequest ? "允许发送" : "Allow", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}

private struct MailApprovalExpandedContent: View {
    var mail: AppMailSendApprovalPresentation
    var approval: AgentPendingApproval

    var body: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceL) {
            approvalInfoGrid

            SectionBlock(title: "邮件内容预览", systemImage: "doc.text") {
                Text(mail.bodyPreview?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? mail.bodyPreview! : "无正文预览。")
                    .font(AgentChatTypography.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AgentChatLayout.spaceM)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusM, style: .continuous))
            }

            SectionBlock(title: "安全与审计", systemImage: "lock.shield") {
                VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                    InfoRow(label: "Draft ID", value: mail.draftID)
                    if let envelopeHash = mail.envelopeHash, !envelopeHash.isEmpty {
                        InfoRow(label: "Envelope Hash", value: envelopeHash)
                    }
                    InfoRow(label: "附件数量", value: String(mail.attachmentCount))
                    if let riskSummary = mail.riskSummary, !riskSummary.isEmpty {
                        InfoRow(label: "风险摘要", value: riskSummary)
                    }
                    Text(mail.warning)
                        .font(AgentChatTypography.meta)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var approvalInfoGrid: some View {
        SectionBlock(title: "收件与主题", systemImage: "envelope") {
            VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                if let from = mail.from, !from.isEmpty { InfoRow(label: "From", value: from) }
                InfoRow(label: "To", value: mail.to.isEmpty ? "草稿中配置" : mail.to.joined(separator: ", "))
                if !mail.cc.isEmpty { InfoRow(label: "Cc", value: mail.cc.joined(separator: ", ")) }
                if mail.bccCount > 0 { InfoRow(label: "Bcc", value: "\(mail.bccCount) hidden") }
                InfoRow(label: "Subject", value: mail.subject?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? mail.subject! : "草稿中配置")
            }
        }
    }
}

private struct GenericApprovalExpandedContent: View {
    var approval: AgentPendingApproval
    var presentation: AppAgentPendingApprovalPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceL) {
            SectionBlock(title: "请求信息", systemImage: "info.circle") {
                VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                    InfoRow(label: "Capability", value: approval.capability.rawValue)
                    InfoRow(label: "Tool", value: approval.toolName ?? "未指定")
                    InfoRow(label: "Request ID", value: approval.requestID)
                    InfoRow(label: "Run ID", value: approval.runID)
                    InfoRow(label: "Session ID", value: approval.sessionID)
                    InfoRow(label: "Status", value: presentation.statusLabel)
                }
            }

            SectionBlock(title: "完整 Payload", systemImage: "curlybraces") {
                Text(Self.prettyPayload(approval.payloadJSON))
                    .font(AgentChatTypography.monoMeta)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AgentChatLayout.spaceM)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusM, style: .continuous))
            }
        }
    }

    private static func prettyPayload(_ json: String) -> String {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: pretty, encoding: .utf8)
        else { return trimmed.isEmpty ? "{}" : trimmed }
        return string
    }
}

private struct SectionBlock<Content: View>: View {
    var title: String
    var systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceM) {
            Label(title, systemImage: systemImage)
                .font(AgentChatTypography.calloutEmphasis)
                .foregroundStyle(.primary)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct InfoRow: View {
    var label: String
    var value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AgentChatLayout.spaceM) {
            Text(label)
                .font(AgentChatTypography.metaEmphasis)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(AgentChatTypography.meta)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
