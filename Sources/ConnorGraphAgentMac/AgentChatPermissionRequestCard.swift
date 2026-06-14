import SwiftUI
import ConnorGraphCore
import ConnorGraphAgent
import ConnorGraphAppSupport

struct AgentChatPermissionRequestCard: View {
    var approval: AgentPendingApproval
    @ObservedObject var viewModel: AppViewModel
    @State private var isPayloadExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceM) {
            HStack(alignment: .top, spacing: AgentChatLayout.spaceM) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: AgentChatTypography.controlIconSize + 2, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.orange)
                    .frame(width: AgentChatLayout.iconButtonSize, height: AgentChatLayout.iconButtonSize)

                VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                    HStack(spacing: AgentChatLayout.spaceS) {
                        Text("需要权限")
                            .font(AgentChatTypography.calloutEmphasis)
                        Text(approval.capability.rawValue)
                            .font(AgentChatTypography.monoMeta)
                            .padding(.horizontal, AgentChatLayout.spaceS)
                            .padding(.vertical, AgentChatLayout.spaceXS)
                            .background(Color.orange.opacity(0.12), in: Capsule())
                            .foregroundStyle(.orange)
                    }

                    if let toolName = approval.toolName, !toolName.isEmpty {
                        Label("Tool: \(toolName)", systemImage: "wrench.and.screwdriver")
                    } else {
                        Label("Request: \(approval.requestID)", systemImage: "number")
                    }

                    Label("Session: \(approval.sessionID)", systemImage: "bubble.left.and.bubble.right")

                    DisclosureGroup(isExpanded: $isPayloadExpanded) {
                        Text(approval.payloadJSON)
                            .font(AgentChatTypography.monoMeta)
                            .textSelection(.enabled)
                            .lineLimit(isPayloadExpanded ? nil : 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(AgentChatLayout.spaceM)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusS, style: .continuous))
                    } label: {
                        Text(compactPayload)
                            .font(AgentChatTypography.monoMeta)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .padding(.horizontal, AgentChatLayout.spaceM)
                            .frame(height: AgentChatLayout.chipHeight)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusS, style: .continuous))
                    }
                }
                .font(AgentChatTypography.meta)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: AgentChatLayout.spaceS) {
                Button {
                    viewModel.approvePendingApproval(approval)
                } label: {
                    Label("Allow", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

                Button {
                    viewModel.alwaysAllowPendingApproval(approval)
                } label: {
                    Label("Always Allow", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("将当前 Sidecar 会话权限提升为受信写入，并批准这个请求")

                Button(role: .destructive) {
                    viewModel.denyPendingApproval(approval)
                } label: {
                    Label("Deny", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Spacer(minLength: AgentChatLayout.spaceS)

                Text("Always Allow 会记住当前会话权限模式")
                    .font(AgentChatTypography.meta)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(AgentChatLayout.spaceM)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous)
                .stroke(Color.orange.opacity(0.22), lineWidth: 1)
        )
    }

    private var compactPayload: String {
        let trimmed = approval.payloadJSON
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "{}" : trimmed
    }
}
