import SwiftUI
import ConnorGraphCore
import ConnorGraphAgent
import ConnorGraphSearch
import ConnorGraphAppSupport

struct AgentChatView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        HStack(spacing: 0) {
            AgentChatSessionListView(viewModel: viewModel)
                .frame(width: 280)
                .background(Color.black.opacity(0.10))

            Divider()

            AgentChatConversationView(viewModel: viewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Agent Chat")
        .onAppear { viewModel.reloadChatSessions() }
    }
}

private struct AgentChatSessionListView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 12) {
            Button(action: { viewModel.newChatSession() }) {
                Label("New Chat", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            HStack {
                Text("All Sessions")
                    .font(.headline)
                Spacer()
                Button(action: { viewModel.reloadChatSessions() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Reload sessions")
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(viewModel.chatSessions) { session in
                        let row = AgentChatSessionPresentation(session: session)
                        AgentChatSessionRow(
                            row: row,
                            isSelected: session.id == viewModel.selectedChatSessionID
                        ) {
                            viewModel.selectChatSession(session.id)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
    }
}

private struct AgentChatSessionRow: View {
    var row: AgentChatSessionPresentation
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "pin.fill" : "message")
                    .font(.caption)
                    .foregroundStyle(isSelected ? .orange : .secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.title)
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .lineLimit(1)
                    Text(row.relativeUpdatedTime)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct AgentChatConversationView: View {
    @ObservedObject var viewModel: AppViewModel

    private var messageRows: [AgentChatMessagePresentation] {
        AgentChatMessagePresentation.rows(messages: viewModel.transcript, lastContext: viewModel.lastContext)
    }

    var body: some View {
        VStack(spacing: 0) {
            AgentChatConversationHeader(viewModel: viewModel)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if viewModel.transcript.isEmpty {
                            AgentChatEmptyStateView()
                                .frame(maxWidth: .infinity, minHeight: 360)
                        } else {
                            ForEach(messageRows) { row in
                                AgentChatMessageRow(row: row)
                                    .id(row.id)
                            }
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 22)
                }
                .onChange(of: viewModel.transcript.count) { _, _ in
                    if let lastID = viewModel.transcript.last?.id {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            AgentChatComposerView(viewModel: viewModel)
                .padding(12)
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.20))
    }
}

private struct AgentChatConversationHeader: View {
    @ObservedObject var viewModel: AppViewModel

    private var selectedTitle: String {
        viewModel.chatSessions.first(where: { $0.id == viewModel.selectedChatSessionID })?.title ?? "Agent Chat"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedTitle)
                        .font(.headline)
                        .lineLimit(1)
                    Text("Graph-backed conversation workspace")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Reload") { viewModel.reloadChatSessions() }
                Button(viewModel.summarizeChatSessionButtonTitle) {
                    Task { await viewModel.summarizeSelectedChatSession() }
                }
                .disabled(!viewModel.canSummarizeSelectedChatSession)
            }

            if let summary = viewModel.latestChatSummary {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(summary.content)
                            .font(.subheadline)
                            .textSelection(.enabled)
                        if let freshness = viewModel.latestChatSummaryFreshness {
                            Text("Covers \(freshness.coveredMessageCount) / \(freshness.currentMessageCount) messages · Updated \(summary.updatedAt.formatted())")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(viewModel.latestChatSummaryContextMessage)
                            .font(.caption)
                            .foregroundColor(viewModel.latestChatSummaryFreshness?.isFresh == true ? .secondary : .orange)
                        if let message = viewModel.chatSummaryMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    Label("Session summary", systemImage: "text.quote")
                        .font(.caption.weight(.semibold))
                }
                .padding(10)
                .background(.quaternary.opacity(0.20), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }
}

private struct AgentChatEmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("Start a graph-backed conversation")
                .font(.title3.weight(.semibold))
            Text("Ask about your imported graph knowledge. Each assistant turn can expose prompt, context, token budget, and citations.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AgentChatMessageRow: View {
    var row: AgentChatMessagePresentation

    private var isUser: Bool { row.message.role == .user }

    var body: some View {
        HStack(alignment: .top) {
            if isUser { Spacer(minLength: 80) }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(row.roleLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isUser ? .white.opacity(0.90) : .secondary)
                    Text("Turn \(row.turnNumber)")
                        .font(.caption2)
                        .foregroundStyle(isUser ? .white.opacity(0.65) : .secondary)
                    Text(row.message.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(isUser ? .white.opacity(0.65) : .secondary)
                }

                Text(row.message.content)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if row.message.role == .assistant {
                    AgentChatTurnInspectorView(row: row)
                }
            }
            .padding(12)
            .frame(maxWidth: isUser ? 560 : 760, alignment: .leading)
            .background(messageBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isUser ? Color.clear : Color.secondary.opacity(0.12), lineWidth: 1)
            )

            if !isUser { Spacer(minLength: 80) }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    private var messageBackground: Color {
        if isUser { return Color.accentColor.opacity(0.88) }
        return Color(nsColor: .controlBackgroundColor).opacity(0.85)
    }
}

private struct AgentChatTurnInspectorView: View {
    var row: AgentChatMessagePresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let summary = row.turnMetadataSummary {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                    Text(summary)
                    Spacer(minLength: 0)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 10) {
                    if let request = row.currentRequest {
                        MetadataBlock(title: "Current request", text: request)
                    }

                    if !row.citationIDs.isEmpty {
                        MetadataChips(title: "Citations", values: row.citationIDs)
                    }

                    if !row.expandedContextItems.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Cited graph context")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(row.expandedContextItems) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.sourceID)
                                        .font(.caption.weight(.semibold))
                                    Text(item.content)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.quaternary.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }

                    if let prompt = row.promptSnapshotText, !prompt.isEmpty {
                        MetadataBlock(title: "Prompt snapshot", text: prompt, monospaced: true)
                    } else if row.message.promptInspection != nil {
                        Text("No rendered prompt snapshot saved for this turn.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 8)
            } label: {
                Text("Turn information")
                    .font(.caption.weight(.semibold))
            }
            .font(.caption)
        }
    }
}

private struct MetadataBlock: View {
    var title: String
    var text: String
    var monospaced: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(monospaced ? .system(.caption, design: .monospaced) : .caption)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(.quaternary.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

private struct MetadataChips: View {
    var title: String
    var values: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            FlowLikeChips(values: values)
        }
    }
}

private struct FlowLikeChips: View {
    var values: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(values, id: \.self) { value in
                Text(value)
                    .font(.caption2)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
        }
    }
}

private struct AgentChatComposerView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                TextField("Ask the graph-backed agent", text: $viewModel.chatInput, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.accentColor.opacity(0.65), lineWidth: 1)
                    )
                    .onSubmit { Task { await viewModel.submitChat() } }

                Button(action: { Task { await viewModel.submitChat() } }) {
                    Image(systemName: "arrow.up")
                        .font(.headline)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(Circle())
                .disabled(viewModel.chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            HStack(spacing: 8) {
                Label("graph context", systemImage: "link")
                if let inspection = viewModel.lastPromptInspection {
                    Text("~\(inspection.estimatedPromptTokenCount) tokens")
                    Text(AgentChatMessagePresentation.budgetStatusText(inspection.promptBudgetStatus))
                        .foregroundStyle(promptBudgetStatusColor(inspection.promptBudgetStatus))
                }
                Spacer()
                Text("Return to send")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
    }

    private func promptBudgetStatusColor(_ status: AgentPromptBudgetStatus) -> Color {
        switch status {
        case .safe: return .secondary
        case .warning: return .orange
        case .over: return .red
        }
    }
}
