import AppKit
import Testing
@testable import ConnorGraphAgentMac

@MainActor
@Suite("App ViewModel Dock badge")
struct AppViewModelDockBadgeTests {
    @Test("Badge update safely skips before NSApplication exists")
    func skipsMissingApplication() {
        AppViewModel.applyDockBadge(count: 3, application: nil)
    }

    @Test("Badge update applies and clears on a live application")
    func appliesAndClearsBadge() {
        let application = NSApplication.shared
        let originalBadge = application.dockTile.badgeLabel
        defer { application.dockTile.badgeLabel = originalBadge }

        AppViewModel.applyDockBadge(count: 3, application: application)
        #expect(application.dockTile.badgeLabel == "3")

        AppViewModel.applyDockBadge(count: 0, application: application)
        #expect(application.dockTile.badgeLabel == nil)
    }
}
