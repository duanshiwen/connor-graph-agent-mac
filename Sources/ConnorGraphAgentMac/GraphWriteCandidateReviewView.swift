import SwiftUI
import AppKit
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphSearch
import ConnorGraphAgent
import ConnorGraphStore
import ConnorGraphAppSupport

struct GraphWriteCandidateReviewView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("刷新") { viewModel.reloadGraphWriteCandidates() }
                if let summary = viewModel.lastGraphWriteCandidateResultSummary {
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("propose → validate → review → commit → audit")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            if viewModel.graphWriteCandidates.isEmpty {
                Text("暂无图谱写入候选。Agent 只能创建候选，不会直接污染长期图谱。")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(viewModel.graphWriteCandidates) { candidate in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(candidate.kind.rawValue)
                                .font(.headline)
                            Text(candidate.status.rawValue)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(statusColor(candidate.status).opacity(0.15), in: Capsule())
                                .foregroundStyle(statusColor(candidate.status))
                            Spacer()
                            Text(candidate.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text(candidate.rationale)
                            .font(.subheadline)
                            .textSelection(.enabled)

                        HStack(spacing: 12) {
                            Label("confidence \(candidate.confidence, specifier: "%.2f")", systemImage: "gauge.medium")
                            Label("run \(candidate.proposedByRunID)", systemImage: "play.circle")
                            if let toolCallID = candidate.proposedByToolCallID {
                                Label("tool \(toolCallID)", systemImage: "wrench.and.screwdriver")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        DisclosureGroup("候选 payload JSON") {
                            Text(candidate.payloadJSON)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(.quaternary.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }

                        if !candidate.validationErrors.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("验证/审阅记录")
                                    .font(.caption.weight(.semibold))
                                ForEach(candidate.validationErrors, id: \.self) { error in
                                    Text("• \(error)")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }

                        let auditItems = viewModel.graphWriteCandidateAudits[candidate.id] ?? []
                        DisclosureGroup("审计时间线（\(auditItems.count)）") {
                            if auditItems.isEmpty {
                                Text("暂无审计事件。执行验证、批准、治理提交或拒绝后会生成审计轨迹。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(auditItems) { item in
                                        HStack(alignment: .top, spacing: 8) {
                                            Circle()
                                                .fill(auditColor(item.severity))
                                                .frame(width: 8, height: 8)
                                                .padding(.top, 5)
                                            VStack(alignment: .leading, spacing: 2) {
                                                HStack(alignment: .firstTextBaseline) {
                                                    Text(item.title)
                                                        .font(.caption.weight(.semibold))
                                                    Text(item.createdAt.formatted(date: .omitted, time: .standard))
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                    Text(item.actor)
                                                        .font(.caption2.monospaced())
                                                        .foregroundStyle(.secondary)
                                                }
                                                Text(item.detail)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .textSelection(.enabled)
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }

                        HStack {
                            Button("验证") { Task { await viewModel.validateGraphWriteCandidate(candidate) } }
                                .disabled(candidate.status == .committed || candidate.status == .rejected)
                            Button("批准") { Task { await viewModel.approveGraphWriteCandidate(candidate) } }
                                .disabled(candidate.status == .approved || candidate.status == .committed || candidate.status == .rejected)
                            Button("治理提交") { Task { await viewModel.commitGraphWriteCandidate(candidate) } }
                                .disabled(candidate.status != .approved)
                            Button("拒绝", role: .destructive) { Task { await viewModel.rejectGraphWriteCandidate(candidate) } }
                                .disabled(candidate.status == .committed || candidate.status == .rejected)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }

            if let error = viewModel.errorMessage {
                Text(error).foregroundStyle(.red)
            }
        }
        .padding()
        .task {
            viewModel.deferViewUpdate {
                viewModel.reloadGraphWriteCandidates()
            }
        }
    }

    private func statusColor(_ status: GraphWriteCandidateStatus) -> Color {
        switch status {
        case .pendingValidation, .pendingReview: return .orange
        case .validationFailed, .rejected: return .red
        case .approved: return .blue
        case .committed: return .green
        case .superseded: return .secondary
        }
    }

    private func auditColor(_ severity: GraphWriteCandidateAuditSeverity) -> Color {
        switch severity {
        case .info: return .blue
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}

