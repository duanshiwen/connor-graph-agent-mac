import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport
@testable import ConnorGraphAgentMac

@MainActor
struct ContactsFeatureModelTests {
    @Test func imageImporterRetainsTargetWhenSwiftUIDismissesBeforeCompletion() {
        let personID = ContactID(rawValue: "person-image-import")
        var state = ContactImageImporterState()

        state.present(for: personID)
        state.isPresented = false

        #expect(state.consumeTargetPersonID() == personID)
        #expect(state.targetPersonID == nil)
        #expect(state.isPresented == false)
    }

    @Test func reloadBuildsPresentationAndRepairsInvalidSelection() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let id = ContactID(rawValue: "person-one")
        _ = try await fixture.profileStore.upsert(PersonProfile(id: id, displayName: "张霞"))
        fixture.model.selectedContactID = ContactID(rawValue: "missing")

        await fixture.model.reload()

        #expect(fixture.model.profiles.map(\.id) == [id])
        #expect(fixture.model.contactRecords.map(\.id) == [id])
        #expect(fixture.model.presentation.rows.map(\.id) == [id])
        #expect(fixture.model.selectedContactID == nil)
    }

    @Test func displayTitleUsesCurrentUserProfileAndMissingFallback() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let id = ContactID(rawValue: "person-duan-fuqiang")
        _ = try await fixture.profileStore.upsert(PersonProfile(id: id, displayName: "段福强"))
        await fixture.model.reload()

        #expect(fixture.model.displayTitle(for: .currentUser()) == "我（当前用户）")
        #expect(fixture.model.displayTitle(for: .personProfile(id)) == "段福强")
        #expect(fixture.model.displayTitle(for: .personProfile(ContactID(rawValue: "missing"))) == "未知人物（missing）")
    }

    @Test func relationshipSaveAndMergeReassignEndpoints() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let sourceID = ContactID(rawValue: "person-source")
        let targetID = ContactID(rawValue: "person-target")
        await fixture.model.saveProfileDraft(PersonProfileDraft(id: sourceID, displayName: "旧档案"))
        await fixture.model.saveProfileDraft(PersonProfileDraft(id: targetID, displayName: "新档案"))
        let relationship = PersonRelationship(
            id: "rel-merge",
            source: .personProfile(sourceID),
            target: .currentUser(),
            kind: .friendOf,
            createdAt: Date(timeIntervalSince1970: 200),
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        #expect(await fixture.model.saveRelationship(relationship))
        #expect(fixture.model.currentUserRelationships().map(\.id) == [relationship.id])

        #expect(await fixture.model.mergeProfile(sourceID: sourceID, targetID: targetID))

        let reloaded = fixture.model.relationships.first { $0.id == relationship.id }
        #expect(reloaded?.source.personID == targetID)
        #expect(reloaded?.target.isCurrentUser == true)
        #expect(fixture.model.selectedContactID == targetID)
    }

    @Test func profileAndRelationshipDraftValidationPreserveExactMessages() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        await fixture.model.saveProfileDraft(PersonProfileDraft(displayName: "   "))
        #expect(fixture.model.errorMessage == "人物名称不能为空")

        let sourceID = ContactID(rawValue: "person-source")
        var missing = PersonRelationshipDraft(sourcePersonID: sourceID)
        missing.targetMode = .personProfile
        await fixture.model.saveRelationshipDraft(missing)
        #expect(fixture.model.errorMessage == "请选择关系目标人物")

        var selfDraft = PersonRelationshipDraft(sourcePersonID: sourceID)
        selfDraft.targetMode = .personProfile
        selfDraft.targetPersonID = sourceID
        await fixture.model.saveRelationshipDraft(selfDraft)
        #expect(fixture.model.errorMessage == "不能将人物关系指向自己")
    }

    @Test func systemSyncPersistsProfilesAndPublishesExactMessages() async throws {
        let record = ContactRecord(id: ContactID(rawValue: "system-person"), givenName: "系统联系人", emails: [])
        let fixture = try makeFixture(systemLoader: { [record] })
        defer { fixture.cleanup() }
        var settingsMessages: [String?] = []
        fixture.model.onEvent = { event in
            if case let .settingsMessageChanged(message) = event { settingsMessages.append(message) }
        }

        #expect(await fixture.model.syncSystemContactsNow())

        #expect(fixture.model.syncMessage == "已同步系统通讯录：1 个人物档案")
        #expect(settingsMessages.last == "已同步系统通讯录：1 个人物档案")
        #expect(try await fixture.profileStore.loadProfiles(includeInactive: false).map(\.id) == [record.id])
        #expect(fixture.model.isSyncingSystemContacts == false)
    }

    @Test func systemSyncPreservesExistingProfileImages() async throws {
        let id = ContactID(rawValue: "system-person-with-images")
        let record = ContactRecord(id: id, givenName: "更新后的姓名", emails: [])
        let fixture = try makeFixture(systemLoader: { [record] })
        defer { fixture.cleanup() }
        let paths = ["contacts/images/system-person-with-images/one.png", "contacts/images/system-person-with-images/two.jpg"]
        _ = try await fixture.profileStore.upsert(PersonProfile(id: id, displayName: "旧姓名", imageRelativePaths: paths))

        #expect(await fixture.model.syncSystemContactsNow())

        let synced = try #require(try await fixture.profileStore.profile(id: id))
        #expect(synced.displayName == "更新后的姓名")
        #expect(synced.imageRelativePaths == paths)
    }

    @Test func systemSyncFailureResetsLoadingAndReportsLocalizedMessage() async throws {
        struct Failure: LocalizedError { var errorDescription: String? { "通讯录权限被拒绝" } }
        let fixture = try makeFixture(systemLoader: { throw Failure() })
        defer { fixture.cleanup() }

        #expect(await fixture.model.syncSystemContactsNow() == false)
        #expect(fixture.model.syncMessage == "通讯录权限被拒绝")
        #expect(fixture.model.errorMessage == "通讯录权限被拒绝")
        #expect(fixture.model.isSyncingSystemContacts == false)
    }

    @Test func shutdownPreventsSystemContactsApplication() async throws {
        actor Gate {
            var continuation: CheckedContinuation<[ContactRecord], Never>?
            func wait() async -> [ContactRecord] { await withCheckedContinuation { continuation = $0 } }
            func resume(_ records: [ContactRecord]) { continuation?.resume(returning: records); continuation = nil }
        }
        let gate = Gate()
        let fixture = try makeFixture(systemLoader: { await gate.wait() })
        defer { fixture.cleanup() }
        fixture.model.syncSystemContacts()
        await Task.yield()
        fixture.model.shutdown()
        await gate.resume([ContactRecord(id: ContactID(rawValue: "late"), givenName: "Late", emails: [])])
        await fixture.model.waitForPendingOperations()

        #expect(fixture.model.profiles.isEmpty)
    }

    @Test func externalProfileWriteRefreshesVisibleContactsWithoutManualReload() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        await fixture.model.reload()
        let profile = PersonProfile(
            id: ContactID(rawValue: "agent-created-person"),
            displayName: "Agent Created"
        )

        _ = try await fixture.profileStore.upsert(profile)
        await Task.yield()
        await fixture.model.waitForPendingOperations()

        #expect(fixture.model.profiles.map(\.id) == [profile.id])
        #expect(fixture.model.contactRecords.map(\.id) == [profile.id])
        #expect(fixture.model.presentation.rows.map(\.id) == [profile.id])
    }

    @Test func profileImageIsOptionalAndCanBeAddedAndRemoved() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let id = ContactID(rawValue: "person-image")
        _ = try await fixture.profileStore.upsert(PersonProfile(id: id, displayName: "有头像的人"))
        await fixture.model.reload()
        #expect(fixture.model.imageURLs(for: id).isEmpty)

        let firstSourceURL = fixture.root.appendingPathComponent("first.png")
        let secondSourceURL = fixture.root.appendingPathComponent("second.jpg")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: firstSourceURL)
        try Data([0xFF, 0xD8, 0xFF]).write(to: secondSourceURL)
        await fixture.model.addProfileImages(from: [firstSourceURL, secondSourceURL], for: id)

        let storedURLs = fixture.model.imageURLs(for: id)
        #expect(storedURLs.count == 2)
        #expect(storedURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        #expect(storedURLs.allSatisfy { $0.deletingLastPathComponent().lastPathComponent == id.rawValue })
        #expect(fixture.model.profiles.first?.imageRelativePaths?.count == 2)

        await fixture.model.removeProfileImage(at: storedURLs[0], for: id)
        #expect(fixture.model.imageURLs(for: id).count == 1)
        await fixture.model.removeProfileImage(at: storedURLs[1], for: id)
        #expect(fixture.model.imageURLs(for: id).isEmpty)
        #expect(fixture.model.profiles.first?.imageRelativePaths == nil)
        #expect(storedURLs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test func orphanedStoredImagesAreRecoveredAndCanBeRemoved() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let id = ContactID(rawValue: "person-orphaned-images")
        _ = try await fixture.profileStore.upsert(PersonProfile(id: id, displayName: "恢复图片"))
        let sourceURL = fixture.root.appendingPathComponent("orphan.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: sourceURL)
        let imageStore = PersonProfileImageStore(applicationSupportDirectory: fixture.root)
        _ = try imageStore.importImage(at: sourceURL, personID: id)
        await fixture.model.reload()

        let recoveredURL = try #require(fixture.model.imageURLs(for: id).first)
        await fixture.model.removeProfileImage(at: recoveredURL, for: id)

        #expect(fixture.model.imageURLs(for: id).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: recoveredURL.path))
    }

    private func makeFixture(
        systemLoader: @escaping ContactsFeatureModel.SystemContactsLoader = { [] }
    ) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-contacts-feature-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let databaseURL = root.appendingPathComponent("person-profiles.sqlite")
        let profileStore = try SQLitePersonProfileStore(databaseURL: databaseURL)
        let relationshipStore = try SQLitePersonRelationshipStore(databaseURL: databaseURL)
        let model = ContactsFeatureModel(
            profileStore: profileStore,
            relationshipStore: relationshipStore,
            imageStore: PersonProfileImageStore(applicationSupportDirectory: root),
            systemContactsLoader: systemLoader
        )
        return Fixture(root: root, profileStore: profileStore, model: model)
    }

    private struct Fixture {
        let root: URL
        let profileStore: SQLitePersonProfileStore
        let model: ContactsFeatureModel
        @MainActor func cleanup() {
            model.shutdown()
            try? FileManager.default.removeItem(at: root)
        }
    }
}
