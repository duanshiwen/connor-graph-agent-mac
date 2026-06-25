import Foundation
import Testing
import ConnorGraphAppSupport

@Suite("Browser Live WebView Budget Policy Tests")
struct BrowserLiveWebViewBudgetPolicyTests {
    @Test func evictsLeastRecentlyUsedHiddenEntryWhenHiddenCountExceedsLimit() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let entries = (0..<5).map { index in
            BrowserLiveWebViewBudgetEntry(
                key: BrowserLiveWebViewKey(sessionID: "session", tabID: UUID()),
                isVisible: false,
                lastAccessedAt: now.addingTimeInterval(TimeInterval(index)),
                restorationStatus: .live
            )
        }
        let policy = BrowserLiveWebViewBudgetPolicy(config: .init(maxHiddenLiveWebViews: 4, minHiddenLiveWebViewsToKeep: 1))

        let decision = policy.evictionDecision(entries: entries, processMemoryMegabytes: nil)

        #expect(decision.keysToEvict == [entries[0].key])
        #expect(decision.reason == .hiddenCountExceeded)
    }

    @Test func doesNotEvictVisibleEntryEvenWhenOldest() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let visible = BrowserLiveWebViewBudgetEntry(
            key: BrowserLiveWebViewKey(sessionID: "session", tabID: UUID()),
            isVisible: true,
            lastAccessedAt: now.addingTimeInterval(-100),
            restorationStatus: .live
        )
        let hiddenA = BrowserLiveWebViewBudgetEntry(
            key: BrowserLiveWebViewKey(sessionID: "session", tabID: UUID()),
            isVisible: false,
            lastAccessedAt: now,
            restorationStatus: .live
        )
        let hiddenB = BrowserLiveWebViewBudgetEntry(
            key: BrowserLiveWebViewKey(sessionID: "session", tabID: UUID()),
            isVisible: false,
            lastAccessedAt: now.addingTimeInterval(1),
            restorationStatus: .live
        )
        let policy = BrowserLiveWebViewBudgetPolicy(config: .init(maxHiddenLiveWebViews: 1, minHiddenLiveWebViewsToKeep: 0))

        let decision = policy.evictionDecision(entries: [visible, hiddenA, hiddenB], processMemoryMegabytes: nil)

        #expect(decision.keysToEvict == [hiddenA.key])
        #expect(!decision.keysToEvict.contains(visible.key))
    }

    @Test func keepsAtLeastMinimumHiddenEntriesDuringMemoryPressure() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let hidden = BrowserLiveWebViewBudgetEntry(
            key: BrowserLiveWebViewKey(sessionID: "session", tabID: UUID()),
            isVisible: false,
            lastAccessedAt: now,
            restorationStatus: .live
        )
        let policy = BrowserLiveWebViewBudgetPolicy(
            config: .init(maxHiddenLiveWebViews: 4, minHiddenLiveWebViewsToKeep: 1, softProcessMemoryLimitMegabytes: 512)
        )

        let decision = policy.evictionDecision(entries: [hidden], processMemoryMegabytes: 900)

        #expect(decision.keysToEvict.isEmpty)
        #expect(decision.reason == .withinBudget)
    }

    @Test func memoryPressureRequestsHiddenLRUEviction() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let hiddenA = BrowserLiveWebViewBudgetEntry(
            key: BrowserLiveWebViewKey(sessionID: "session", tabID: UUID()),
            isVisible: false,
            lastAccessedAt: now,
            restorationStatus: .live
        )
        let hiddenB = BrowserLiveWebViewBudgetEntry(
            key: BrowserLiveWebViewKey(sessionID: "session", tabID: UUID()),
            isVisible: false,
            lastAccessedAt: now.addingTimeInterval(1),
            restorationStatus: .live
        )
        let policy = BrowserLiveWebViewBudgetPolicy(
            config: .init(maxHiddenLiveWebViews: 4, minHiddenLiveWebViewsToKeep: 1, softProcessMemoryLimitMegabytes: 512)
        )

        let decision = policy.evictionDecision(entries: [hiddenA, hiddenB], processMemoryMegabytes: 900)

        #expect(decision.keysToEvict == [hiddenA.key])
        #expect(decision.reason == .memoryPressure)
    }

    @Test func prefersAlreadyRestorableEntriesBeforeRecentlyVisibleEntries() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let recentlyVisible = BrowserLiveWebViewBudgetEntry(
            key: BrowserLiveWebViewKey(sessionID: "session", tabID: UUID()),
            isVisible: false,
            lastAccessedAt: now.addingTimeInterval(-100),
            lastVisibleAt: now.addingTimeInterval(-10),
            restorationStatus: .live
        )
        let restorable = BrowserLiveWebViewBudgetEntry(
            key: BrowserLiveWebViewKey(sessionID: "session", tabID: UUID()),
            isVisible: false,
            lastAccessedAt: now,
            lastVisibleAt: now.addingTimeInterval(-1_000),
            restorationStatus: .restoredFromSnapshot
        )
        let policy = BrowserLiveWebViewBudgetPolicy(config: .init(maxHiddenLiveWebViews: 1, minHiddenLiveWebViewsToKeep: 0))

        let decision = policy.evictionDecision(entries: [recentlyVisible, restorable], processMemoryMegabytes: nil)

        #expect(decision.keysToEvict == [restorable.key])
    }
}
