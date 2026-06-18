import SwiftUI
import AppKit
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphSearch
import ConnorGraphAgent
import ConnorGraphStore
import ConnorGraphAppSupport

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
