import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore

private func temporaryMemoryOSSyncDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func l2StatementWithUnknownSubjectFailsUnderForeignKeys() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryMemoryOSSyncDatabaseURL().path)
    try store.migrate()
    let statement = MemoryOSStatement(
        id: "sync-s1",
        subjectID: "free-text-subject",
        predicate: "knows",
        text: "hello",
        committedAt: Date(timeIntervalSince1970: 1_000)
    )
    // 本地管线要求 subject 存在于 memory_l2_nodes，否则外键拦截。
    #expect(throws: SQLiteMemoryOSStoreError.self) {
        try store.upsert(statement: statement)
    }
}

@Test func l2StatementWithUnknownSubjectCanBeSyncedWithForeignKeysDisabled() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryMemoryOSSyncDatabaseURL().path)
    try store.migrate()
    let statement = MemoryOSStatement(
        id: "sync-s2",
        subjectID: "free-text-subject",
        predicate: "knows",
        text: "hello",
        committedAt: Date(timeIntervalSince1970: 1_000)
    )
    try store.withForeignKeysDisabled {
        try store.upsert(statement: statement)
    }
    #expect(try store.listAllStatements().contains { $0.id == "sync-s2" })
}

@Test func replacingEntityWithChildrenWorksUnderForeignKeysDisabled() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryMemoryOSSyncDatabaseURL().path)
    try store.migrate()
    let entity = MemoryOSEntity(
        id: "e1",
        stableKey: "person:1",
        entityType: "person",
        name: "张三",
        aliases: ["阿三"],
        createdAt: Date(timeIntervalSince1970: 1_000),
        updatedAt: Date(timeIntervalSince1970: 1_000)
    )
    let relation = MemoryOSEntityStatement(
        id: "r1",
        entityID: "e1",
        predicate: .relatedTo,
        objectEntityID: "e2",
        text: "认识",
        committedAt: Date(timeIntervalSince1970: 1_000)
    )
    try store.withForeignKeysDisabled {
        try store.upsert(entity: entity)
        try store.upsert(entityStatement: relation)
        // 同步可能重复应用同一实体：REPLACE 先删旧行，外键放开后不再失败。
        try store.upsert(entity: entity)
    }
    #expect(try store.entity(id: "e1") != nil)
    #expect(try store.entityStatements(entityID: "e1", limit: 10).contains { $0.id == "r1" })
}
