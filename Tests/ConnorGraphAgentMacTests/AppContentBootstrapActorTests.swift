import Foundation
import Testing
import ConnorGraphAppSupport
@testable import ConnorGraphAgentMac

@Suite("App Content Bootstrap Actor Tests")
struct AppContentBootstrapActorTests {
    @Test func skillSnapshotIncludesDefinitionsAndPresentationBuiltOffMainActor() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-content-bootstrap-skills-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppStoragePaths.resolving(applicationSupportBaseDirectory: root)
        try paths.ensureDirectoryHierarchy(fileManager: .default)
        let packageDirectory = paths.skillsDirectory.appendingPathComponent("review-skill", isDirectory: true)
        try FileManager.default.createDirectory(at: packageDirectory, withIntermediateDirectories: true)
        try """
        ---
        name: Review Skill
        description: Reviews changes
        ---
        Review the requested changes.
        """.write(to: packageDirectory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let repository = AppSkillRuntimeRepository(storagePaths: paths)
        let definition = try repository.loadSkill(
            slug: "review-skill",
            scope: .home,
            skillURL: packageDirectory.appendingPathComponent("SKILL.md")
        )
        try repository.save(definition)

        let snapshot = await AppContentBootstrapActor().load(paths: paths, governanceConfig: .default)
        let skills = try #require(snapshot.skills.value)

        #expect(skills.definitions.map(\.slug) == ["review-skill"])
        #expect(skills.presentation.cards.map(\.id) == ["review-skill"])
        #expect(skills.presentation.summary.total == 1)
    }

    @Test func oneDomainFailureDoesNotCancelIndependentDomains() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-content-bootstrap-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        try paths.ensureDirectoryHierarchy()
        let brokenSkillDirectory = paths.skillsDirectory.appendingPathComponent("broken-skill", isDirectory: true)
        try FileManager.default.createDirectory(at: brokenSkillDirectory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: brokenSkillDirectory.appendingPathComponent("skill-runtime.json"))

        let snapshot = await AppContentBootstrapActor().load(paths: paths, governanceConfig: .default)

        #expect(snapshot.skills.value == nil)
        #expect(snapshot.skills.failureMessage != nil)
        #expect(snapshot.productOS.value != nil)
        #expect(snapshot.tasks.value != nil)
        #expect(snapshot.sources.value != nil)
        #expect(snapshot.browserHistory.value != nil)
    }
}
