import AppKit
import Testing
@testable import ConnorGraphAgentMac

@MainActor
@Suite("Settings Section Message Scope Tests")
struct SettingsSectionMessageScopeTests {
    @Test func sectionMessageIsVisibleOnlyForOwningSection() {
        var store = SettingsSectionMessageStore()

        store.set("已同步本机日历：3 个日历，12 个日程", for: .calendar)

        #expect(store.message(for: .calendar) == "已同步本机日历：3 个日历，12 个日程")
        #expect(store.message(for: .ai) == nil)
        #expect(store.message(for: .mail) == nil)
    }

    @Test func clearingOneSectionDoesNotClearOtherSections() {
        var store = SettingsSectionMessageStore()

        store.set("已同步本机日历：3 个日历，12 个日程", for: .calendar)
        store.set("已添加邮件账户：诗闻", for: .mail)
        store.clear(for: .calendar)

        #expect(store.message(for: .calendar) == nil)
        #expect(store.message(for: .mail) == "已添加邮件账户：诗闻")
    }

    @Test func blankMessagesAreTreatedAsClears() {
        var store = SettingsSectionMessageStore()

        store.set("已保存。", for: .app)
        store.set("   ", for: .app)

        #expect(store.message(for: .app) == nil)
    }

    @Test func appViewModelReturnsOnlyCurrentSectionMessages() {
        _ = NSApplication.shared
        let viewModel = AppViewModel(
            entities: [],
            statements: [],
            observeLogEntries: []
        )

        viewModel.setSettingsMessage("已同步本机日历：3 个日历，12 个日程", for: .calendar)
        viewModel.setSettingsMessage("已添加邮件账户：诗闻", for: .mail)

        viewModel.selectSettingsSection(.ai)
        #expect(viewModel.settingsMessage(for: viewModel.selectedSettingsSection) == nil)

        viewModel.selectSettingsSection(.calendar)
        #expect(viewModel.settingsMessage(for: viewModel.selectedSettingsSection) == "已同步本机日历：3 个日历，12 个日程")

        viewModel.selectSettingsSection(.mail)
        #expect(viewModel.settingsMessage(for: viewModel.selectedSettingsSection) == "已添加邮件账户：诗闻")
    }
}
