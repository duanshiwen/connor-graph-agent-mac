import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore

private func temporaryMemoryOSKernelDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func memoryOSTemporalEntityKernelSupportsStableEntityAliasAndFTS() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryMemoryOSKernelDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 1_000)
    let entity = MemoryOSEntity(
        id: "entity-connor-memory-os",
        stableKey: MemoryOSStableKeyBuilder.stableKey(type: "project", name: "Connor Memory OS"),
        entityType: "project",
        name: "Connor Memory OS",
        aliases: ["MemoryOS", "L0-L4 Memory"],
        summary: "Production-grade memory architecture",
        confidence: 0.96,
        createdAt: now,
        updatedAt: now,
        validFrom: now
    )

    try store.upsert(entity: entity)

    let loaded = try store.entity(id: entity.id)
    #expect(loaded?.stableKey == "default:project:connor-memory-os")
    #expect(loaded?.aliases == ["MemoryOS", "L0-L4 Memory"])
    #expect(try store.searchEntitiesFTS(query: "MemoryOS") == [entity.id])
}
