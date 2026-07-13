import SwiftUI
import AppKit
import CoreLocation
import CoreServices
import IOKit.pwr_mgt
import UserNotifications
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphSearch
import ConnorGraphAgent
import ConnorGraphStore
import ConnorGraphAppSupport

enum AppMenuPresentation {
    static let fileMenuTitle = "文件"
    static let actionMenuTitle = "操作"
    static let newSessionTitle = "新建会话"
    static let newNoteTitle = "新建笔记"
    static let importNotesTitle = "导入笔记…"
    static let importCenterTitle = "导入中心…"
    static let noteImportWizardWindowID = "note-import-wizard"
    static let noteImportCenterWindowID = "note-import-center"
}

@main
struct ConnorGraphAgentMacApp: App {
    @NSApplicationDelegateAdaptor(ConnorApplicationDelegate.self) private var applicationDelegate
    @StateObject private var viewModel: AppViewModel
    @StateObject private var identityStore: AppUserIdentityStore
    @StateObject private var noteImportModel: NoteImportViewModel
    private let featureFlags: AppFeatureFlags

    init() {
        AppKitSecureCodingWarningMitigator.clearLegacyOpenPanelRootDirectoryState()
        let liveViewModel = AppViewModel.live()
        _viewModel = StateObject(wrappedValue: liveViewModel)
        _identityStore = StateObject(wrappedValue: AppUserIdentityStore())
        _noteImportModel = StateObject(wrappedValue: liveViewModel.makeNoteImportViewModel())
        featureFlags = AppFeatureFlags.load()
    }

    var body: some Scene {
        Window("康纳同学", id: "main") {
            AppShellView(
                viewModel: viewModel,
                identityStore: identityStore,
                noteImportModel: noteImportModel
            )
                .preferredColorScheme(viewModel.appearanceMode.colorScheme)
                .toolbarBackground(.visible, for: .windowToolbar)
                .task {
                    viewModel.startTaskSchedulerTimer()
                    await noteImportModel.recoverPersistedJobs()
                    await identityStore.restoreSession()
                }
        }
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 1180, height: 760)
        .commands {
            NoteImportFileCommands(viewModel: viewModel)

            CommandGroup(replacing: .undoRedo) {
                Button("撤销") {
                    sendResponderAction(#selector(ConnorMenuActionSelectors.undo(_:)))
                }
                .keyboardShortcut("z", modifiers: .command)

                Button("重做") {
                    sendResponderAction(#selector(ConnorMenuActionSelectors.redo(_:)))
                }
                .keyboardShortcut("Z", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .pasteboard) {
                Button("剪切") {
                    sendResponderAction(#selector(NSText.cut(_:)))
                }
                .keyboardShortcut("x", modifiers: .command)

                Button("复制") {
                    sendResponderAction(#selector(NSText.copy(_:)))
                }
                .keyboardShortcut("c", modifiers: .command)

                Button("粘贴") {
                    sendResponderAction(#selector(NSText.paste(_:)))
                }
                .keyboardShortcut("v", modifiers: .command)

                Button("删除") {
                    sendResponderAction(#selector(ConnorMenuActionSelectors.delete(_:)))
                }

                Button("全选") {
                    sendResponderAction(#selector(NSText.selectAll(_:)))
                }
                .keyboardShortcut("a", modifiers: .command)
            }

            CommandGroup(replacing: .textEditing) {
                Button("粘贴并匹配样式") {
                    sendResponderAction(#selector(ConnorMenuActionSelectors.pasteAsPlainText(_:)))
                }
                .keyboardShortcut("V", modifiers: [.command, .option, .shift])

                Divider()

                Button("开始听写…") {
                    sendResponderAction(#selector(ConnorMenuActionSelectors.startDictation(_:)))
                }

                Button("表情与符号") {
                    sendResponderAction(#selector(ConnorMenuActionSelectors.orderFrontCharacterPalette(_:)))
                }
                .keyboardShortcut("e", modifiers: [.control, .command])
            }

            CommandMenu(AppMenuPresentation.actionMenuTitle) {
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

        Window("导入笔记", id: AppMenuPresentation.noteImportWizardWindowID) {
            NoteImportWizardView(
                model: noteImportModel,
                importExecutionEnabled: featureFlags.noteImportEnabled
            )
        }
        .defaultSize(width: 720, height: 560)

        Window("导入中心", id: AppMenuPresentation.noteImportCenterWindowID) {
            NoteImportCenterView(model: noteImportModel)
        }
        .defaultSize(width: 900, height: 620)
    }
}

private struct NoteImportFileCommands: Commands {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(AppMenuPresentation.newSessionTitle) {
                viewModel.performShortcutAction(.newSession)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button(AppMenuPresentation.newNoteTitle) {
                viewModel.newNoteSession()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Divider()

            Button(AppMenuPresentation.importNotesTitle) {
                openWindow(id: AppMenuPresentation.noteImportWizardWindowID)
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])

            Button(AppMenuPresentation.importCenterTitle) {
                openWindow(id: AppMenuPresentation.noteImportCenterWindowID)
            }
        }
    }
}

extension Notification.Name {
    static let connorSessionNotificationActivated = Notification.Name("connorSessionNotificationActivated")
}

@MainActor
private func sendResponderAction(_ selector: Selector) {
    NSApp.sendAction(selector, to: nil, from: nil)
}

@objc
private final class ConnorMenuActionSelectors: NSObject {
    @objc func undo(_ sender: Any?) {}
    @objc func redo(_ sender: Any?) {}
    @objc func delete(_ sender: Any?) {}
    @objc func pasteAsPlainText(_ sender: Any?) {}
    @objc func startDictation(_ sender: Any?) {}
    @objc func orderFrontCharacterPalette(_ sender: Any?) {}
}

@MainActor
private final class ConnorApplicationDelegate: NSObject, NSApplicationDelegate, @preconcurrency UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        registerCurrentApplicationBundleWithLaunchServices()
        if Bundle.main.bundleURL.pathExtension == "app" {
            UNUserNotificationCenter.current().delegate = self
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        orderExistingMainWindowToFront()
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        orderExistingMainWindowToFront()
        return false
    }

    private func registerCurrentApplicationBundleWithLaunchServices() {
        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.pathExtension == "app" else { return }
        let status = LSRegisterURL(bundleURL as CFURL, true)
        if status != noErr {
            NSLog("Connor failed to register app bundle with LaunchServices: status=\(status), path=\(bundleURL.path)")
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let sessionID = userInfo["sessionID"] as? String
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            self.orderExistingMainWindowToFront()
            if let sessionID {
                NotificationCenter.default.post(
                    name: .connorSessionNotificationActivated,
                    object: nil,
                    userInfo: ["sessionID": sessionID]
                )
            }
            completionHandler()
        }
    }

    private func orderExistingMainWindowToFront() {
        let candidate = NSApp.windows.first { window in
            window.isVisible && !window.isMiniaturized && window.canBecomeKey
        } ?? NSApp.windows.first { window in
            !window.isMiniaturized && window.canBecomeKey
        }
        candidate?.makeKeyAndOrderFront(nil)
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
