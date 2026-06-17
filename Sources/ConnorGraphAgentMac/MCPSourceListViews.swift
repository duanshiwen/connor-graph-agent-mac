import SwiftUI
import ConnorGraphAppSupport

struct CraftSourceListPane: View {
    @ObservedObject var viewModel: AppViewModel

    private var presentation: SourceRuntimeUIPresentation {
        SourceRuntimeUIPresentation.build(
            sources: viewModel.sourceRuntimeConfigurations,
            healthRecords: viewModel.sourceRuntimeHealthRecords,
            auditRecords: viewModel.sourceRuntimeAuditRecordsBySource.values.flatMap { $0 }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            SourceListHeader(onRefresh: viewModel.reloadSourceRuntimeConfigurations)

            if presentation.cards.isEmpty {
                SourceListEmptyState()
            } else {
                List(presentation.cards) { card in
                    MCPSourceRow(
                        card: card,
                        isSelected: card.id == viewModel.selectedSourceRuntimeCardID,
                        onSelect: { viewModel.selectSourceRuntimeCard(card.id) }
                    )
                    .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            guard viewModel.sourceRuntimeConfigurations.isEmpty else { return }
            viewModel.deferViewUpdate {
                viewModel.reloadSourceRuntimeConfigurations()
            }
        }
    }
}

private struct SourceListHeader: View {
    var onRefresh: () -> Void

    var body: some View {
        ZStack {
            Text("MCP")
                .font(AppListTypography.header)
                .frame(maxWidth: .infinity, alignment: .center)
            HStack {
                Spacer()
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12.5, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
                .help("刷新 MCP Sources")
                .accessibilityLabel("刷新 MCP Sources")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }
}

private struct SourceListEmptyState: View {
    var body: some View {
        ContentUnavailableView(
            "暂无 MCP Source",
            systemImage: "server.rack",
            description: Text("添加并测试 MCP source 后，它会显示在这里。")
        )
        .padding(.top, 80)
    }
}

private struct MCPSourceRow: View {
    var card: SourceRuntimeUICard
    var isSelected: Bool
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(rowColor.opacity(isSelected ? 0.20 : 0.12))
                    Image(systemName: "server.rack")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(rowColor)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Circle().fill(rowColor).frame(width: 7, height: 7)
                        Text(card.title)
                            .font(isSelected ? AppListTypography.rowTitleSelected : AppListTypography.rowTitle)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    Text(card.transportLabel)
                        .font(AppListTypography.rowSubtitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 6) {
                        SourceMiniPill(text: card.statusLabel, color: rowColor)
                        SourceMiniPill(text: card.toolCountLabel, color: .secondary)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.24) : Color.clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var rowColor: Color {
        switch card.severity {
        case .success: .green
        case .warning: .orange
        case .error: .red
        case .info: .blue
        }
    }
}

private struct SourceMiniPill: View {
    var text: String
    var color: Color

    var body: some View {
        Text(text)
            .font(AppListTypography.rowCaption)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .frame(height: 18)
            .foregroundStyle(color)
            .background(color.opacity(0.11), in: Capsule())
    }
}
