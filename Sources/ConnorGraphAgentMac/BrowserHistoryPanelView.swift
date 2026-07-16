import SwiftUI
import AppKit
import ConnorGraphAppSupport

// MARK: - History Panel

struct BrowserHistoryPanelView: View {
    @Bindable var model: BrowserFeatureModel
    @State private var clearConfirmation: Bool = false

    private var searchText: Binding<String> {
        Binding(
            get: { model.historySearchQuery },
            set: { model.filterHistory(query: $0) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            searchBar
            Divider()

            if groupedRecords.isEmpty {
                emptyState
            } else {
                historyList
            }

            Divider()
            footerBar
        }
        .frame(width: 300)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(BrowserFloatingTypography.popoverTitle)
                .foregroundStyle(.secondary)
            Text("浏览历史")
                .font(BrowserFloatingTypography.popoverTitle)
            Spacer()
            Button(action: { model.toggleHistoryPanel() }) {
                Image(systemName: "xmark")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.appIcon)
            .help("关闭历史面板")
            .accessibilityLabel("关闭历史面板")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            TextField("搜索网址、标题或正文", text: searchText)
                .textFieldStyle(.plain)
                .font(BrowserFloatingTypography.input)
            if !model.historySearchQuery.isEmpty {
                Button(action: {
                    model.filterHistory(query: "")
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("清空历史搜索")
                .accessibilityLabel("清空历史搜索")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        let isSearching = !model.historySearchQuery.isEmpty

        return VStack(spacing: 8) {
            Spacer()
            Image(systemName: "clock")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text(isSearching ? "没有找到匹配的浏览记录" : "还没有浏览记录")
                .font(BrowserFloatingTypography.hint.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(isSearching ? "换个关键词试试，或者回到浏览器继续打开新的网页。" : "你在康纳同学里打开过的网页会出现在这里。之后可以从历史记录回到资料现场，继续和会话一起工作。")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 18)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - List

    private var groupedRecords: [BrowserHistoryDateGroup] {
        BrowserHistoryGrouper().group(model.filteredHistoryRecords)
    }

    private var historyList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(groupedRecords) { group in
                    sectionHeader(group.label)
                    ForEach(group.records) { record in
                        BrowserHistoryRow(record: record) {
                            model.navigateToHistoryRecord(record)
                        } onDelete: {
                            model.deleteHistoryRecord(record.id)
                        }
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack {
            Text("\(model.filteredHistoryRecords.count) 条记录")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
            Button(action: { clearConfirmation = true }) {
                Text("清空")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .disabled(model.historyRecords.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .confirmationDialog("确认清空所有浏览历史？", isPresented: $clearConfirmation, titleVisibility: .visible) {
            Button("清空所有历史", role: .destructive) {
                model.clearHistory()
                model.filterHistory(query: "")
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作无法撤销。")
        }
    }
}

// MARK: - History Row

private struct BrowserHistoryRow: View {
    var record: BrowserHistoryRecord
    var onTap: () -> Void
    var onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                favicon
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayTitle)
                        .font(BrowserFloatingTypography.pageTitle)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    HStack(spacing: 4) {
                        Text(displayURL)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(record.sessionTitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.10), in: Capsule())
                    Text(timeString)
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isHovering ? Color.secondary.opacity(0.06) : Color.clear)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("删除此记录", role: .destructive, action: onDelete)
            Divider()
            Button("复制网址") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(record.url, forType: .string)
            }
        }
        .help(record.url)
    }

    private var displayTitle: String {
        let title = record.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? (URL(string: record.url)?.host ?? record.url) : title
    }

    private var displayURL: String {
        if let url = URL(string: record.url), let host = url.host {
            return host + (url.path == "/" ? "" : url.path)
        }
        return record.url
    }

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: record.visitedAt)
    }

    @ViewBuilder
    private var favicon: some View {
        AsyncImage(url: faviconURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
            default:
                Image(systemName: "globe")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
            }
        }
        .frame(width: 16, height: 16)
    }

    private var faviconURL: URL? {
        guard let host = URL(string: record.url)?.host else { return nil }
        return URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=32")
    }
}

// MARK: - Date Grouping

struct BrowserHistoryDateGroup: Identifiable {
    let id: String
    let label: String
    let records: [BrowserHistoryRecord]
}

struct BrowserHistoryGrouper {
    private let calendar = Calendar.current

    func group(_ records: [BrowserHistoryRecord]) -> [BrowserHistoryDateGroup] {
        let sorted = records.sorted { $0.visitedAt > $1.visitedAt }
        guard !sorted.isEmpty else { return [] }

        var groups: [(label: String, bucket: Date, records: [BrowserHistoryRecord])] = []

        for record in sorted {
            let bucket = dateBucket(for: record.visitedAt)
            if let index = groups.firstIndex(where: { $0.bucket == bucket }) {
                groups[index].records.append(record)
            } else {
                groups.append((label: labelForBucket(bucket), bucket: bucket, records: [record]))
            }
        }

        return groups.map {
            BrowserHistoryDateGroup(
                id: ISO8601DateFormatter().string(from: $0.bucket),
                label: $0.label,
                records: $0.records
            )
        }
    }

    private func dateBucket(for date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    private func labelForBucket(_ bucket: Date) -> String {
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: bucket, to: today).day ?? 0

        switch days {
        case 0: return "今天"
        case 1: return "昨天"
        case 2...7: return "本周"
        case 8...30: return "本月"
        default:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.timeZone = .autoupdatingCurrent
            formatter.dateFormat = "yyyy年M月"
            return formatter.string(from: bucket)
        }
    }
}

// MARK: - Bookmarks Panel
