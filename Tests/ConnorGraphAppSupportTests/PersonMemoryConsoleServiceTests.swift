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

    @Test func archiveMemoryItemMarksStatementArchivedAndRemovesFromActiveList() async throws {
        let store = try SQLiteMemoryOSStore(path: temporaryPersonMemoryConsoleDatabaseURL().path)
        try store.migrate()
        let now = Date(timeIntervalSince1970: 10_300)
        let profile = boundProfile(id: "person-dana", name: "Dana")
        try seedEntity(for: profile, in: store, now: now)
        try seedStatement(id: "memory-archive", text: "Dana 喜欢潜水。", profile: profile, store: store, now: now)
        let service = AppPersonMemoryConsoleService(store: store)

        try await service.archiveMemoryItem(id: "memory-archive", for: profile, now: now.addingTimeInterval(10))

        #expect(try await service.loadMemoryItems(for: profile).isEmpty)
        let allItems = try await service.loadMemoryItems(for: profile, includeInactive: true)
        #expect(allItems.first?.status == .archived)
        let statement = try #require(try store.entityStatement(id: "memory-archive"))
        #expect(statement.metadata["person_memory_status"] == "archived")
        #expect(statement.metadata["person_memory_governed_at"] != nil)
    }

    @Test func deleteMemoryItemMarksStatementDeletedAndRemovesFromActiveList() async throws {
        let store = try SQLiteMemoryOSStore(path: temporaryPersonMemoryConsoleDatabaseURL().path)
        try store.migrate()
        let now = Date(timeIntervalSince1970: 10_400)
        let profile = boundProfile(id: "person-erin", name: "Erin")
        try seedEntity(for: profile, in: store, now: now)
        try seedStatement(id: "memory-delete", text: "Erin 的错误记忆。", profile: profile, store: store, now: now)
        let service = AppPersonMemoryConsoleService(store: store)

        try await service.deleteMemoryItem(id: "memory-delete", for: profile, now: now.addingTimeInterval(10))

        #expect(try await service.loadMemoryItems(for: profile).isEmpty)
        let allItems = try await service.loadMemoryItems(for: profile, includeInactive: true)
        #expect(allItems.first?.status == .deleted)
        let statement = try #require(try store.entityStatement(id: "memory-delete"))
        #expect(statement.metadata["person_memory_status"] == "deleted")
    }

    @Test func archiveAndDeleteRequireStatementBelongsToPerson() async throws {
        let store = try SQLiteMemoryOSStore(path: temporaryPersonMemoryConsoleDatabaseURL().path)
        try store.migrate()
        let now = Date(timeIntervalSince1970: 10_500)
        let owner = boundProfile(id: "person-owner", name: "Owner")
        let other = boundProfile(id: "person-other", name: "Other")
        try seedEntity(for: owner, in: store, now: now)
        try seedEntity(for: other, in: store, now: now)
        try seedStatement(id: "memory-owner", text: "Owner memory", profile: owner, store: store, now: now)
        let service = AppPersonMemoryConsoleService(store: store)

        await #expect(throws: PersonMemoryConsoleServiceError.self) {
            try await service.archiveMemoryItem(id: "memory-owner", for: other, now: now)
        }
        await #expect(throws: PersonMemoryConsoleServiceError.self) {
            try await service.deleteMemoryItem(id: "memory-owner", for: other, now: now)
        }
    }

    @Test func moveMemoryItemCopiesStatementToTargetAndMarksSourceMoved() async throws {
        let store = try SQLiteMemoryOSStore(path: temporaryPersonMemoryConsoleDatabaseURL().path)
        try store.migrate()
        let now = Date(timeIntervalSince1970: 10_600)
        let source = boundProfile(id: "person-source", name: "Source")
        let target = boundProfile(id: "person-target", name: "Target")
        try seedEntity(for: source, in: store, now: now)
        try seedEntity(for: target, in: store, now: now)
        try store.upsert(entityStatement: MemoryOSEntityStatement(
            id: "memory-move",
            entityID: try #require(source.memoryEntityID),
            predicate: .relatedTo,
            text: "这条记忆应该属于 Target。",
            validAt: now,
            committedAt: now,
            evidenceSpanIDs: ["span-1"],
            sourceArtifactID: "artifact-1",
            metadata: ["person_profile_id": source.id.rawValue]
        ))
        let service = AppPersonMemoryConsoleService(store: store)

        let moved = try await service.moveMemoryItem(id: "memory-move", from: source, to: target, now: now.addingTimeInterval(10))

        #expect(moved.personID == target.id)
        #expect(moved.text == "这条记忆应该属于 Target。")
        #expect(moved.evidenceSpanIDs == ["span-1"])
        #expect(moved.sourceArtifactID == "artifact-1")
        #expect(try await service.loadMemoryItems(for: source).isEmpty)
        let sourceAll = try await service.loadMemoryItems(for: source, includeInactive: true)
        #expect(sourceAll.first?.status == .moved)
        let targetItems = try await service.loadMemoryItems(for: target)
        #expect(targetItems.map(\.text) == ["这条记忆应该属于 Target。"])
        #expect(targetItems.first?.id != "memory-move")
    }

    @Test func moveMemoryItemRejectsDeletedTargetPerson() async throws {
        let store = try SQLiteMemoryOSStore(path: temporaryPersonMemoryConsoleDatabaseURL().path)
        try store.migrate()
        let now = Date(timeIntervalSince1970: 10_700)
        let source = boundProfile(id: "person-source", name: "Source")
        var target = boundProfile(id: "person-deleted", name: "Deleted")
        target.status = .deleted
        try seedEntity(for: source, in: store, now: now)
        try seedEntity(for: target, in: store, now: now)
        try seedStatement(id: "memory-move", text: "Cannot move", profile: source, store: store, now: now)
        let service = AppPersonMemoryConsoleService(store: store)

        await #expect(throws: PersonMemoryConsoleServiceError.self) {
            try await service.moveMemoryItem(id: "memory-move", from: source, to: target, now: now)
        }
    }

    @Test func mergePersonMemoryMovesActiveSourceMemoryToTarget() async throws {
        let store = try SQLiteMemoryOSStore(path: temporaryPersonMemoryConsoleDatabaseURL().path)
        try store.migrate()
        let now = Date(timeIntervalSince1970: 10_800)
        let source = boundProfile(id: "person-merge-source", name: "Source")
        let target = boundProfile(id: "person-merge-target", name: "Target")
        try seedEntity(for: source, in: store, now: now)
        try seedEntity(for: target, in: store, now: now)
        try seedStatement(id: "memory-merge-1", text: "Source 的可迁移记忆。", profile: source, store: store, now: now)
        try store.upsert(entityStatement: MemoryOSEntityStatement(
            id: "memory-merge-archived",
            entityID: try #require(source.memoryEntityID),
            predicate: .relatedTo,
            text: "Source 的 archived 记忆不应迁移。",
            committedAt: now,
            metadata: ["person_profile_id": source.id.rawValue, "person_memory_status": "archived"]
        ))
        let service = AppPersonMemoryConsoleService(store: store)

        let movedItems = try await service.mergePersonMemory(source: source, target: target, now: now.addingTimeInterval(10))

        #expect(movedItems.map(\.text) == ["Source 的可迁移记忆。"])
        #expect(try await service.loadMemoryItems(for: source).isEmpty)
        #expect(try await service.loadMemoryItems(for: target).map(\.text) == ["Source 的可迁移记忆。"])
        let sourceAll = try await service.loadMemoryItems(for: source, includeInactive: true)
        #expect(sourceAll.first(where: { $0.id == "memory-merge-1" })?.status == .moved)
        #expect(sourceAll.first(where: { $0.id == "memory-merge-archived" })?.status == .archived)
    }

    @Test func deletePersonMemoryMarksActiveMemoryDeleted() async throws {
        let store = try SQLiteMemoryOSStore(path: temporaryPersonMemoryConsoleDatabaseURL().path)
        try store.migrate()
        let now = Date(timeIntervalSince1970: 10_900)
        let profile = boundProfile(id: "person-delete-all", name: "Delete All")
        try seedEntity(for: profile, in: store, now: now)
        try seedStatement(id: "memory-delete-all", text: "这条 active 记忆要删除。", profile: profile, store: store, now: now)
        try store.upsert(entityStatement: MemoryOSEntityStatement(
            id: "memory-already-archived",
            entityID: try #require(profile.memoryEntityID),
            predicate: .relatedTo,
            text: "这条 archived 记忆保持 archived。",
            committedAt: now,
            metadata: ["person_profile_id": profile.id.rawValue, "person_memory_status": "archived"]
        ))
        let service = AppPersonMemoryConsoleService(store: store)

        try await service.deletePersonMemory(for: profile, now: now.addingTimeInterval(10))

        #expect(try await service.loadMemoryItems(for: profile).isEmpty)
        let all = try await service.loadMemoryItems(for: profile, includeInactive: true)
        #expect(all.first(where: { $0.id == "memory-delete-all" })?.status == .deleted)
        #expect(all.first(where: { $0.id == "memory-already-archived" })?.status == .archived)
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

private func seedStatement(id: String, text: String, profile: PersonProfile, store: SQLiteMemoryOSStore, now: Date) throws {
    try store.upsert(entityStatement: MemoryOSEntityStatement(
        id: id,
        entityID: try #require(profile.memoryEntityID),
        predicate: .relatedTo,
        text: text,
        validAt: now,
        committedAt: now,
        metadata: ["person_profile_id": profile.id.rawValue]
    ))
}
