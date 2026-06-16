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
    @StateObject private var viewModel = AppViewModel.live()

    init() {
        AppKitSecureCodingWarningMitigator.clearLegacyOpenPanelRootDirectoryState()
    }

    var body: some Scene {
        WindowGroup {
            AppShellView(viewModel: viewModel)
                .preferredColorScheme(viewModel.appearanceMode.colorScheme)
        }
        .commands {
            CommandMenu("康纳同学") {
                Button("新建聊天") {
                    viewModel.performShortcutAction(.newSession)
                }
                .keyboardShortcut(viewModel.shortcut(for: .newSession).keyEquivalent, modifiers: viewModel.shortcut(for: .newSession).eventModifierFlags)

                Button("显示 / 隐藏浏览器") {
                    viewModel.performShortcutAction(.toggleBrowser)
                }
                .keyboardShortcut(viewModel.shortcut(for: .toggleBrowser).keyEquivalent, modifiers: viewModel.shortcut(for: .toggleBrowser).eventModifierFlags)

                Button("聚焦顶部搜索") {
                    viewModel.performShortcutAction(.focusTopSearch)
                }
                .keyboardShortcut(viewModel.shortcut(for: .focusTopSearch).keyEquivalent, modifiers: viewModel.shortcut(for: .focusTopSearch).eventModifierFlags)

                Button("打开设置") {
                    viewModel.performShortcutAction(.openSettings)
                }
                .keyboardShortcut(viewModel.shortcut(for: .openSettings).keyEquivalent, modifiers: viewModel.shortcut(for: .openSettings).eventModifierFlags)
            }
        }
    }
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
