import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore
import ConnorGraphAppSupport

private func temporaryPersonMemoryConsoleDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Suite("Person Memory Console Service Tests")
struct PersonMemoryConsoleServiceTests {
    @Test func loadMemoryItemsReturnsActiveStatementsForBoundPerson() async throws {
        let store = try SQLiteMemoryOSStore(path: temporaryPersonMemoryConsoleDatabaseURL().path)
        try store.migrate()
        let now = Date(timeIntervalSince1970: 10_000)
        let profile = boundProfile(id: "person-alice", name: "Alice")
        try seedEntity(for: profile, in: store, now: now)
        try store.upsert(entityStatement: MemoryOSEntityStatement(
            id: "memory-1",
            entityID: try #require(profile.memoryEntityID),
            predicate: .relatedTo,
            text: "Alice 喜欢摄影。",
            validAt: now,
            committedAt: now,
            sourceArtifactID: "artifact-1",
            metadata: ["person_profile_id": profile.id.rawValue]
        ))
        let service = AppPersonMemoryConsoleService(store: store)

        let items = try await service.loadMemoryItems(for: profile)

        #expect(items.map(\.id) == ["memory-1"])
        #expect(items.first?.personID == profile.id)
        #expect(items.first?.status == .active)
        #expect(items.first?.text == "Alice 喜欢摄影。")
        #expect(items.first?.sourceArtifactID == "artifact-1")
    }

    @Test func loadMemoryItemsHidesArchivedDeletedAndMovedByDefault() async throws {
        let store = try SQLiteMemoryOSStore(path: temporaryPersonMemoryConsoleDatabaseURL().path)
        try store.migrate()
        let now = Date(timeIntervalSince1970: 10_100)
        let profile = boundProfile(id: "person-bob", name: "Bob")
        try seedEntity(for: profile, in: store, now: now)
        let entityID = try #require(profile.memoryEntityID)
        for (id, status) in [
            ("active", "active"),
            ("archived", "archived"),
            ("deleted", "deleted"),
            ("moved", "moved")
        ] {
            try store.upsert(entityStatement: MemoryOSEntityStatement(
                id: id,
                entityID: entityID,
                predicate: .relatedTo,
                text: "\(id) memory",
                committedAt: now,
                metadata: ["person_profile_id": profile.id.rawValue, "person_memory_status": status]
            ))
        }
        let service = AppPersonMemoryConsoleService(store: store)

        let activeItems = try await service.loadMemoryItems(for: profile)
        let allItems = try await service.loadMemoryItems(for: profile, includeInactive: true)

        #expect(activeItems.map(\.id) == ["active"])
        #expect(Set(allItems.map(\.status)) == [.active, .archived, .deleted, .moved])
    }

    @Test func activeMemorySummaryUsesBoundActiveStatementsNotProfileNotes() async throws {
        let store = try SQLiteMemoryOSStore(path: temporaryPersonMemoryConsoleDatabaseURL().path)
        try store.migrate()
        let now = Date(timeIntervalSince1970: 10_200)
        var profile = boundProfile(id: "person-carol", name: "Carol")
        profile.notes = "profile notes should not be memory summary"
        try seedEntity(for: profile, in: store, now: now)
        let entityID = try #require(profile.memoryEntityID)
        try store.upsert(entityStatement: MemoryOSEntityStatement(
            id: "newer",
            entityID: entityID,
            predicate: .relatedTo,
            text: "Carol 负责产品策略。",
            committedAt: now.addingTimeInterval(60),
            metadata: ["person_profile_id": profile.id.rawValue]
        ))
        try store.upsert(entityStatement: MemoryOSEntityStatement(
            id: "archived",
            entityID: entityID,
            predicate: .relatedTo,
            text: "Carol 的旧记忆不应进入摘要。",
            committedAt: now.addingTimeInterval(120),
            metadata: ["person_profile_id": profile.id.rawValue, "person_memory_status": "archived"]
        ))
        let service = AppPersonMemoryConsoleService(store: store)

        let summary = try await service.activeMemorySummary(for: profile, limit: 4)

        #expect(summary.contains("Carol 负责产品策略。"))
        #expect(!summary.contains("profile notes"))
        #expect(!summary.contains("旧记忆"))
    }
}

private func boundProfile(id: String, name: String) -> PersonProfile {
    PersonProfile(
        id: ContactID(rawValue: id),
        displayName: name,
        memoryEntityID: "person:person-profile:\(id)",
        memoryStableKey: "person-profile:\(id)"
    )
}

private func seedEntity(for profile: PersonProfile, in store: SQLiteMemoryOSStore, now: Date) throws {
    try store.upsert(entity: MemoryOSEntity(
        id: try #require(profile.memoryEntityID),
        stableKey: try #require(profile.memoryStableKey),
        entityType: MemoryOSEntityType.person.rawValue,
        name: profile.displayName,
        aliases: profile.aliases,
        summary: "Person profile memory anchor",
        confidence: 1.0,
        createdAt: now,
        updatedAt: now,
        metadata: ["person_profile_id": profile.id.rawValue]
    ))
}
