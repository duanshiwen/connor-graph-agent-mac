import SwiftUI
import AppKit
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphSearch
import ConnorGraphAgent
import ConnorGraphStore
import ConnorGraphAppSupport

struct SchemaHealthBanner: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        HStack(spacing: 10) {
            if let report = viewModel.schemaHealthReport {
                Circle()
                    .fill(statusColor(report.status))
                    .frame(width: 8, height: 8)
                Text("图模型 v\(report.actualVersion)")
                    .font(.caption.weight(.semibold))
                Text(report.status.rawValue)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                if report.status != .healthy {
                    Text(report.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Circle()
                    .fill(Color.gray)
                    .frame(width: 8, height: 8)
                Text("图模型版本未加载")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let databasePath = viewModel.databasePath {
                Text(databasePath)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Button("刷新") { viewModel.reloadSchemaHealthReport() }
                .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.06))
    }

    private func statusColor(_ status: GraphSchemaHealthReport.Status) -> Color {
        switch status {
        case .healthy: return .green
        case .warning: return .orange
        case .migrationRequired: return .red
        }
    }
}

struct GraphEntitiesView: View {
    let entities: [GraphEntity]
    let statements: [GraphStatement]
    let episodes: [GraphEpisodeV3]

    var body: some View {
        List {
            Section("实体") {
                ForEach(entities) { entity in
                    VStack(alignment: .leading) {
                        Text(entity.name).font(.headline)
                        Text("\(entity.entityKind.rawValue) · \(entity.status.rawValue)").font(.caption).foregroundStyle(.secondary)
                        if !entity.summary.isEmpty { Text(entity.summary).font(.subheadline) }
                    }
                }
            }
            Section("陈述") {
                ForEach(statements) { statement in
                    VStack(alignment: .leading) {
                        Text(statement.predicate.rawValue).font(.headline)
                        Text("\(statement.subjectEntityID) → \(statement.objectEntityID)").font(.caption).foregroundStyle(.secondary)
                        Text(statement.statementText).font(.subheadline)
                    }
                }
            }
            Section("Episodes") {
                ForEach(episodes) { episode in
                    VStack(alignment: .leading) {
                        Text(episode.title).font(.headline)
                        Text("\(episode.sourceType.rawValue) · \(episode.status.rawValue)").font(.caption).foregroundStyle(.secondary)
                        Text(episode.content).font(.subheadline).lineLimit(3)
                    }
                }
            }
        }
        .navigationTitle("图谱")
    }
}

struct SearchView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("搜索图谱和观察日志", text: $viewModel.query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await viewModel.runSearch() } }
                Button("搜索") { Task { await viewModel.runSearch() } }
            }
            List(viewModel.searchResults) { result in
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.id).font(.headline)
                    Text(result.ownerType.rawValue).font(.caption).foregroundStyle(.secondary)
                    Text(result.retrievalMethod).font(.subheadline)
                    Text(result.text).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .navigationTitle("搜索")
    }
}

struct ObserveLogView: View {
    let entries: [ObserveLogEntry]

    var body: some View {
        List(entries) { entry in
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.content).font(.headline)
                Text("\(entry.kind.rawValue) · \(entry.status.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("过期时间：\(entry.expiresAt.formatted())")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("观察日志")
    }
}

struct PromotionQueueView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("刷新") { viewModel.reloadPromotionCandidates() }
                if let summary = viewModel.lastPromotionResultSummary {
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
            }

            if viewModel.promotionCandidates.isEmpty {
                Text("暂无可提升候选项。")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(viewModel.promotionCandidates) { entry in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(entry.kind.rawValue).font(.headline)
                            Spacer()
                            Text(entry.status.rawValue).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(entry.content)
                        if !entry.normalizedSummary.isEmpty {
                            Text(entry.normalizedSummary).font(.subheadline).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 12) {
                            if let workObjectID = entry.workObjectID {
                                Text("工作对象：\(workObjectID)")
                            }
                            Text("重要性：\(entry.importance, format: .number.precision(.fractionLength(2)))")
                            Text("置信度：\(entry.confidence, format: .number.precision(.fractionLength(2)))")
                            Text("过期时间：\(entry.expiresAt.formatted())")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        HStack {
                            Button("提升") { viewModel.promote(entry) }
                            Button("忽略") { viewModel.dismissPromotionCandidate(entry) }
                            Button("置顶 30 天") { viewModel.pinPromotionCandidate(entry) }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }

            if let error = viewModel.errorMessage {
                Text(error).foregroundStyle(.red)
            }
        }
        .padding()
        .navigationTitle("提升队列")
        .task {
            viewModel.deferViewUpdate {
                viewModel.reloadPromotionCandidates()
            }
        }
    }
}

struct AgentPendingApprovalReviewView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("刷新") { viewModel.reloadPendingApprovals() }
                if let summary = viewModel.lastPendingApprovalResultSummary {
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("request → review → decision → audit → timeline")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            if viewModel.pendingApprovals.isEmpty {
                Text("暂无待审批权限请求。Sidecar 只能请求权限，康纳同学负责审批、审计和 timeline。")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(viewModel.pendingApprovals) { approval in
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
                            Text(row.createdAt.formatted(date: .abbreviated, time: .shortened))
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
                            Button("批准") { viewModel.approvePendingApproval(approval) }
                            Button("拒绝", role: .destructive) { viewModel.denyPendingApproval(approval) }
                            Button("取消") { viewModel.cancelPendingApproval(approval) }
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
        .navigationTitle("权限审批")
        .task {
            viewModel.deferViewUpdate {
                viewModel.reloadPendingApprovals()
            }
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
        .navigationTitle("写入候选")
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

struct MemoryChangeLogView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("刷新") { viewModel.reloadMemoryChangeLog() }
                Spacer()
                Text("what changed · why · source trace · reversible later")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            if viewModel.memoryChangeLogEntries.isEmpty {
                Text("暂无记忆变更记录。后台 extraction/admission 运行后会在这里形成可审计 change log。")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(viewModel.memoryChangeLogEntries) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(entry.title)
                                .font(.headline)
                            Text(entry.action.rawValue)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(changeLogColor(entry.action).opacity(0.15), in: Capsule())
                                .foregroundStyle(changeLogColor(entry.action))
                            Spacer()
                            Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(entry.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 6)
                }
            }

            if let error = viewModel.errorMessage {
                Text(error).foregroundStyle(.red)
            }
        }
        .padding()
        .navigationTitle("记忆变更")
        .task {
            viewModel.deferViewUpdate {
                viewModel.reloadMemoryChangeLog()
            }
        }
    }

    private func changeLogColor(_ action: GraphMemoryChangeLogAction) -> Color {
        switch action {
        case .extractionCommitted: return .green
        case .extractionHeld, .extractionAskUser: return .orange
        case .extractionDiscarded: return .secondary
        case .extractionFailed: return .red
        case .replayDryRun: return .blue
        case .manualInvalidation: return .purple
        }
    }
}

struct GraphExtractionDiagnosticsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("刷新") { viewModel.reloadGraphExtractionTraces() }
                Spacer()
                Text("extract → validate → admit → auto-commit / hold / ask")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            if !viewModel.admissionHoldQueueItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("系统待诊断队列")
                        .font(.headline)
                    Text("这些是后台自愈队列，不是默认用户逐条审核。系统可用于 replay、grounding、merge 或必要时询问用户。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let summary = viewModel.lastAdmissionHoldQueueActionSummary {
                        Text(summary)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .padding(8)
                            .background(.quaternary.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    ForEach(viewModel.admissionHoldQueueItems) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(item.title)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(item.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            HStack(spacing: 8) {
                                Button("检查证据") { viewModel.inspectAdmissionHoldQueueItemEvidence(item) }
                                Button("重跑提取") { viewModel.rerunAdmissionHoldQueueItem(item) }
                                Button("批准提交") { viewModel.approveAdmissionHoldQueueItem(item) }
                                Button("Dismiss", role: .destructive) { viewModel.rejectAdmissionHoldQueueItem(item) }
                            }
                            .font(.caption)
                        }
                        .padding(8)
                        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                Divider()
            }

            if viewModel.graphExtractionTraces.isEmpty {
                Text("暂无记忆准入轨迹。后台 extraction job 运行后会记录 auto-commit、hold、ask 或 failed 的原因。")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(viewModel.graphExtractionTraces) { trace in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(trace.title)
                                .font(.headline)
                            Text(trace.admissionAction?.rawValue ?? "no admission")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(traceOutcomeColor(trace.outcome).opacity(0.15), in: Capsule())
                                .foregroundStyle(traceOutcomeColor(trace.outcome))
                            Spacer()
                            Text(trace.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(trace.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)

                        if let payloadText = tracePayloadText(trace) {
                            DisclosureGroup("trace payload") {
                                Text(payloadText)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .background(.quaternary.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }

            if let error = viewModel.errorMessage {
                Text(error).foregroundStyle(.red)
            }
        }
        .padding()
        .navigationTitle("记忆准入")
        .task {
            viewModel.deferViewUpdate {
                viewModel.reloadGraphExtractionTraces()
            }
        }
    }

    private func tracePayloadText(_ trace: AppGraphExtractionTracePresentation) -> String? {
        var sections: [String] = []
        if let decoderErrorKind = trace.decoderErrorKind {
            sections.append("decoder_error_kind:\n\(decoderErrorKind)")
        }
        if let decoderErrorMessage = trace.decoderErrorMessage {
            sections.append("decoder_error_message:\n\(decoderErrorMessage)")
        }
        if let normalizedJSON = trace.normalizedJSON {
            sections.append("normalized_json:\n\(normalizedJSON)")
        }
        if let rawResponseJSON = trace.rawResponseJSON {
            sections.append("raw_response_json:\n\(rawResponseJSON)")
        }
        if let promptText = trace.promptText {
            sections.append("prompt_text:\n\(promptText)")
        }
        guard !sections.isEmpty else { return nil }
        return sections.joined(separator: "\n\n---\n\n")
    }

    private func traceOutcomeColor(_ outcome: GraphExtractionTraceOutcome) -> Color {
        switch outcome {
        case .committed: return .green
        case .held: return .orange
        case .askUser: return .blue
        case .discarded: return .secondary
        case .failed: return .red
        }
    }
}
