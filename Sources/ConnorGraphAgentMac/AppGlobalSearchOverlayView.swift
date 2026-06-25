import SwiftUI
import ConnorGraphCore

struct AppGlobalSearchOverlayView: View {
    @ObservedObject var viewModel: AppViewModel

    private var state: GlobalSearchPreviewState { viewModel.globalSearchPreviewState }
    private var query: String { viewModel.globalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            actionRows
            Divider()
            resultSection(kind: .mail, results: state.mailResults)
            resultSection(kind: .calendar, results: state.calendarResults)
            resultSection(kind: .rss, results: state.rssResults)
            if let errorMessage = state.errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .padding(.top, 2)
            }
        }
        .padding(12)
        .frame(width: 680, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 14)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkle.magnifyingglass")
                .foregroundStyle(Color.accentColor)
            Text("搜索或发起：")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(query)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Spacer()
            if state.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var actionRows: some View {
        VStack(spacing: 6) {
            GlobalSearchActionRow(kind: .newChat, query: query) {
                viewModel.performGlobalSearchNewChat()
            }
            GlobalSearchActionRow(kind: .webSearch, query: query) {
                viewModel.performGlobalSearchWebSearch()
            }
        }
    }

    private func resultSection(kind: GlobalSearchSectionKind, results: [NativeSearchResult]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(kind.title)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button("查看全部") {
                    viewModel.showAllGlobalSearchResults(kind: kind)
                }
                .font(.system(size: 11, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .disabled(query.isEmpty)
            }

            if results.isEmpty {
                Text(kind.emptyTitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 22)
            } else {
                VStack(spacing: 4) {
                    ForEach(results.prefix(3)) { result in
                        Button {
                            viewModel.openGlobalSearchResult(result)
                        } label: {
                            GlobalSearchResultRow(result: result)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct GlobalSearchActionRow: View {
    var kind: GlobalSearchActionKind
    var query: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .font(.system(size: 12.5, weight: .semibold))
                    Text(kind.subtitle(for: query))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "return")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .opacity(kind == .newChat ? 1 : 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct GlobalSearchResultRow: View {
    var result: NativeSearchResult

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 18)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(result.title.isEmpty ? "无标题" : result.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    if !result.resultTimeLabel.isEmpty {
                        Text(result.resultTimeLabel)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                if !result.snippet.isEmpty {
                    Text(result.snippet)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.45), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var iconName: String {
        switch result.sourceKind {
        case .mail: "envelope"
        case .calendar: "calendar"
        case .rss: "dot.radiowaves.left.and.right"
        }
    }

    private var iconColor: Color {
        switch result.sourceKind {
        case .mail: .blue
        case .calendar: .purple
        case .rss: .orange
        }
    }
}
