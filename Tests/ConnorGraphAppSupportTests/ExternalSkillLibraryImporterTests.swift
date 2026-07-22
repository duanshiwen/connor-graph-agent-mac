import Foundation
import Testing
@testable import ConnorGraphAppSupport

@Suite("External skill library importer")
struct ExternalSkillLibraryImporterTests {
    @Test func discoversClaudeAndCodexSkillsAndCopiesSupportingFiles() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let claudeSkill = try writeSkill(root: fixture.claude, slug: "claude-review", name: "Claude Review")
        _ = try writeSkill(root: fixture.codex, slug: "codex-plan", name: "Codex Plan")
        try FileManager.default.createDirectory(at: claudeSkill.appendingPathComponent("scripts", isDirectory: true), withIntermediateDirectories: true)
        try "echo ok".write(to: claudeSkill.appendingPathComponent("scripts/run.sh"), atomically: true, encoding: .utf8)
        let importer = makeImporter(fixture: fixture)

        let discovery = importer.discover(destinationDirectory: fixture.destination)
        let result = try importer.importSkills(discovery.candidates, destinationDirectory: fixture.destination)

        #expect(Set(discovery.candidates.map(\.source)) == Set([.claudeCode, .codex]))
        #expect(result.importedIDs.count == 2)
        #expect(FileManager.default.fileExists(atPath: fixture.destination.appendingPathComponent("claude-review/scripts/run.sh").path))
        #expect(FileManager.default.fileExists(atPath: fixture.destination.appendingPathComponent("codex-plan/SKILL.md").path))
    }

    @Test func marksAndSkipsExistingDestinationWithoutOverwriting() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        _ = try writeSkill(root: fixture.claude, slug: "shared-skill", name: "External")
        let existing = try writeSkill(root: fixture.destination, slug: "shared-skill", name: "Existing")
        let importer = makeImporter(fixture: fixture)

        let discovery = importer.discover(destinationDirectory: fixture.destination)
        let candidate = try #require(discovery.candidates.first)
        let result = try importer.importSkills([candidate], destinationDirectory: fixture.destination)
        let retained = try String(contentsOf: existing.appendingPathComponent("SKILL.md"), encoding: .utf8)

        #expect(candidate.isAlreadyImported)
        #expect(result.importedIDs.isEmpty)
        #expect(result.skippedIDs == [candidate.id])
        #expect(retained.contains("name: Existing"))
    }

    @Test func invalidSkillDoesNotBlockValidCandidates() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        _ = try writeSkill(root: fixture.claude, slug: "valid-skill", name: "Valid")
        let invalid = fixture.codex.appendingPathComponent("invalid-skill", isDirectory: true)
        try FileManager.default.createDirectory(at: invalid, withIntermediateDirectories: true)
        try "# no frontmatter".write(to: invalid.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let discovery = makeImporter(fixture: fixture).discover(destinationDirectory: fixture.destination)

        #expect(discovery.candidates.map(\.slug) == ["valid-skill"])
        #expect(discovery.warnings.count == 1)
        #expect(discovery.warnings[0].contains("invalid-skill"))
    }

    @Test func defaultRootsRespectEnvironmentOverrides() {
        let roots = ExternalSkillLibraryImporter.defaultRoots(
            environment: ["CLAUDE_CONFIG_DIR": "/tmp/custom-claude", "CODEX_HOME": "/tmp/custom-codex"],
            homeDirectory: URL(fileURLWithPath: "/tmp/home", isDirectory: true)
        )

        #expect(roots[0].directoryURL.path == "/tmp/custom-claude/skills")
        #expect(roots[1].directoryURL.path == "/tmp/custom-codex/skills")
        #expect(roots.contains { $0.source == .cursor && $0.directoryURL.path == "/tmp/home/.cursor/skills" })
        #expect(roots.contains { $0.source == .openCode && $0.directoryURL.path == "/tmp/home/.config/opencode/skills" })
        #expect(roots.contains { $0.source == .agents && $0.directoryURL.path == "/tmp/home/.agents/skills" })
    }

    @Test func customRootMayPointDirectlyAtOneSkillPackage() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let skill = try writeSkill(root: fixture.root, slug: "custom-skill", name: "Custom Skill")
        let importer = ExternalSkillLibraryImporter(roots: [])

        let discovery = importer.discover(
            destinationDirectory: fixture.destination,
            additionalRoots: [ExternalSkillLibraryRoot(source: .custom, directoryURL: skill)]
        )

        #expect(discovery.candidates.map(\.slug) == ["custom-skill"])
        #expect(discovery.candidates.first?.source == .custom)
    }

    private func makeFixture() throws -> (root: URL, claude: URL, codex: URL, destination: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("external-skill-import-\(UUID().uuidString)", isDirectory: true)
        let claude = root.appendingPathComponent("claude", isDirectory: true)
        let codex = root.appendingPathComponent("codex", isDirectory: true)
        let destination = root.appendingPathComponent("destination", isDirectory: true)
        for directory in [claude, codex, destination] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return (root, claude, codex, destination)
    }

    private func makeImporter(fixture: (root: URL, claude: URL, codex: URL, destination: URL)) -> ExternalSkillLibraryImporter {
        ExternalSkillLibraryImporter(roots: [
            ExternalSkillLibraryRoot(source: .claudeCode, directoryURL: fixture.claude),
            ExternalSkillLibraryRoot(source: .codex, directoryURL: fixture.codex)
        ])
    }

    @discardableResult
    private func writeSkill(root: URL, slug: String, name: String) throws -> URL {
        let directory = root.appendingPathComponent(slug, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try """
        ---
        name: \(name)
        description: Imported test skill
        ---
        Follow the imported instructions.
        """.write(to: directory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        return directory
    }
}
