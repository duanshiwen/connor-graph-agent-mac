import SwiftUI
import ConnorGraphCore
import ConnorGraphAgent
import ConnorGraphAppSupport

struct AgentChatPermissionRequestCard: View {
    var approval: AgentPendingApproval
    @ObservedObject var viewModel: AppViewModel
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
                viewModel.approvePendingApproval(approval)
            } label: {
                Label(mailApproval.isMailSendRequest ? "允许发送" : "Allow", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            if approvalPresentation.allowsAlwaysAllow {
                Button {
                    viewModel.alwaysAllowPendingApproval(approval)
                } label: {
                    Label("Always Allow", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("将当前 Agent 会话权限提升为执行，并批准这个请求")
            }

            Button(role: .destructive) {
                viewModel.denyPendingApproval(approval)
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
