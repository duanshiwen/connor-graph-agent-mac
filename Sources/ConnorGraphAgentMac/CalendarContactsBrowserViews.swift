import SwiftUI
import ConnorGraphCore
import ConnorGraphAppSupport

struct CraftCalendarListPane: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            Text("日历")
                .font(AppListTypography.header)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)

            if viewModel.calendarBrowserPresentation.daySections.isEmpty {
                ContentUnavailableView("暂无日程", systemImage: "calendar", description: Text("添加支持 Calendar capability 的账户后，日程会显示在这里。"))
                    .padding(.top, 80)
            } else {
                CalendarSectionScrollView(
                    sections: viewModel.calendarBrowserPresentation.daySections,
                    selectedID: viewModel.selectedCalendarEventID,
                    onSelect: { viewModel.selectedCalendarEventID = $0 }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct CalendarSectionScrollView: View {
    var sections: [NativeCalendarDaySectionPresentation]
    var selectedID: CalendarEventID?
    var onSelect: (CalendarEventID) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.title)
                            .font(AppListTypography.rowCaption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                        ForEach(section.events) { event in
                            CalendarEventButton(row: event, isSelected: event.id == selectedID, onSelect: { onSelect(event.id) })
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .scrollContentBackground(.hidden)
    }
}

private struct CalendarEventButton: View {
    var row: NativeCalendarEventRowPresentation
    var isSelected: Bool
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 8) {
                Text(row.timeText)
                    .font(AppListTypography.rowCaption)
                    .foregroundStyle(.secondary)
                    .frame(width: 92, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.title)
                        .font(AppListTypography.rowTitle)
                        .foregroundStyle(.primary)
                    if let location = row.location, !location.isEmpty {
                        Text(location)
                            .font(AppListTypography.rowSubtitle)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct CraftContactsListPane: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var query = ""

    private var rows: [NativeContactRowPresentation] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return viewModel.contactsBrowserPresentation.rows }
        return viewModel.contactsBrowserPresentation.rows.filter { row in
            row.displayName.lowercased().contains(normalized) || (row.primaryEmail?.lowercased().contains(normalized) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("联系人")
                .font(AppListTypography.header)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)

            ContactsSearchField(query: $query)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)

            if rows.isEmpty {
                ContentUnavailableView("暂无联系人", systemImage: "person.crop.circle.badge", description: Text("添加支持 Contacts capability 的账户后，联系人会显示在这里。"))
                    .padding(.top, 80)
            } else {
                ContactsRowsScrollView(rows: rows, selectedID: viewModel.selectedContactID, onSelect: { viewModel.selectedContactID = $0 })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct ContactsSearchField: View {
    @Binding var query: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("搜索姓名或邮箱", text: $query)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.62), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AppShellColors.hairline, lineWidth: 1))
    }
}

private struct ContactsRowsScrollView: View {
    var rows: [NativeContactRowPresentation]
    var selectedID: MailContactID?
    var onSelect: (MailContactID) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(rows) { row in
                    ContactRowButton(row: row, isSelected: row.id == selectedID, onSelect: { onSelect(row.id) })
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .scrollContentBackground(.hidden)
    }
}

private struct ContactRowButton: View {
    var row: NativeContactRowPresentation
    var isSelected: Bool
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.displayName)
                    .font(AppListTypography.rowTitle)
                    .foregroundStyle(.primary)
                Text(row.primaryEmail ?? row.organizationName ?? "无邮箱")
                    .font(AppListTypography.rowSubtitle)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct CalendarSourceSettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: AppShellLayout.spaceL) {
            CalendarContactsHeader(title: "日历", subtitle: "轻量日程数据源：列表、详情和 AI 工具管理，不做完整日历客户端。")
            Divider().opacity(0.6)
            if let selected = selectedEventRow {
                VStack(alignment: .leading, spacing: AppShellLayout.spaceM) {
                    Label(selected.title, systemImage: "calendar.badge.clock")
                        .font(AgentChatTypography.title)
                    Text(selected.timeText)
                        .font(AgentChatTypography.meta)
                        .foregroundStyle(.secondary)
                    if let location = selected.location {
                        Text(location).font(AgentChatTypography.meta)
                    }
                }
                .padding(AppShellLayout.spaceXL)
            } else {
                ContentUnavailableView("选择一个日程", systemImage: "calendar", description: Text("从左侧日程列表选择后查看详情。"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppShellColors.detailBackground)
    }

    private var selectedEventRow: NativeCalendarEventRowPresentation? {
        guard let id = viewModel.selectedCalendarEventID else { return nil }
        return viewModel.calendarBrowserPresentation.daySections.flatMap(\.events).first { $0.id == id }
    }
}

struct ContactsSourceSettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: AppShellLayout.spaceL) {
            CalendarContactsHeader(title: "联系人", subtitle: "轻量联系人数据源：列表、搜索和详情，不做 CRM。")
            Divider().opacity(0.6)
            if let selected = selectedContactRow {
                VStack(alignment: .leading, spacing: AppShellLayout.spaceM) {
                    Label(selected.displayName, systemImage: "person.crop.circle")
                        .font(AgentChatTypography.title)
                    if let email = selected.primaryEmail {
                        Text(email).font(AgentChatTypography.meta).textSelection(.enabled)
                    }
                    if let organization = selected.organizationName {
                        Text(organization).font(AgentChatTypography.meta).foregroundStyle(.secondary)
                    }
                }
                .padding(AppShellLayout.spaceXL)
            } else {
                ContentUnavailableView("选择一个联系人", systemImage: "person.crop.circle.badge", description: Text("从左侧联系人列表选择后查看详情。"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppShellColors.detailBackground)
    }

    private var selectedContactRow: NativeContactRowPresentation? {
        guard let id = viewModel.selectedContactID else { return nil }
        return viewModel.contactsBrowserPresentation.rows.first { $0.id == id }
    }
}

private struct CalendarContactsHeader: View {
    var title: String
    var subtitle: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: AppShellLayout.spaceXS) {
                Text(title).font(.system(size: 24, weight: .semibold))
                Text(subtitle).font(AgentChatTypography.meta).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, AppShellLayout.spaceXL)
        .padding(.vertical, AppShellLayout.spaceL)
    }
}
