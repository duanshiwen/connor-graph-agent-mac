import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore

private func temporaryResolverDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func entityResolverMatchesStableKeyAndAliasWithinScope() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryResolverDatabaseURL().path)
    try store.migrate()
    let entity = GraphEntity(
        id: "entity-apple",
        graphID: "default",
        name: "Apple Inc.",
        entityKind: .entity,
        scope: .publicScope,
        canonicalClassID: "organization",
        aliases: ["Apple", "苹果公司"]
    )
    try store.upsert(entity: entity)
    let resolver = SQLiteGraphEntityResolver(store: store)

    let stableResult = try resolver.resolve(name: "Apple Inc.", entityKind: .entity, scope: .publicScope, graphID: "default")
    let aliasResult = try resolver.resolve(name: "苹果公司", entityKind: .entity, scope: .publicScope, graphID: "default")
    let scopedResult = try resolver.resolve(name: "Apple Inc.", entityKind: .entity, scope: .personal, graphID: "default")

    #expect(stableResult == .matched(entity.id, reason: .stableKey))
    #expect(aliasResult == .matched(entity.id, reason: .alias))
    #expect(scopedResult == .create(stableKey: "personal:entity:apple_inc"))
}
