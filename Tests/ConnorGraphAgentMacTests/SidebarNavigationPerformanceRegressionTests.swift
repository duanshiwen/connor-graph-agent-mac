import SwiftUI
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport
@testable import ConnorGraphAgentMac

@MainActor
@Suite("Sidebar Navigation Performance Regression Tests")
struct SidebarNavigationPerformanceRegressionTests {
    @Test func largeFixtureKeepsInitialListWindowsBounded() {
        let fixture = SidebarNavigationPerformanceFixture.make()

        #expect(fixture.sessions.count == 5_000)
        #expect(fixture.mailMessages.count == 500)
        #expect(fixture.rssItems.count == 200)
        #expect(fixture.largeHTML.count >= 500_000)
        #expect(fixture.mailModel.filteredListMessages.count == 500)
        #expect(fixture.mailModel.visibleListMessages.count == 100)
        #expect(fixture.rssModel.visibleItems.count == 200)
        #expect(fixture.rssModel.visibleWindowItems.count == 50)
    }

    @Test func largeSessionMetadataProjectionStaysWithinReleaseBudget() {
        let fixture = SidebarNavigationPerformanceFixture.make()
        var buildSamples: [Double] = []
        var lookupSamples: [Double] = []

        for _ in 0..<30 {
            let buildStarted = DispatchTime.now().uptimeNanoseconds
            let summary = ChatSessionSidebarSummary.build(from: fixture.sessions)
            buildSamples.append(milliseconds(since: buildStarted))
            #expect(summary.totalCount == 5_000)
            #expect(summary.countsByStatus[.todo] == 2_500)

            let lookupStarted = DispatchTime.now().uptimeNanoseconds
            _ = summary.countsByStatus[.todo, default: 0]
            _ = summary.countsByLabelID["important", default: 0]
            lookupSamples.append(milliseconds(since: lookupStarted))
        }

        report("sessionSummaryBuild", buildSamples)
        report("sessionSummaryLookup", lookupSamples)
        assertReleaseBudget(buildSamples, p95Milliseconds: 5)
        assertReleaseBudget(lookupSamples, p95Milliseconds: 1)
    }

    @Test func selectionCommitStaysWithinReleaseBudgetAcrossThirtyRounds() {
        let model = AppShellFeatureModel()
        let sequence: [SidebarItem] = [.agentChat, .rss, .mail, .agentChat]
        var samples: [Double] = []

        for _ in 0..<30 {
            for route in sequence {
                guard model.selection != route else { continue }
                let started = DispatchTime.now().uptimeNanoseconds
                #expect(model.select(route))
                samples.append(milliseconds(since: started))
            }
        }

        report("selectionCommit", samples)
        assertReleaseBudget(samples, p95Milliseconds: 5)
    }

    @Test func retainedHostKeepsBoundedControllersAcrossOneHundredSwitches() {
        let contentOwner = NSObject()
        let host = RetainedRouteHostController(
            pane: .list,
            tracker: AppRoutePerformanceTracker(),
            contentOwner: ObjectIdentifier(contentOwner),
            routeFactory: { route in AnyView(Text(route.rawValue)) }
        )
        let routes: [SidebarItem] = [.agentChat, .rss, .mail, .calendar, .contacts, .sources]
        var samples: [Double] = []

        for index in 0..<100 {
            let started = DispatchTime.now().uptimeNanoseconds
            host.activate(routes[index % routes.count])
            samples.append(milliseconds(since: started))
            #expect(host.cachedControllerCount <= 4)
        }

        report("retainedHostActivation", samples)
        assertReleaseBudget(Array(samples.dropFirst(routes.count)), p95Milliseconds: 50)
    }

    @Test func preparedLargeHTMLCacheHasStableEntryBound() {
        let fixture = SidebarNavigationPerformanceFixture.make()
        let cache = MailHTMLRenderCache(capacity: 8)
        let sanitizer = MailHTMLBodySanitizer()

        for index in 0..<12 {
            let request = MailHTMLSanitizationRequest(
                messageID: MailMessageID(rawValue: "large-\(index)"),
                html: fixture.largeHTML,
                allowsRemoteImages: false
            )
            let result = sanitizer.prepareHTML(fixture.largeHTML, policy: MailHTMLDisplayPolicy(remoteContentMode: .block))
            cache.insert(MailPreparedHTMLBodyPresentation(result), for: request)
            #expect(cache.count <= 8)
        }
    }

    private func milliseconds(since started: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
    }

    private func percentile(_ values: [Double], _ fraction: Double) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let index = min(sorted.count - 1, Int((Double(sorted.count - 1) * fraction).rounded(.up)))
        return sorted[index]
    }

    private func report(_ name: String, _ samples: [Double]) {
        let p50 = percentile(samples, 0.50)
        let p95 = percentile(samples, 0.95)
        let maximum = samples.max() ?? 0
        print("PERF \(name) samples=\(samples.count) p50=\(p50)ms p95=\(p95)ms max=\(maximum)ms")
    }

    private func assertReleaseBudget(_ samples: [Double], p95Milliseconds: Double) {
        #if DEBUG
        let effectiveBudget = max(p95Milliseconds * 10, p95Milliseconds + 10)
        #else
        let effectiveBudget = p95Milliseconds
        #endif
        #expect(percentile(samples, 0.95) <= effectiveBudget)
    }
}

@MainActor
private struct SidebarNavigationPerformanceFixture {
    var sessions: [AgentSession]
    var mailMessages: [MailMessageSummary]
    var rssItems: [RSSItemSummary]
    var largeHTML: String
    var mailModel: MailFeatureModel
    var rssModel: RSSFeatureModel

    static func make() -> Self {
        let sessions = (0..<5_000).map { index in
            AgentSession(
                id: "session-\(index)",
                title: "Session \(index)",
                updatedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                governance: AgentSessionGovernanceMetadata(status: index.isMultiple(of: 2) ? .todo : .inProgress)
            )
        }

        let accountID = MailAccountID(rawValue: "fixture@example.com")
        let mailboxID = MailMailboxID(rawValue: "inbox")
        let identity = MailIdentity(
            id: MailIdentityID(rawValue: "fixture-identity"),
            displayName: "Fixture",
            address: MailAddress(email: "fixture@example.com")
        )
        let account = MailAccount(id: accountID, provider: .localFixture, displayName: "Fixture", identities: [identity])
        let mailbox = MailMailbox(id: mailboxID, accountID: accountID, name: "Inbox", path: "INBOX", role: .inbox)
        let mailMessages = (0..<500).map { index in
            MailMessageSummary(
                id: MailMessageID(rawValue: "mail-\(index)"),
                accountID: accountID,
                mailboxID: mailboxID,
                subject: "Mail \(index)",
                from: MailAddress(email: "sender@example.com"),
                to: [identity.address],
                date: Date(timeIntervalSince1970: TimeInterval(index)),
                snippet: "Fixture snippet"
            )
        }
        let mailModel = MailFeatureModel(store: nil, preferencesStore: nil)
        mailModel.presentation = NativeMailBrowserPresentation(accounts: [account], mailboxes: [mailbox], messages: mailMessages)

        let sourceID = RSSSourceID(rawValue: "fixture-rss")
        let source = RSSSource(id: sourceID, feedURL: URL(string: "https://example.com/feed.xml")!, displayName: "Fixture RSS")
        let rssItems = (0..<200).map { index in
            RSSItemSummary(
                id: RSSItemID(rawValue: "rss-\(index)"),
                sourceID: sourceID,
                title: "RSS \(index)",
                snippet: "Fixture RSS body"
            )
        }
        let rssModel = RSSFeatureModel(runtime: RSSRuntime(
            repository: InMemoryRSSSourceRepository(sources: [source]),
            cache: InMemoryRSSSourceCache(items: [])
        ))
        rssModel.presentation = NativeRSSBrowserPresentation(sources: [source], items: rssItems)

        let paragraph = "<p>Large fixture body for deterministic mail rendering.</p>"
        let largeHTML = "<html><body>" + String(repeating: paragraph, count: 10_000) + "</body></html>"
        return Self(
            sessions: sessions,
            mailMessages: mailMessages,
            rssItems: rssItems,
            largeHTML: largeHTML,
            mailModel: mailModel,
            rssModel: rssModel
        )
    }
}
