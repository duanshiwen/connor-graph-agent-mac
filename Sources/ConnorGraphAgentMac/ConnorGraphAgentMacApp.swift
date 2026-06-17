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
    @NSApplicationDelegateAdaptor(ConnorMenuBarDelegate.self) private var menuBarDelegate
    @StateObject private var viewModel: AppViewModel
    @StateObject private var updateController: ConnorReleaseUpdateController

    init() {
        AppKitSecureCodingWarningMitigator.clearLegacyOpenPanelRootDirectoryState()
        _viewModel = StateObject(wrappedValue: AppViewModel.live())
        _updateController = StateObject(wrappedValue: ConnorReleaseUpdateController())
    }

    var body: some Scene {
        WindowGroup {
            AppShellView(viewModel: viewModel)
                .environmentObject(updateController)
                .preferredColorScheme(viewModel.appearanceMode.colorScheme)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updateController.checkForUpdates()
                }
            }
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .saveItem) {}
            CommandGroup(replacing: .importExport) {}
            CommandGroup(replacing: .printItem) {}
            CommandGroup(replacing: .help) {}

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
private final class ConnorMenuBarDelegate: NSObject, NSApplicationDelegate {
    private let hiddenTopLevelMenuTitles: Set<String> = [
        "Edit", "View", "Window", "Help",
        "编辑", "显示", "窗口", "帮助"
    ]
    private var menuObservers: [NSObjectProtocol] = []
    private var pruneWorkItem: DispatchWorkItem?
    private var isPruningMenus = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenuPruneObserversIfNeeded()
        scheduleStandardMenuPrune()
        scheduleStandardMenuPrune(after: 0.1)
        scheduleStandardMenuPrune(after: 0.5)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        scheduleStandardMenuPrune()
    }

    func applicationWillUpdate(_ notification: Notification) {
        scheduleStandardMenuPrune()
    }

    func applicationDidUpdate(_ notification: Notification) {
        scheduleStandardMenuPrune()
    }

    func applicationWillTerminate(_ notification: Notification) {
        for observer in menuObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        menuObservers.removeAll()
        pruneWorkItem?.cancel()
        pruneWorkItem = nil
    }

    private func installMenuPruneObserversIfNeeded() {
        guard menuObservers.isEmpty else { return }
        let center = NotificationCenter.default
        let notifications: [Notification.Name] = [
            NSMenu.didAddItemNotification,
            NSMenu.didChangeItemNotification,
            NSMenu.didRemoveItemNotification
        ]
        menuObservers = notifications.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.scheduleStandardMenuPrune()
                }
            }
        }
    }

    private func scheduleStandardMenuPrune(after delay: TimeInterval = 0) {
        guard !isPruningMenus else { return }
        pruneWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.pruneStandardMenusNow()
        }
        pruneWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func pruneStandardMenusNow() {
        guard !isPruningMenus else { return }
        guard let mainMenu = NSApp.mainMenu else {
            scheduleStandardMenuPrune(after: 0.05)
            return
        }
        isPruningMenus = true
        defer { isPruningMenus = false }
        for item in mainMenu.items.reversed() where hiddenTopLevelMenuTitles.contains(item.title) {
            mainMenu.removeItem(item)
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
