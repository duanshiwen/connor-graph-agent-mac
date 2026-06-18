import SwiftUI
import AppKit
import CoreLocation
import IOKit.pwr_mgt
import UserNotifications
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphSearch
import ConnorGraphAgent
import ConnorGraphStore
import ConnorGraphAppSupport

@main
struct ConnorGraphAgentMacApp: App {
    @NSApplicationDelegateAdaptor(ConnorApplicationDelegate.self) private var applicationDelegate
    @StateObject private var viewModel: AppViewModel

    init() {
        AppKitSecureCodingWarningMitigator.clearLegacyOpenPanelRootDirectoryState()
        _viewModel = StateObject(wrappedValue: AppViewModel.live())
    }

    var body: some Scene {
        WindowGroup("康纳同学") {
            AppShellView(viewModel: viewModel)
                .preferredColorScheme(viewModel.appearanceMode.colorScheme)
                .toolbarBackground(.visible, for: .windowToolbar)
        }
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandMenu("指示") {
                Button("新建会话") {
                    viewModel.performShortcutAction(.newSession)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("切换浏览器") {
                    viewModel.performShortcutAction(.toggleBrowser)
                }
                .keyboardShortcut("b", modifiers: .command)

                Button("聚焦搜索") {
                    viewModel.performShortcutAction(.focusTopSearch)
                }
                .keyboardShortcut("f", modifiers: .command)

                Divider()

                Button("打开设置") {
                    viewModel.performShortcutAction(.openSettings)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

@MainActor
private final class ConnorApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(localizeMenuBeforeTracking(_:)),
            name: NSMenu.didBeginTrackingNotification,
            object: nil
        )
        normalizeMenusSoon()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        normalizeMenusSoon()
    }

    func applicationDidUpdate(_ notification: Notification) {
        normalizeMenusSoon()
    }

    private func normalizeMenusSoon() {
        DispatchQueue.main.async { [weak self] in
            self?.normalizeMenus()
        }
    }

    private func normalizeMenus() {
        guard let mainMenu = NSApp.mainMenu else { return }
        localizeApplicationMenu(in: mainMenu)
        localizeTopLevelStandardMenus(in: mainMenu)
        localizeEditMenu(in: mainMenu)
        ConnorMenuLocalizer.localizeMenuTree(mainMenu)
    }

    @objc private func localizeMenuBeforeTracking(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu else { return }
        ConnorMenuLocalizer.localizeMenuTree(menu)
    }

    private func localizeApplicationMenu(in mainMenu: NSMenu) {
        guard let appMenu = mainMenu.items.first?.submenu else { return }
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? ProcessInfo.processInfo.processName
        for item in appMenu.items {
            switch item.action {
            case #selector(NSApplication.orderFrontStandardAboutPanel(_:)):
                item.title = "关于\(appName)"
            case Selector(("showSettingsWindow:")), Selector(("showPreferencesWindow:")):
                item.title = "设置…"
            case #selector(NSApplication.hide(_:)):
                item.title = "隐藏\(appName)"
            case #selector(NSApplication.hideOtherApplications(_:)):
                item.title = "隐藏其它"
            case #selector(NSApplication.unhideAllApplications(_:)):
                item.title = "全部显示"
            case #selector(NSApplication.terminate(_:)):
                item.title = "退出\(appName)"
            default:
                if item.title == "Services" || item.title == "服务" {
                    item.title = "服务"
                }
            }
        }
    }

    private func localizeTopLevelStandardMenus(in mainMenu: NSMenu) {
        for item in mainMenu.items {
            switch item.title {
            case "File":
                item.title = "文件"
                item.submenu?.title = "文件"
            case "Edit":
                item.title = "编辑"
                item.submenu?.title = "编辑"
            case "View":
                item.title = "显示"
                item.submenu?.title = "显示"
            case "Window":
                item.title = "窗口"
                item.submenu?.title = "窗口"
            case "Help":
                item.title = "帮助"
                item.submenu?.title = "帮助"
            default:
                break
            }
        }
    }

    private func localizeEditMenu(in mainMenu: NSMenu) {
        guard let editMenuItem = mainMenu.items.first(where: { $0.title == "Edit" || $0.title == "编辑" }) else { return }
        editMenuItem.title = "编辑"
        guard let editMenu = editMenuItem.submenu else { return }
        editMenu.title = "编辑"
        for item in editMenu.items {
            switch item.action {
            case Selector(("undo:")):
                item.title = "撤销"
            case Selector(("redo:")):
                item.title = "重做"
            case #selector(NSText.cut(_:)):
                item.title = "剪切"
            case #selector(NSText.copy(_:)):
                item.title = "复制"
            case #selector(NSText.paste(_:)):
                item.title = "粘贴"
            case #selector(NSText.selectAll(_:)):
                item.title = "全选"
            case Selector(("delete:")):
                item.title = "删除"
            case Selector(("pasteAsPlainText:")):
                item.title = "粘贴并匹配样式"
            case Selector(("startDictation:")):
                item.title = "开始听写…"
            case Selector(("orderFrontCharacterPalette:")):
                item.title = "表情与符号"
            default:
                break
            }
        }
    }

    private func localizeStandardMenuItems(in menu: NSMenu) {
        let titleMap: [String: String] = [
            "New": "新建",
            "Open…": "打开…",
            "Open Recent": "打开最近使用",
            "Close": "关闭",
            "Save": "保存",
            "Save As…": "另存为…",
            "Duplicate": "复制副本",
            "Rename…": "重命名…",
            "Move To…": "移动到…",
            "Revert To": "复原到",
            "Page Setup…": "页面设置…",
            "Print…": "打印…",
            "Undo": "撤销",
            "Redo": "重做",
            "Cut": "剪切",
            "Copy": "复制",
            "Paste": "粘贴",
            "Paste and Match Style": "粘贴并匹配样式",
            "Delete": "删除",
            "Select All": "全选",
            "Find": "查找",
            "Find…": "查找…",
            "Find and Replace…": "查找并替换…",
            "Find Next": "查找下一个",
            "Find Previous": "查找上一个",
            "Use Selection for Find": "使用所选内容查找",
            "Spelling and Grammar": "拼写和语法",
            "Show Spelling and Grammar": "显示拼写和语法",
            "Check Document Now": "立即检查文档",
            "Check Spelling While Typing": "输入时检查拼写",
            "Check Grammar With Spelling": "随拼写检查语法",
            "Correct Spelling Automatically": "自动校正拼写",
            "Substitutions": "替换",
            "Show Substitutions": "显示替换",
            "Smart Copy/Paste": "智能复制/粘贴",
            "Smart Quotes": "智能引号",
            "Smart Dashes": "智能破折号",
            "Smart Links": "智能链接",
            "Data Detectors": "数据检测器",
            "Text Replacement": "文本替换",
            "Transformations": "转换",
            "Make Upper Case": "转为大写",
            "Make Lower Case": "转为小写",
            "Capitalize": "首字母大写",
            "Speech": "语音",
            "Start Speaking": "开始朗读",
            "Stop Speaking": "停止朗读",
            "Start Dictation…": "开始听写…",
            "Emoji & Symbols": "表情与符号",
            "Show Toolbar": "显示工具栏",
            "Hide Toolbar": "隐藏工具栏",
            "Customize Toolbar…": "自定工具栏…",
            "Show Sidebar": "显示边栏",
            "Hide Sidebar": "隐藏边栏",
            "Enter Full Screen": "进入全屏幕",
            "Exit Full Screen": "退出全屏幕",
            "Minimize": "最小化",
            "Zoom": "缩放",
            "Bring All to Front": "全部前置",
            "Show Previous Tab": "显示上一个标签页",
            "Show Next Tab": "显示下一个标签页",
            "Move Tab to New Window": "将标签页移到新窗口",
            "Merge All Windows": "合并所有窗口",
            "Search": "搜索",
            "Help": "帮助",
            "Services": "服务"
        ]

        for item in menu.items {
            if let localized = titleMap[item.title] {
                item.title = localized
            }
            if let submenu = item.submenu {
                if let localized = titleMap[submenu.title] {
                    submenu.title = localized
                }
                ConnorMenuLocalizer.localizeMenuTree(submenu)
            }
        }
    }
}

@MainActor
enum ConnorMenuLocalizer {
    static func localizeMenuTree(_ menu: NSMenu) {
        localize(menu)
        for item in menu.items {
            localize(item)
            if let submenu = item.submenu {
                localizeMenuTree(submenu)
            }
        }
    }

    private static func localize(_ menu: NSMenu) {
        if let localized = localizedTitle(for: menu.title) {
            menu.title = localized
        }
    }

    private static func localize(_ item: NSMenuItem) {
        if let localized = localizedTitle(for: item.title) {
            item.title = localized
        }
    }

    private static func localizedTitle(for title: String) -> String? {
        if title.hasPrefix("New "), title.hasSuffix(" Window") {
            let windowName = title
                .dropFirst("New ".count)
                .dropLast(" Window".count)
            return "新建\(windowName)窗口"
        }

        return titleMap[title]
    }

    private static let titleMap: [String: String] = [
        "File": "文件",
        "Edit": "编辑",
        "View": "显示",
        "Window": "窗口",
        "Help": "帮助",
        "New": "新建",
        "Open…": "打开…",
        "Open Recent": "打开最近使用",
        "Close": "关闭",
        "Save": "保存",
        "Save As…": "另存为…",
        "Duplicate": "复制副本",
        "Rename…": "重命名…",
        "Move To…": "移动到…",
        "Revert To": "复原到",
        "Page Setup…": "页面设置…",
        "Print…": "打印…",
        "Undo": "撤销",
        "Redo": "重做",
        "Cut": "剪切",
        "Copy": "复制",
        "Paste": "粘贴",
        "Delete": "删除",
        "Select All": "全选",
        "Paste and Match Style": "粘贴并匹配样式",
        "AutoFill": "自动填充",
        "Start Dictation…": "开始听写…",
        "Emoji & Symbols": "表情与符号",
        "Find": "查找",
        "Find…": "查找…",
        "Find and Replace…": "查找并替换…",
        "Find Next": "查找下一个",
        "Find Previous": "查找上一个",
        "Use Selection for Find": "使用所选内容查找",
        "Spelling and Grammar": "拼写和语法",
        "Show Spelling and Grammar": "显示拼写和语法",
        "Check Document Now": "立即检查文档",
        "Check Spelling While Typing": "输入时检查拼写",
        "Check Grammar With Spelling": "随拼写检查语法",
        "Correct Spelling Automatically": "自动校正拼写",
        "Substitutions": "替换",
        "Show Substitutions": "显示替换",
        "Smart Copy/Paste": "智能复制/粘贴",
        "Smart Quotes": "智能引号",
        "Smart Dashes": "智能破折号",
        "Smart Links": "智能链接",
        "Data Detectors": "数据检测器",
        "Text Replacement": "文本替换",
        "Transformations": "转换",
        "Make Upper Case": "转为大写",
        "Make Lower Case": "转为小写",
        "Capitalize": "首字母大写",
        "Speech": "语音",
        "Start Speaking": "开始朗读",
        "Stop Speaking": "停止朗读",
        "Show Toolbar": "显示工具栏",
        "Hide Toolbar": "隐藏工具栏",
        "Customize Toolbar…": "自定工具栏…",
        "Show Sidebar": "显示边栏",
        "Hide Sidebar": "隐藏边栏",
        "Enter Full Screen": "进入全屏幕",
        "Exit Full Screen": "退出全屏幕",
        "Minimize": "最小化",
        "Zoom": "缩放",
        "Bring All to Front": "全部前置",
        "Show Previous Tab": "显示上一个标签页",
        "Show Next Tab": "显示下一个标签页",
        "Move Tab to New Window": "将标签页移到新窗口",
        "Merge All Windows": "合并所有窗口",
        "Search": "搜索",
        "Services": "服务"
    ]
}

private enum AppKitSecureCodingWarningMitigator {
    static func clearLegacyOpenPanelRootDirectoryState(userDefaults: UserDefaults = .standard) {
        // NSOpenPanel can persist the last root directory as an AppKit bookmark/archive
        // under this key. On newer macOS builds that legacy archive may be decoded
        // through an overly broad NSObject allowed-class list inside AppKit/XPC,
        // producing a console warning that is expected to become a future error.
        // Connor stores its own runtime settings as JSON, so this system panel cache
        // is not required for app correctness and is safe to discard at launch.
        userDefaults.removeObject(forKey: "NSOSPLastRootDirectory")
    }
}
