import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore

private func temporaryReasonerDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func reasonerInfersInstanceOfThroughSubclassChain() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryReasonerDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 1_000)
    let macOS = GraphEntity(id: "macos", graphID: "default", name: "macOS", entityKind: .artifact, scope: .publicScope)
    let os = GraphEntity(id: "class-operating-system", graphID: "default", name: "operating system", entityKind: .classNode, scope: .publicScope)
    let software = GraphEntity(id: "class-software", graphID: "default", name: "software", entityKind: .classNode, scope: .publicScope)
    try store.upsert(entity: macOS)
    try store.upsert(entity: os)
    try store.upsert(entity: software)
    try store.upsert(statement: GraphStatement(id: "s1", graphID: "default", subjectEntityID: macOS.id, predicate: .instanceOf, objectEntityID: os.id, statementText: "macOS is an operating system", validAt: now, committedAt: now, confidence: 0.9, justifications: [GraphJustification(type: .extracted, source: "episode-1", strength: 0.9)], sourceEpisodeIDs: ["episode-1"]))
    try store.upsert(statement: GraphStatement(id: "s2", graphID: "default", subjectEntityID: os.id, predicate: .subclassOf, objectEntityID: software.id, statementText: "operating system is software", validAt: now, committedAt: now, confidence: 0.95, justifications: [GraphJustification(type: .constraintDerived, source: "seed", strength: 1.0)], sourceEpisodeIDs: ["seed"]))

    let reasoner = SQLiteGraphReasoner(store: store)
    let inferred = try reasoner.inferredInstanceOf(entityID: macOS.id, graphID: "default")

    #expect(inferred.contains { $0.objectEntityID == software.id && $0.predicate == .instanceOf && $0.inferencePath == ["s1", "s2"] })
}
