import SwiftUI
import AppKit
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphSearch
import ConnorGraphAgent
import ConnorGraphStore
import ConnorGraphAppSupport

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

