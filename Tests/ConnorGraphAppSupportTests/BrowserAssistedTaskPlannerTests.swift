import Foundation
import Testing
import ConnorGraphAppSupport

@Suite("Browser Assisted Task Planner Tests")
struct BrowserAssistedTaskPlannerTests {
    @Test func backgroundSearchOpensSelectedTabWithoutRevealingBrowser() {
        let planner = BrowserAssistedTaskPlanner()
        let request = BrowserAssistedTaskRequest(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
            kind: .search,
            sessionID: "session-a",
            urlString: "https://www.google.com/search?q=connor",
            title: "Search: connor",
            visibility: .background
        )

        let plan = planner.start(request, in: AppBrowserStateSnapshot(), now: Date(timeIntervalSince1970: 10))

        #expect(plan.snapshot.tabs.count == 1)
        #expect(plan.snapshot.selectedTabID == plan.snapshot.tabs.first?.id)
        #expect(plan.snapshot.tabs.first?.isLoading == true)
        #expect(plan.task.status == .running)
        #expect(plan.task.statusMessage == "Running in background")
        #expect(plan.shouldRevealBrowser == false)
    }

    @Test func foregroundSearchRequestsBrowserRevealImmediately() {
        let planner = BrowserAssistedTaskPlanner()
        let request = BrowserAssistedTaskRequest(
            kind: .search,
            sessionID: "session-a",
            urlString: "https://www.bing.com/search?q=connor",
            title: "Search: connor",
            visibility: .foreground
        )

        let plan = planner.start(request, in: AppBrowserStateSnapshot())

        #expect(plan.shouldRevealBrowser == true)
    }

    @Test func userInterventionMarksTaskAndPreservesTabBinding() {
        let planner = BrowserAssistedTaskPlanner()
        let request = BrowserAssistedTaskRequest(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
            kind: .search,
            sessionID: "session-a",
            urlString: "https://www.google.com/search?q=connor",
            title: "Search: connor"
        )
        let plan = planner.start(request, in: AppBrowserStateSnapshot(), now: Date(timeIntervalSince1970: 20))

        let updated = planner.requireUserIntervention(plan.task, reason: "CAPTCHA requires user action", now: Date(timeIntervalSince1970: 30))

        #expect(updated.id == plan.task.id)
        #expect(updated.tabID == plan.task.tabID)
        #expect(updated.status == .awaitingUserIntervention)
        #expect(updated.statusMessage == "CAPTCHA requires user action")
        #expect(updated.updatedAt == Date(timeIntervalSince1970: 30))
    }

    @Test func completionMarksTaskCompletedWithoutIntervention() {
        let planner = BrowserAssistedTaskPlanner()
        let request = BrowserAssistedTaskRequest(kind: .search, sessionID: "session-a", urlString: "https://search.example?q=connor", title: "Search")
        let plan = planner.start(request, in: AppBrowserStateSnapshot(), now: Date(timeIntervalSince1970: 40))

        let completed = planner.complete(plan.task, now: Date(timeIntervalSince1970: 50))

        #expect(completed.status == .completed)
        #expect(completed.statusMessage == "Completed in background")
    }

    @Test func detectorFlagsCaptchaAndIgnoresOrdinarySearchResults() {
        let detector = BrowserAssistedInterventionDetector()

        #expect(detector.interventionReason(urlString: "https://www.google.com/sorry/index", title: "Unusual traffic") != nil)
        #expect(detector.interventionReason(urlString: "https://www.bing.com/search?q=connor", title: "connor - Search") == nil)
    }
}
