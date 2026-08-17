import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Im Friend Person Provisioner Tests")
struct ImFriendPersonProvisionerTests {
    @Test func createsProfileForUnboundFriendAndBindsIt() async throws {
        let fixture = try makeFixture()
        try await fixture.imStore.upsertFriends([ImFriend(
            userId: 7,
            username: "alice",
            nickname: "爱丽丝",
            email: "alice@example.com"
        )])

        let reconciled = try await fixture.provisioner.reconcile(friends: try await fixture.imStore.loadFriends())

        let profile = try #require(try await fixture.profileStore.loadProfiles(includeInactive: true).first)
        #expect(profile.displayName == "爱丽丝")
        #expect(profile.source == ImFriendPersonProvisioner.connorFriendSource)
        #expect(profile.id == ImFriendPersonProvisioner.profileID(for: 7))
        #expect(profile.emails.map(\.email) == ["alice@example.com"])
        #expect(try await fixture.imStore.friend(userId: 7)?.personProfileID == profile.id.rawValue)
        #expect(reconciled.first?.personProfileID == profile.id.rawValue)
    }

    @Test func retriesWithStableProfileWithoutCreatingDuplicates() async throws {
        let fixture = try makeFixture()
        let existing = PersonProfile(
            id: ImFriendPersonProvisioner.profileID(for: 7),
            displayName: "爱丽丝",
            source: ImFriendPersonProvisioner.connorFriendSource
        )
        _ = try await fixture.profileStore.upsert(existing)
        try await fixture.imStore.upsertFriends([ImFriend(userId: 7, username: "alice", nickname: "爱丽丝")])

        _ = try await fixture.provisioner.reconcile(friends: try await fixture.imStore.loadFriends())

        let profiles = try await fixture.profileStore.loadProfiles(includeInactive: true)
        #expect(profiles.map(\.id) == [existing.id])
        #expect(try await fixture.imStore.friend(userId: 7)?.personProfileID == existing.id.rawValue)
    }

    @Test func rebindsFriendToMergedTargetProfile() async throws {
        let fixture = try makeFixture()
        let sourceID = ContactID(rawValue: "person-source")
        let targetID = ContactID(rawValue: "person-target")
        _ = try await fixture.profileStore.upsert(PersonProfile(id: sourceID, displayName: "旧人物"))
        _ = try await fixture.profileStore.upsert(PersonProfile(id: targetID, displayName: "目标人物"))
        _ = try await fixture.profileStore.merge(sourceID: sourceID, targetID: targetID, now: Date())
        try await fixture.imStore.upsertFriends([
            ImFriend(userId: 8, username: "bob", personProfileID: sourceID.rawValue)
        ])

        let reconciled = try await fixture.provisioner.reconcile(friends: try await fixture.imStore.loadFriends())

        #expect(reconciled.first?.personProfileID == targetID.rawValue)
        #expect(try await fixture.imStore.friend(userId: 8)?.personProfileID == targetID.rawValue)
    }

    @Test func reusesSingleActiveProfileWithExactEmail() async throws {
        let fixture = try makeFixture()
        let existing = PersonProfile(
            id: ContactID(rawValue: "person-alice"),
            displayName: "Alice Wang",
            emails: [ContactEmailAddress(email: "Alice@Example.com")]
        )
        _ = try await fixture.profileStore.upsert(existing)
        try await fixture.imStore.upsertFriends([
            ImFriend(userId: 7, username: "alice", email: " alice@example.com ")
        ])

        _ = try await fixture.provisioner.reconcile(friends: try await fixture.imStore.loadFriends())

        #expect(try await fixture.profileStore.loadProfiles(includeInactive: true).map(\.id) == [existing.id])
        #expect(try await fixture.imStore.friend(userId: 7)?.personProfileID == existing.id.rawValue)
    }

    @Test func keepsExistingFriendBindingUntouched() async throws {
        let fixture = try makeFixture()
        let bound = PersonProfile(id: ContactID(rawValue: "person-bound"), displayName: "已绑定人物")
        _ = try await fixture.profileStore.upsert(bound)
        try await fixture.imStore.upsertFriends([ImFriend(
            userId: 8,
            username: "bob",
            nickname: "鲍勃",
            personProfileID: bound.id.rawValue
        )])

        _ = try await fixture.provisioner.reconcile(friends: try await fixture.imStore.loadFriends())

        #expect(try await fixture.profileStore.loadProfiles(includeInactive: true).map(\.id) == [bound.id])
        #expect(try await fixture.imStore.friend(userId: 8)?.personProfileID == bound.id.rawValue)
    }

    @Test func mergesAutoProvisionedProfileIntoBoundTarget() async throws {
        let fixture = try makeFixture()
        let targetID = ContactID(rawValue: "person-target")
        _ = try await fixture.profileStore.upsert(PersonProfile(id: targetID, displayName: "目标人物"))
        // 好友 7 之前已自动建档（connor-friend-7），随后被用户绑定到目标人物。
        let stableID = ImFriendPersonProvisioner.profileID(for: 7)
        _ = try await fixture.profileStore.upsert(PersonProfile(
            id: stableID,
            displayName: "爱丽丝",
            emails: [ContactEmailAddress(email: "alice@example.com")],
            source: ImFriendPersonProvisioner.connorFriendSource
        ))
        try await fixture.imStore.upsertFriends([
            ImFriend(userId: 7, username: "alice", nickname: "爱丽丝", email: "alice@example.com", personProfileID: targetID.rawValue)
        ])

        _ = try await fixture.provisioner.reconcile(friends: try await fixture.imStore.loadFriends())

        let profiles = try await fixture.profileStore.loadProfiles(includeInactive: true)
        let source = try #require(profiles.first { $0.id == stableID })
        #expect(source.status == .merged)
        #expect(source.mergedIntoID == targetID)
        let target = try #require(profiles.first { $0.id == targetID })
        #expect(target.status == .active)
        #expect(target.emails.map(\.email).contains("alice@example.com"))
        // 好友记录保留且重定向到目标人物，而不是被删除。
        #expect(try await fixture.imStore.friend(userId: 7)?.personProfileID == targetID.rawValue)
    }

    @Test func reconcilesSyncedFriendBindingMetadataFromL4Entity() async throws {
        let fixture = try makeFixture()
        let targetID = ContactID(rawValue: "person-target")
        _ = try await fixture.profileStore.upsert(PersonProfile(id: targetID, displayName: "目标人物"))
        let stableID = ImFriendPersonProvisioner.profileID(for: 7)
        _ = try await fixture.profileStore.upsert(PersonProfile(
            id: stableID,
            displayName: "爱丽丝",
            emails: [ContactEmailAddress(email: "alice@example.com")],
            source: ImFriendPersonProvisioner.connorFriendSource
        ))
        // 好友未绑定；安卓同步来的人物实体携带 connor_friend_user_id。
        try await fixture.imStore.upsertFriends([ImFriend(userId: 7, username: "alice", nickname: "爱丽丝")])
        let entity = MemoryOSEntity(
            id: "l4-entity:person:目标人物",
            stableKey: "person:目标人物",
            entityType: "person",
            name: "目标人物",
            metadata: ["connor_friend_user_id": "7", "connor_friend_username": "alice"]
        )

        _ = try await fixture.provisioner.reconcileSyncedFriendBindings(entities: [entity])

        #expect(try await fixture.imStore.friend(userId: 7)?.personProfileID == targetID.rawValue)
        let profiles = try await fixture.profileStore.loadProfiles(includeInactive: true)
        #expect(profiles.first { $0.id == stableID }?.status == .merged)
        #expect(profiles.first { $0.id == stableID }?.mergedIntoID == targetID)
    }

    @Test func syncReconcilerSkipsAmbiguousNameMatches() async throws {
        let fixture = try makeFixture()
        // 两个同名人物的 active 档案 → 无法唯一匹配，跳过合并，不产生副作用。
        _ = try await fixture.profileStore.upsert(PersonProfile(id: ContactID(rawValue: "person-a"), displayName: "同名"))
        _ = try await fixture.profileStore.upsert(PersonProfile(id: ContactID(rawValue: "person-b"), displayName: "同名"))
        try await fixture.imStore.upsertFriends([ImFriend(userId: 7, username: "alice", nickname: "爱丽丝")])
        let entity = MemoryOSEntity(
            id: "l4-entity:person:同名",
            stableKey: "person:同名",
            entityType: "person",
            name: "同名",
            metadata: ["connor_friend_user_id": "7"]
        )

        let applied = try await fixture.provisioner.reconcileSyncedFriendBindings(entities: [entity])

        #expect(applied.applied.isEmpty)
        #expect(try await fixture.imStore.friend(userId: 7)?.personProfileID == nil)
        let profiles = try await fixture.profileStore.loadProfiles(includeInactive: true)
        #expect(profiles.allSatisfy { $0.status == .active })
    }

    @Test func degradesGracefullyWithoutProfileStore() async throws {
        let root = try makeTemporaryDirectory()
        let imStore = try SQLiteImStore(databaseURL: root.appendingPathComponent("im.sqlite"))
        try await imStore.upsertFriends([ImFriend(userId: 9, username: "carol", nickname: "卡罗尔")])
        let provisioner = ImFriendPersonProvisioner(profileStore: nil, imStore: imStore)

        let reconciled = try await provisioner.reconcile(friends: try await imStore.loadFriends())

        #expect(reconciled.first?.personProfileID == nil)
        #expect(reconciled.first?.userId == 9)
    }

    // MARK: - Helpers

    private struct Fixture {
        let imStore: SQLiteImStore
        let profileStore: SQLitePersonProfileStore
        let provisioner: ImFriendPersonProvisioner
    }

    private func makeFixture() throws -> Fixture {
        let root = try makeTemporaryDirectory()
        let imStore = try SQLiteImStore(databaseURL: root.appendingPathComponent("im.sqlite"))
        let profileStore = try SQLitePersonProfileStore(databaseURL: root.appendingPathComponent("profiles.sqlite"))
        let provisioner = ImFriendPersonProvisioner(profileStore: profileStore, imStore: imStore)
        return Fixture(imStore: imStore, profileStore: profileStore, provisioner: provisioner)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImFriendPersonProvisionerTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
