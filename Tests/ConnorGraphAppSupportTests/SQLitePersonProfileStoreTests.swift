import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("SQLite Person Profile Store Tests")
struct SQLitePersonProfileStoreTests {
    @Test func newDatabaseLoadsEmptyProfiles() async throws {
        let store = try makeStore()

        let profiles = try await store.loadProfiles(includeInactive: false)

        #expect(profiles.isEmpty)
    }

    @Test func upsertAndLoadRoundTripsPersonWithoutContactMethods() async throws {
        let store = try makeStore()
        let profile = PersonProfile(
            id: ContactID(rawValue: "person-wang"),
            displayName: "小王",
            aliases: ["王同学"],
            notes: "朋友的朋友",
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )

        _ = try await store.upsert(profile)
        let loaded = try await store.loadProfiles(includeInactive: false)

        #expect(loaded == [profile])
    }

    @Test func upsertUpdatesExistingProfile() async throws {
        let store = try makeStore()
        let id = ContactID(rawValue: "person-alice")
        _ = try await store.upsert(PersonProfile(id: id, displayName: "Alice"))

        let updated = PersonProfile(id: id, displayName: "Alice Wang", organizationName: "Connor Labs")
        _ = try await store.upsert(updated)

        let loaded = try await store.loadProfiles(includeInactive: false)
        #expect(loaded.count == 1)
        #expect(loaded.first?.displayName == "Alice Wang")
        #expect(loaded.first?.organizationName == "Connor Labs")
    }

    @Test func searchMatchesNamesAliasesContactsAndNotes() async throws {
        let store = try makeStore()
        let profile = PersonProfile(
            id: ContactID(rawValue: "person-search"),
            displayName: "Alice Wang",
            aliases: ["小艾"],
            emails: [ContactEmailAddress(label: "work", email: "alice@example.com")],
            phones: [PersonPhoneNumber(label: "mobile", number: "+86 138 0000 0000")],
            organizationName: "Connor Labs",
            jobTitle: "Designer",
            notes: "杭州朋友"
        )
        _ = try await store.upsert(profile)

        #expect(try await store.searchProfiles(query: "alice", includeInactive: false).map(\.id) == [profile.id])
        #expect(try await store.searchProfiles(query: "小艾", includeInactive: false).map(\.id) == [profile.id])
        #expect(try await store.searchProfiles(query: "example", includeInactive: false).map(\.id) == [profile.id])
        #expect(try await store.searchProfiles(query: "138", includeInactive: false).map(\.id) == [profile.id])
        #expect(try await store.searchProfiles(query: "Connor", includeInactive: false).map(\.id) == [profile.id])
        #expect(try await store.searchProfiles(query: "杭州", includeInactive: false).map(\.id) == [profile.id])
    }

    @Test func deletedProfilesAreHiddenByDefaultButCanBeIncluded() async throws {
        let store = try makeStore()
        let id = ContactID(rawValue: "person-delete")
        _ = try await store.upsert(PersonProfile(id: id, displayName: "待删除"))

        try await store.markDeleted(id: id, now: Date(timeIntervalSince1970: 100))

        #expect(try await store.loadProfiles(includeInactive: false).isEmpty)
        #expect(try await store.searchProfiles(query: "待删除", includeInactive: false).isEmpty)

        let inactive = try await store.loadProfiles(includeInactive: true)
        #expect(inactive.count == 1)
        #expect(inactive.first?.status == .deleted)
    }

    @Test func mergeMovesSourceDataIntoTargetAndHidesSourceByDefault() async throws {
        let store = try makeStore()
        let sourceID = ContactID(rawValue: "person-source")
        let targetID = ContactID(rawValue: "person-target")
        let source = PersonProfile(
            id: sourceID,
            displayName: "小王",
            aliases: ["王同学"],
            emails: [ContactEmailAddress(label: "old", email: "old@example.com")],
            phones: [PersonPhoneNumber(label: "mobile", number: "13800000000")],
            addresses: [PersonPostalAddress(label: "home", value: "杭州")],
            notes: "source notes"
        )
        let target = PersonProfile(
            id: targetID,
            displayName: "王诗闻",
            aliases: ["Shiwen"],
            emails: [ContactEmailAddress(label: "work", email: "work@example.com")],
            notes: "target notes"
        )
        _ = try await store.upsert(source)
        _ = try await store.upsert(target)

        let merged = try await store.merge(sourceID: sourceID, targetID: targetID, now: Date(timeIntervalSince1970: 200))

        #expect(merged.id == targetID)
        #expect(merged.displayName == "王诗闻")
        #expect(merged.aliases.contains("小王"))
        #expect(merged.aliases.contains("王同学"))
        #expect(merged.aliases.contains("Shiwen"))
        #expect(merged.emails.map(\.email).contains("old@example.com"))
        #expect(merged.emails.map(\.email).contains("work@example.com"))
        #expect(merged.phones.map(\.number).contains("13800000000"))
        #expect(merged.addresses.map(\.value).contains("杭州"))

        let active = try await store.loadProfiles(includeInactive: false)
        #expect(active.map(\.id) == [targetID])

        let all = try await store.loadProfiles(includeInactive: true)
        let sourceAfterMerge = all.first { $0.id == sourceID }
        #expect(sourceAfterMerge?.status == .merged)
        #expect(sourceAfterMerge?.mergedIntoID == targetID)
    }

    @Test func profileByIDReturnsMergedAndDeletedWhenRequestedDirectly() async throws {
        let store = try makeStore()
        let id = ContactID(rawValue: "person-direct")
        _ = try await store.upsert(PersonProfile(id: id, displayName: "Direct"))
        try await store.markDeleted(id: id, now: Date(timeIntervalSince1970: 1))

        let profile = try await store.profile(id: id)

        #expect(profile?.id == id)
        #expect(profile?.status == .deleted)
    }

    @Test func successfulMutationsPublishStoreScopedChangeNotifications() async throws {
        let store = try makeStore()
        let recorder = PersonProfileStoreChangeNotificationRecorder()
        let observer = NotificationCenter.default.addObserver(
            forName: .connorPersonProfileStoreDidChange,
            object: store,
            queue: nil
        ) { recorder.record($0) }
        defer { NotificationCenter.default.removeObserver(observer) }
        let sourceID = ContactID(rawValue: "person-notification-source")
        let targetID = ContactID(rawValue: "person-notification-target")

        _ = try await store.upsert(PersonProfile(id: sourceID, displayName: "Source"))
        _ = try await store.upsert(PersonProfile(id: targetID, displayName: "Target"))
        try await store.markDeleted(id: sourceID, now: Date(timeIntervalSince1970: 10))
        _ = try await store.upsert(PersonProfile(id: sourceID, displayName: "Source"))
        _ = try await store.merge(sourceID: sourceID, targetID: targetID, now: Date(timeIntervalSince1970: 20))

        let notifications = recorder.snapshot()
        #expect(notifications.compactMap(Self.reason(from:)) == [.upserted, .upserted, .deleted, .upserted, .merged])
        #expect(Self.personIDs(from: notifications.last) == [sourceID.rawValue, targetID.rawValue])
    }

    @Test func failedMutationDoesNotPublishChangeNotification() async throws {
        let store = try makeStore()
        let recorder = PersonProfileStoreChangeNotificationRecorder()
        let observer = NotificationCenter.default.addObserver(
            forName: .connorPersonProfileStoreDidChange,
            object: store,
            queue: nil
        ) { recorder.record($0) }
        defer { NotificationCenter.default.removeObserver(observer) }

        await #expect(throws: SQLitePersonProfileStoreError.self) {
            try await store.markDeleted(id: ContactID(rawValue: "missing"), now: Date())
        }

        #expect(recorder.snapshot().isEmpty)
    }

    private static func reason(from notification: Notification) -> PersonProfileStoreChangeReason? {
        guard let rawValue = notification.userInfo?[PersonProfileStoreChangeNotificationUserInfoKey.reason] as? String else {
            return nil
        }
        return PersonProfileStoreChangeReason(rawValue: rawValue)
    }

    private static func personIDs(from notification: Notification?) -> [String] {
        notification?.userInfo?[PersonProfileStoreChangeNotificationUserInfoKey.personIDs] as? [String] ?? []
    }

    private func makeStore() throws -> SQLitePersonProfileStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SQLitePersonProfileStoreTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return try SQLitePersonProfileStore(databaseURL: root.appendingPathComponent("person-profiles.sqlite"))
    }
}

private final class PersonProfileStoreChangeNotificationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var notifications: [Notification] = []

    func record(_ notification: Notification) {
        lock.lock(); defer { lock.unlock() }
        notifications.append(notification)
    }

    func snapshot() -> [Notification] {
        lock.lock(); defer { lock.unlock() }
        return notifications
    }
}
