import AppKit
import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore
import ConnorGraphAppSupport
@testable import ConnorGraphAgentMac

@MainActor
struct AppGlobalSearchTests {
    @Test func updateGlobalSearchQueryShowsAndClearsOverlay() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        fixture.viewModel.sessionSearchQuery = "existing session filter"
        fixture.viewModel.updateGlobalSearchQuery(" quarterly planning ")

        #expect(fixture.viewModel.globalSearchQuery == " quarterly planning ")
        #expect(fixture.viewModel.sessionSearchQuery == "existing session filter")
        #expect(fixture.viewModel.isGlobalSearchOverlayPresented)
        #expect(fixture.viewModel.globalSearchPreviewState.query == "quarterly planning")
        #expect(!fixture.viewModel.globalSearchPreviewState.isLoading)

        fixture.viewModel.clearGlobalSearch()

        #expect(fixture.viewModel.globalSearchQuery.isEmpty)
        #expect(fixture.viewModel.sessionSearchQuery == "existing session filter")
        #expect(!fixture.viewModel.isGlobalSearchOverlayPresented)
        #expect(fixture.viewModel.globalSearchPreviewState == .empty)
    }

    @Test func focusRestoresOverlayForExistingQueryAndBlurDismissesIt() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        fixture.viewModel.updateGlobalSearchQuery("invoice")
        fixture.viewModel.dismissGlobalSearchOverlay()

        #expect(!fixture.viewModel.isGlobalSearchOverlayPresented)

        fixture.viewModel.activateGlobalSearchField()

        #expect(fixture.viewModel.isGlobalSearchFieldFocused)
        #expect(fixture.viewModel.isGlobalSearchOverlayPresented)

        fixture.viewModel.deactivateGlobalSearchField()

        #expect(!fixture.viewModel.isGlobalSearchFieldFocused)
        #expect(!fixture.viewModel.isGlobalSearchOverlayPresented)
        #expect(fixture.viewModel.globalSearchQuery == "invoice")
    }

    @Test func showAllGlobalSearchResultsNavigatesToSourceLists() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        fixture.viewModel.updateGlobalSearchQuery("invoice")
        fixture.viewModel.showAllGlobalSearchResults(kind: .mail)

        #expect(fixture.viewModel.selection == .mail)
        #expect(!fixture.viewModel.isGlobalSearchOverlayPresented)

        fixture.viewModel.updateGlobalSearchQuery("standup")
        fixture.viewModel.showAllGlobalSearchResults(kind: .calendar)

        #expect(fixture.viewModel.selection == .calendar)

        fixture.viewModel.updateGlobalSearchQuery("swift")
        fixture.viewModel.showAllGlobalSearchResults(kind: .rss)

        #expect(fixture.viewModel.selection == .rss)
    }

    private func makeFixture() throws -> Fixture {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-app-global-search-\(UUID().uuidString)", isDirectory: true)
        let paths = AppStoragePaths.resolving(applicationSupportBaseDirectory: root)
        try paths.ensureDirectoryHierarchy(fileManager: .default)
        let graphRepository = try AppGraphRepository.bootstrap(paths: paths)
        let viewModel = AppViewModel(
            entities: [],
            statements: [],
            observeLogEntries: [],
            repository: graphRepository,
            databasePath: paths.databaseURL.path,
            storagePaths: paths
        )
        return Fixture(root: root, viewModel: viewModel)
    }

    private struct Fixture {
        var root: URL
        var viewModel: AppViewModel

        func cleanup() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
