import AppKit
import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore
import ConnorGraphAppSupport
@testable import ConnorGraphAgentMac

@MainActor
struct AppViewModelPersonRelationshipTests {
    @Test func displayTitleForCurrentUserEndpointIsUserFacing() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        #expect(fixture.viewModel.displayTitle(for: .currentUser()) == "我（当前用户）")
    }

    @Test func displayTitleForPersonProfileEndpointUsesCurrentProfileName() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let personID = ContactID(rawValue: "person-duan-fuqiang")
        fixture.viewModel.personProfiles = [PersonProfile(id: personID, displayName: "段福强")]

        #expect(fixture.viewModel.displayTitle(for: .personProfile(personID)) == "段福强")

        fixture.viewModel.personProfiles = [PersonProfile(id: personID, displayName: "福强")]
        #expect(fixture.viewModel.displayTitle(for: .personProfile(personID)) == "福强")
    }

    @Test func displayTitleForMissingPersonProfileEndpointFallsBackToID() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let personID = ContactID(rawValue: "person-missing")

        #expect(fixture.viewModel.displayTitle(for: .personProfile(personID)) == "未知人物（person-missing）")
    }

    @Test func saveAndReloadPersonRelationshipUpdatesPublishedState() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let relationship = PersonRelationship(
            id: "rel-zhang-xia-current-user",
            source: .personProfile(ContactID(rawValue: "person-zhang-xia")),
            target: .currentUser(),
            kind: .parentOf,
            customKindLabel: "妈妈",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        await fixture.viewModel.savePersonRelationship(relationship)

        #expect(fixture.viewModel.personRelationships == [relationship])
        #expect(fixture.viewModel.currentUserRelationships().map(\.id) == [relationship.id])
    }

    @Test func mergePersonProfileReassignsRelationshipEndpoints() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let sourceID = ContactID(rawValue: "person-source")
        let targetID = ContactID(rawValue: "person-target")
        await fixture.viewModel.savePersonProfileDraft(PersonProfileDraft(id: sourceID, displayName: "旧档案"))
        await fixture.viewModel.savePersonProfileDraft(PersonProfileDraft(id: targetID, displayName: "新档案"))
        let relationship = PersonRelationship(
            id: "rel-merge",
            source: .personProfile(sourceID),
            target: .currentUser(),
            kind: .friendOf,
            createdAt: Date(timeIntervalSince1970: 200),
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        await fixture.viewModel.savePersonRelationship(relationship)

        await fixture.viewModel.mergePersonProfile(sourceID: sourceID, targetID: targetID)

        let reloaded = fixture.viewModel.personRelationships.first { $0.id == relationship.id }
        #expect(reloaded?.source.personID == targetID)
        #expect(reloaded?.target.isCurrentUser == true)
    }

    private func makeFixture() throws -> Fixture {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-app-vm-person-relationships-\(UUID().uuidString)", isDirectory: true)
        let paths = AppStoragePaths.resolving(applicationSupportBaseDirectory: root)
        try paths.ensureDirectoryHierarchy(fileManager: .default)
        let graphRepository = try AppGraphRepository.bootstrap(paths: paths)
        let viewModel = AppViewModel(
            entities: [],
            statements: [],
            observeLogEntries: [],
            repository: graphRepository,
            databasePath: paths.databaseURL.path,
            storagePaths: paths
        )
        return Fixture(root: root, viewModel: viewModel)
    }

    private struct Fixture {
        var root: URL
        var viewModel: AppViewModel

        func cleanup() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
