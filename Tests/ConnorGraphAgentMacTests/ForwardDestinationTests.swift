import Testing
@testable import ConnorGraphAgentMac

@Suite("Forward destination tests")
struct ForwardDestinationTests {
    @Test("existing destinations mix by most recent activity")
    func sortsAllDestinationKindsByRecency() {
        let destinations = [
            ForwardDestination(key: "agent:old", targetID: "old", title: "Old Agent", subtitle: "", kind: .agent, updatedAt: 100),
            ForwardDestination(key: "im:peer", targetID: "peer", title: "Peer", subtitle: "", kind: .peer, updatedAt: 400),
            ForwardDestination(key: "agent:newer", targetID: "newer", title: "Newer Agent", subtitle: "", kind: .agent, updatedAt: 300),
            ForwardDestination(key: "im:group", targetID: "group", title: "Group", subtitle: "", kind: .group, updatedAt: 200),
        ]

        let sorted = sortForwardDestinationsByRecency(destinations)

        #expect(sorted.map(\.key) == ["im:peer", "agent:newer", "im:group", "agent:old"])
    }

    @Test @MainActor func pagerMergesSourcesByRecencyAndLoadsAll() async throws {
        final class Source {
            var cursor = 0
            let items: [ForwardDestination]
            init(_ items: [ForwardDestination]) { self.items = items }
        }
        let sessions = Source([
            ForwardDestination(key: "agent:a", targetID: "a", title: "A", subtitle: "", kind: .agent, updatedAt: 300),
            ForwardDestination(key: "agent:b", targetID: "b", title: "B", subtitle: "", kind: .agent, updatedAt: 100)
        ])
        let conversations = Source([
            ForwardDestination(key: "im:1", targetID: "1", title: "One", subtitle: "", kind: .peer, updatedAt: 400),
            ForwardDestination(key: "im:2", targetID: "2", title: "Two", subtitle: "", kind: .peer, updatedAt: 200),
            ForwardDestination(key: "im:3", targetID: "3", title: "Three", subtitle: "", kind: .peer, updatedAt: 50)
        ])
        let pager = ForwardDestinationPager(
            sessionsLoader: { _, limit in
                let start = sessions.cursor
                let end = min(start + limit, sessions.items.count)
                sessions.cursor = end
                return (Array(sessions.items[start..<end]), end < sessions.items.count ? "s\(end)" : nil)
            },
            conversationsLoader: { _, limit in
                let start = conversations.cursor
                let end = min(start + limit, conversations.items.count)
                conversations.cursor = end
                return (Array(conversations.items[start..<end]), end < conversations.items.count ? "c\(end)" : nil)
            },
            pageSize: 2
        )

        var merged: [ForwardDestination] = []
        var pages = 0
        while true {
            let page = try await pager.loadNextPage()
            if page.isEmpty { break }
            pages += 1
            merged.append(contentsOf: page)
        }

        #expect(pages == 3)
        #expect(merged.map(\.key) == ["im:1", "agent:a", "im:2", "agent:b", "im:3"])
        #expect(pager.hasMore == false)
    }

    @Test @MainActor func pagerLoadAllIsNonDestructiveForBrowsing() async throws {
        let items = [
            ForwardDestination(key: "agent:a", targetID: "a", title: "A", subtitle: "", kind: .agent, updatedAt: 100),
            ForwardDestination(key: "im:1", targetID: "1", title: "One", subtitle: "", kind: .peer, updatedAt: 90)
        ]
        let pager = ForwardDestinationPager(
            sessionsLoader: { _, limit in (Array(items.prefix(limit)), nil) },
            conversationsLoader: { _, _ in ([], nil) },
            pageSize: 2
        )

        let all = try await pager.loadAll()
        #expect(all.map(\.key) == ["agent:a", "im:1"])

        // loadAll 使用独立实例，不影响当前分页游标。
        let firstPage = try await pager.loadNextPage()
        #expect(firstPage.map(\.key) == ["agent:a", "im:1"])
    }
}
