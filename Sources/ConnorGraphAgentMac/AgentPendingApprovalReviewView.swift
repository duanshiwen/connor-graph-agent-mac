import SwiftUI
import AppKit
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphSearch
import ConnorGraphAgent
import ConnorGraphStore
import ConnorGraphAppSupport

struct AgentPendingApprovalReviewView: View {
    @Bindable var model: ChatFeatureModel
    var chatActions: ChatFeatureActions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("刷新") { chatActions.approval.reloadPendingApprovals() }
                if let summary = model.approvals.lastResultSummary {
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("request → review → decision → audit → timeline")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            if model.approvals.pendingApprovals.isEmpty {
                Text("暂无待审批权限请求。模型管线只能请求工具权限，康纳同学负责审批、审计和 timeline。")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(model.approvals.pendingApprovals) { approval in
                    let row = AppAgentPendingApprovalPresentation(approval)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.title)
                                .font(.headline)
                            Text(row.statusLabel)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(severityColor(row.severity).opacity(0.15), in: Capsule())
                                .foregroundStyle(severityColor(row.severity))
                            Spacer()
                            Text(row.createdAt.connorLocalFormatted(date: .medium, time: .short))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text(row.detail)
                            .font(.subheadline)
                            .textSelection(.enabled)

                        HStack(spacing: 12) {
                            Label("run \(approval.runID)", systemImage: "play.circle")
                            Label("session \(approval.sessionID)", systemImage: "bubble.left.and.bubble.right")
                            if let toolName = approval.toolName {
                                Label(toolName, systemImage: "wrench.and.screwdriver")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        DisclosureGroup("Payload JSON") {
                            Text(approval.payloadJSON)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(.quaternary.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }

                        HStack {
                            Button("批准") { chatActions.approval.approvePendingApproval(approval) }
                            Button("拒绝", role: .destructive) { chatActions.approval.denyPendingApproval(approval) }
                            Button("取消") { chatActions.approval.cancelPendingApproval(approval) }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }

            if let error = chatActions.errors.errorMessage {
                Text(error).foregroundStyle(.red)
            }
        }
        .padding()
        .onAppear {
            chatActions.approval.reloadPendingApprovals()
        }
    }

    private func severityColor(_ severity: AppAgentPendingApprovalSeverity) -> Color {
        switch severity {
        case .warning: .orange
        case .success: .green
        case .error: .red
        case .cancelled: .secondary
        }
    }
}

