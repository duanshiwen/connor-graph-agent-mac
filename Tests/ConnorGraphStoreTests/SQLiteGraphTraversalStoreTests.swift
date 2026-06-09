import Foundation
import Testing
import ConnorGraphCore
@testable import ConnorGraphStore

@Test func sqliteGraphTraversalFindsOneHopNeighbors() throws {
    let store = try SQLiteGraphStore(path: temporaryTraversalDatabaseURL().path)
    try store.migrate()
    let fixture = try insertTraversalFixture(in: store)

    let traversal = SQLiteGraphTraversalStore(store: store)
    let neighbors = try traversal.neighbors(of: fixture.center.id, groupID: "default", depth: 1, limit: 10)

    #expect(neighbors.map(\.nodeID) == [fixture.oneHop.id])
    #expect(neighbors.first?.depth == 1)
    #expect(neighbors.first?.viaFactID == fixture.centerToOneHop.id)
}

@Test func sqliteGraphTraversalFindsShortestHopDistances() throws {
    let store = try SQLiteGraphStore(path: temporaryTraversalDatabaseURL().path)
    try store.migrate()
    let fixture = try insertTraversalFixture(in: store)

    let traversal = SQLiteGraphTraversalStore(store: store)
    let distances = try traversal.shortestHopDistances(
        from: [fixture.center.id],
        to: [fixture.center.id, fixture.oneHop.id, fixture.twoHop.id, fixture.unrelated.id],
        groupID: "default",
        maxDepth: 2
    )

    #expect(distances[fixture.center.id] == 0)
    #expect(distances[fixture.oneHop.id] == 1)
    #expect(distances[fixture.twoHop.id] == 2)
    #expect(distances[fixture.unrelated.id] == nil)
}

@Test func sqliteGraphTraversalRespectsGroupBoundaries() throws {
    let store = try SQLiteGraphStore(path: temporaryTraversalDatabaseURL().path)
    try store.migrate()
    let fixture = try insertTraversalFixture(in: store)

    let otherCenter = GraphNodeV2(id: "node-other-center", groupID: "other", type: .entity, canonicalName: "center", title: "Center")
    let otherNeighbor = GraphNodeV2(id: "node-other-neighbor", groupID: "other", type: .entity, canonicalName: "neighbor", title: "Neighbor")
    let otherFact = GraphFact(id: "fact-other", groupID: "other", sourceNodeID: otherCenter.id, targetNodeID: otherNeighbor.id, relation: .mentions, fact: "Other group edge.")
    try store.upsert(nodeV2: otherCenter)
    try store.upsert(nodeV2: otherNeighbor)
    try store.upsert(fact: otherFact)

    let traversal = SQLiteGraphTraversalStore(store: store)
    let distances = try traversal.shortestHopDistances(
        from: [fixture.center.id],
        to: [otherNeighbor.id],
        groupID: "default",
        maxDepth: 2
    )

    #expect(distances[otherNeighbor.id] == nil)
}

private struct TraversalFixture {
    var center: GraphNodeV2
    var oneHop: GraphNodeV2
    var twoHop: GraphNodeV2
    var unrelated: GraphNodeV2
    var centerToOneHop: GraphFact
    var oneHopToTwoHop: GraphFact
}

private func insertTraversalFixture(in store: SQLiteGraphStore) throws -> TraversalFixture {
    let center = GraphNodeV2(id: "node-center-traversal", groupID: "default", type: .entity, canonicalName: "center", title: "Center")
    let oneHop = GraphNodeV2(id: "node-one-hop-traversal", groupID: "default", type: .entity, canonicalName: "one", title: "One")
    let twoHop = GraphNodeV2(id: "node-two-hop-traversal", groupID: "default", type: .entity, canonicalName: "two", title: "Two")
    let unrelated = GraphNodeV2(id: "node-unrelated-traversal", groupID: "default", type: .entity, canonicalName: "unrelated", title: "Unrelated")
    let centerToOneHop = GraphFact(id: "fact-center-one", groupID: "default", sourceNodeID: center.id, targetNodeID: oneHop.id, relation: .mentions, fact: "Center mentions one.")
    let oneHopToTwoHop = GraphFact(id: "fact-one-two", groupID: "default", sourceNodeID: oneHop.id, targetNodeID: twoHop.id, relation: .mentions, fact: "One mentions two.")

    try store.upsert(nodeV2: center)
    try store.upsert(nodeV2: oneHop)
    try store.upsert(nodeV2: twoHop)
    try store.upsert(nodeV2: unrelated)
    try store.upsert(fact: centerToOneHop)
    try store.upsert(fact: oneHopToTwoHop)

    return TraversalFixture(
        center: center,
        oneHop: oneHop,
        twoHop: twoHop,
        unrelated: unrelated,
        centerToOneHop: centerToOneHop,
        oneHopToTwoHop: oneHopToTwoHop
    )
}

private func temporaryTraversalDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("connor-graph-traversal-\(UUID().uuidString)")
        .appendingPathExtension("sqlite")
}
