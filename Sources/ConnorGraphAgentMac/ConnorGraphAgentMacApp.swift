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
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .saveItem) {}
            CommandGroup(replacing: .importExport) {}
            CommandGroup(replacing: .printItem) {}
            CommandGroup(replacing: .help) {}

            CommandMenu("指示") {}
        }
    }
}

private final class ConnorMenuBarDelegate: NSObject, NSApplicationDelegate {
    private let hiddenTopLevelMenuTitles: Set<String> = [
        "Edit", "View", "Window", "Help",
        "编辑", "显示", "窗口", "帮助"
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        pruneStandardMenus()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        pruneStandardMenus()
    }

    private func pruneStandardMenus() {
        DispatchQueue.main.async { [hiddenTopLevelMenuTitles] in
            guard let mainMenu = NSApp.mainMenu else { return }
            for item in mainMenu.items.reversed() where hiddenTopLevelMenuTitles.contains(item.title) {
                mainMenu.removeItem(item)
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
