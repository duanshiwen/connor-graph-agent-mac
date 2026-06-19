import SwiftUI

struct SettingsCalendarSection: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        SettingsGroup(title: "日历能力") {
            SettingsValueRow(title: "定位", value: "轻量日程数据源")
            SettingsValueRow(title: "当前事件", value: "\(viewModel.calendarBrowserPresentation.eventCount) 个")
            Text("Calendar 与 Mail/Contacts 共享 Connected Account 能力发现，但不复制完整日历客户端、月视图、周视图或复杂 recurrence 编辑器。")
                .font(SettingsListTypography.rowCaption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SettingsContactsSection: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        SettingsGroup(title: "联系人能力") {
            SettingsValueRow(title: "定位", value: "轻量联系人数据源")
            SettingsValueRow(title: "当前联系人", value: "\(viewModel.contactsBrowserPresentation.rows.count) 个")
            Text("Contacts 提供列表、搜索和详情能力，不做 CRM；写入仍应经过明确 approval。")
                .font(SettingsListTypography.rowCaption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
