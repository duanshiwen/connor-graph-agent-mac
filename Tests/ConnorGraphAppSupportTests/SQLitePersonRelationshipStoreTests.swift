import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("SQLite Person Relationship Store Tests")
struct SQLitePersonRelationshipStoreTests {
    @Test func newDatabaseLoadsEmptyRelationships() async throws {
        let store = try makeStore()

        let relationships = try await store.loadRelationships(includeInactive: false)

        #expect(relationships.isEmpty)
    }

    @Test func upsertAndLoadRoundTripsPersonToPersonRelationship() async throws {
        let store = try makeStore()
        let createdAt = Date(timeIntervalSince1970: 100)
        let relationship = PersonRelationship(
            id: "rel-1",
            source: .personProfile(ContactID(rawValue: "person-zhang-xia")),
            target: .personProfile(ContactID(rawValue: "person-duan-fuqiang")),
            kind: .parentOf,
            customKindLabel: "妈妈",
            evidenceText: "张霞是段福强的妈妈。",
            createdAt: createdAt,
            updatedAt: createdAt
        )

        _ = try await store.upsert(relationship)

        #expect(try await store.loadRelationships(includeInactive: false) == [relationship])
    }

    @Test func upsertAndLoadRoundTripsPersonToCurrentUserRelationship() async throws {
        let store = try makeStore()
        let createdAt = Date(timeIntervalSince1970: 120)
        let relationship = PersonRelationship(
            id: "rel-current-user",
            source: .personProfile(ContactID(rawValue: "person-zhang-xia")),
            target: .currentUser(),
            kind: .parentOf,
            customKindLabel: "妈妈",
            createdAt: createdAt,
            updatedAt: createdAt
        )

        _ = try await store.upsert(relationship)
        let loaded = try await store.loadRelationships(includeInactive: false)

        #expect(loaded == [relationship])
        #expect(loaded.first?.target.isCurrentUser == true)
    }

    @Test func relationshipsForPersonMatchesSourceOrTarget() async throws {
        let store = try makeStore()
        let zhangXia = ContactID(rawValue: "person-zhang-xia")
        let duanFuqiang = ContactID(rawValue: "person-duan-fuqiang")
        let unrelated = ContactID(rawValue: "person-unrelated")
        _ = try await store.upsert(PersonRelationship(id: "rel-source", source: .personProfile(zhangXia), target: .currentUser(), kind: .parentOf))
        _ = try await store.upsert(PersonRelationship(id: "rel-target", source: .personProfile(duanFuqiang), target: .personProfile(zhangXia), kind: .childOf))
        _ = try await store.upsert(PersonRelationship(id: "rel-other", source: .personProfile(unrelated), target: .currentUser(), kind: .friendOf))

        let relationships = try await store.relationships(for: zhangXia, includeInactive: false)

        #expect(relationships.map(\.id).sorted() == ["rel-source", "rel-target"])
    }

    @Test func currentUserRelationshipsMatchEitherEndpoint() async throws {
        let store = try makeStore()
        _ = try await store.upsert(PersonRelationship(id: "rel-target-current", source: .personProfile(ContactID(rawValue: "person-zhang-xia")), target: .currentUser(), kind: .parentOf))
        _ = try await store.upsert(PersonRelationship(id: "rel-source-current", source: .currentUser(), target: .personProfile(ContactID(rawValue: "person-friend")), kind: .friendOf))
        _ = try await store.upsert(PersonRelationship(id: "rel-other", source: .personProfile(ContactID(rawValue: "person-a")), target: .personProfile(ContactID(rawValue: "person-b")), kind: .knows))

        let relationships = try await store.currentUserRelationships(includeInactive: false)

        #expect(relationships.map(\.id).sorted() == ["rel-source-current", "rel-target-current"])
    }

    @Test func deletedRelationshipsAreHiddenByDefault() async throws {
        let store = try makeStore()
        _ = try await store.upsert(PersonRelationship(id: "rel-delete", source: .personProfile(ContactID(rawValue: "person-a")), target: .currentUser(), kind: .knows))

        try await store.markDeleted(id: "rel-delete", now: Date(timeIntervalSince1970: 200))

        #expect(try await store.loadRelationships(includeInactive: false).isEmpty)
        let inactive = try await store.loadRelationships(includeInactive: true)
        #expect(inactive.count == 1)
        #expect(inactive.first?.status == .deleted)
    }

    @Test func reassignPersonIDForMergeUpdatesPersonProfileEndpointsOnly() async throws {
        let store = try makeStore()
        let sourceID = ContactID(rawValue: "person-source")
        let targetID = ContactID(rawValue: "person-target")
        _ = try await store.upsert(PersonRelationship(id: "rel-source", source: .personProfile(sourceID), target: .currentUser(), kind: .friendOf))
        _ = try await store.upsert(PersonRelationship(id: "rel-target", source: .personProfile(ContactID(rawValue: "person-other")), target: .personProfile(sourceID), kind: .knows))
        _ = try await store.upsert(PersonRelationship(id: "rel-current", source: .currentUser(), target: .personProfile(ContactID(rawValue: "person-other")), kind: .knows))

        try await store.reassignPersonIDForMerge(sourceID: sourceID, targetID: targetID, now: Date(timeIntervalSince1970: 300))

        let relationships = try await store.loadRelationships(includeInactive: false)
        let relSource = relationships.first { $0.id == "rel-source" }
        let relTarget = relationships.first { $0.id == "rel-target" }
        let relCurrent = relationships.first { $0.id == "rel-current" }
        #expect(relSource?.source.personID == targetID)
        #expect(relSource?.target.isCurrentUser == true)
        #expect(relTarget?.target.personID == targetID)
        #expect(relCurrent?.source.isCurrentUser == true)
    }

    @Test func reassignPersonIDForMergeArchivesSelfLoops() async throws {
        let store = try makeStore()
        let sourceID = ContactID(rawValue: "person-source")
        let targetID = ContactID(rawValue: "person-target")
        _ = try await store.upsert(PersonRelationship(id: "rel-loop", source: .personProfile(sourceID), target: .personProfile(targetID), kind: .knows))

        try await store.reassignPersonIDForMerge(sourceID: sourceID, targetID: targetID, now: Date(timeIntervalSince1970: 400))

        #expect(try await store.loadRelationships(includeInactive: false).isEmpty)
        let all = try await store.loadRelationships(includeInactive: true)
        #expect(all.first?.status == .archived)
        #expect(all.first?.source.personID == targetID)
        #expect(all.first?.target.personID == targetID)
    }

    private func makeStore() throws -> SQLitePersonRelationshipStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SQLitePersonRelationshipStoreTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return try SQLitePersonRelationshipStore(databaseURL: root.appendingPathComponent("person-profiles.sqlite"))
    }
}
