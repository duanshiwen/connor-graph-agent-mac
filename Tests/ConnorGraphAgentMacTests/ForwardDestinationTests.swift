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
}
