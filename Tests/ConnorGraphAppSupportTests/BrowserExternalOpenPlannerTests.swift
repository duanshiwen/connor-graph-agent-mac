import Foundation
import Testing
import ConnorGraphAppSupport

@Suite("Browser External Open Planner Tests")
struct BrowserExternalOpenPlannerTests {
    @Test func createsFirstTabWhenBrowserHasNoTabs() {
        let planner = BrowserExternalOpenPlanner()
        let snapshot = AppBrowserStateSnapshot(tabs: [], selectedTabID: nil)

        let planned = planner.open(urlString: "https://example.com/new", in: snapshot)

        #expect(planned.tabs.count == 1)
        #expect(planned.selectedTabID == planned.tabs.first?.id)
        #expect(planned.tabs.first?.initialURLString == "https://example.com/new")
        #expect(planned.tabs.first?.currentURLString == "https://example.com/new")
    }

    @Test func appendsSelectedTabWhenBrowserAlreadyHasTabs() {
        let planner = BrowserExternalOpenPlanner()
        let existingID = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
        let snapshot = AppBrowserStateSnapshot(
            tabs: [
                AppBrowserTabSnapshot(
                    id: existingID,
                    initialURLString: "https://example.com/old",
                    title: "Old",
                    currentURLString: "https://example.com/old"
                )
            ],
            selectedTabID: existingID
        )

        let planned = planner.open(urlString: "https://example.com/new", in: snapshot)

        #expect(planned.tabs.count == 2)
        #expect(planned.tabs.first?.id == existingID)
        #expect(planned.tabs.last?.initialURLString == "https://example.com/new")
        #expect(planned.tabs.last?.currentURLString == "https://example.com/new")
        #expect(planned.selectedTabID == planned.tabs.last?.id)
    }

    @Test func clearsSelectionPopoverWhenOpeningExternalLink() {
        let planner = BrowserExternalOpenPlanner()
        let existingID = UUID(uuidString: "00000000-0000-0000-0000-000000000021")!
        let threadID = UUID(uuidString: "00000000-0000-0000-0000-000000000022")!
        let snapshot = AppBrowserStateSnapshot(
            tabs: [AppBrowserTabSnapshot(id: existingID, initialURLString: "https://old.example", currentURLString: "https://old.example")],
            selectedTabID: existingID,
            selectionPopover: AppBrowserSelectionPopoverSnapshot(
                tabID: existingID,
                pageURL: "https://old.example",
                pageTitle: "Old",
                pageText: "",
                selectedText: "text",
                rect: AppBrowserSelectionRect(x: 1, y: 2, width: 3, height: 4),
                threadID: threadID
            )
        )

        let planned = planner.open(urlString: "https://new.example", in: snapshot)

        #expect(planned.selectionPopover == nil)
    }
}
