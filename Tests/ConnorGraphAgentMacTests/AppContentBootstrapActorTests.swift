import Foundation
import Testing
import ConnorGraphAppSupport
@testable import ConnorGraphAgentMac

@Suite("App Content Bootstrap Actor Tests")
struct AppContentBootstrapActorTests {
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
