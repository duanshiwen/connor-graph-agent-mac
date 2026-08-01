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
