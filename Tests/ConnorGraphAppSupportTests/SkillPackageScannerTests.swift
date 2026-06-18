import Foundation
import Testing
import ConnorGraphAppSupport
import ConnorGraphCore

private func temporarySkillScannerRoot(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("ConnorSkillScannerTests-\(name)", isDirectory: true)
}

private func writeCommercialSkill(root: URL, slug: String, name: String, extraFrontmatter: String = "") throws -> URL {
    let directory = root.appendingPathComponent(slug, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let skill = directory.appendingPathComponent("SKILL.md")
    try """
    ---
    name: \(name)
    description: \(name) description
    \(extraFrontmatter)
    ---
    # \(name)

    Follow \(name).
    """.write(to: skill, atomically: true, encoding: .utf8)
    return skill
}

@Suite("Commercial Skill Package Scanner Tests")
struct SkillPackageScannerTests {
    @Test func scansOnlyApplicationUserSkillsByDefault() throws {
        let root = temporarySkillScannerRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let global = root.appendingPathComponent("global", isDirectory: true)
        let user = root.appendingPathComponent("user", isDirectory: true)
        let project = root.appendingPathComponent("project", isDirectory: true)
        let projectSkills = project.appendingPathComponent(".agents/skills", isDirectory: true)
        _ = try writeCommercialSkill(root: global, slug: "review", name: "Global Review")
        _ = try writeCommercialSkill(root: user, slug: "review", name: "User Review")
        _ = try writeCommercialSkill(root: projectSkills, slug: "project-only", name: "Project Only")
        _ = try writeCommercialSkill(root: user, slug: "writer", name: "Writer")
        let storagePaths = AppStoragePaths(applicationSupportDirectory: root, skillsDirectory: user)
        let scanner = SkillPackageScanner()

        let snapshot = scanner.scan(storagePaths: storagePaths)

        #expect(snapshot.packages.count == 2)
        #expect(snapshot.resolution(slug: "project-only") == nil)
        let review = try #require(snapshot.resolution(slug: "review"))
        #expect(review.candidates.map(\.sourceTier) == [.user])
        #expect(review.selected?.manifest.name == "User Review")
        #expect(review.warnings.isEmpty)
        let writer = try #require(snapshot.resolution(slug: "writer"))
        #expect(writer.selected?.sourceTier == .user)
    }

    @Test func createsProductOSDefinitionsFromSelectedPackages() throws {
        let root = temporarySkillScannerRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let user = root.appendingPathComponent("user", isDirectory: true)
        _ = try writeCommercialSkill(root: user, slug: "graph-review", name: "Graph Review", extraFrontmatter: """
        requiredSources: [kb-source]
        tags: [graph]
        x-connor:
          requiredCapabilities: [readSession, proposeGraphWrite]
          graphContextPolicy: askToWrite
        """)
        let storagePaths = AppStoragePaths(applicationSupportDirectory: root, skillsDirectory: user)
        let scanner = SkillPackageScanner()

        let definitions = scanner.productOSSkillDefinitions(from: scanner.scan(storagePaths: storagePaths))

        let definition = try #require(definitions.first)
        #expect(definition.id == "graph-review")
        #expect(definition.displayName == "Graph Review")
        #expect(definition.scope == .home)
        #expect(definition.requiredCapabilities == [.readSession, .proposeGraphWrite])
        #expect(definition.graphContextPolicy == .askToWrite)
        #expect(definition.tags.contains("graph"))
        #expect(definition.tags.contains("user"))
    }

    @Test func reportsInvalidSkillsWithoutFailingWholeScan() throws {
        let root = temporarySkillScannerRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let user = root.appendingPathComponent("user", isDirectory: true)
        _ = try writeCommercialSkill(root: user, slug: "valid-skill", name: "Valid")
        let invalidDir = user.appendingPathComponent("invalid-skill", isDirectory: true)
        try FileManager.default.createDirectory(at: invalidDir, withIntermediateDirectories: true)
        try "# Missing frontmatter".write(to: invalidDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let storagePaths = AppStoragePaths(applicationSupportDirectory: root, skillsDirectory: user)

        let snapshot = SkillPackageScanner().scan(storagePaths: storagePaths)

        #expect(snapshot.packages.map(\.slug.rawValue) == ["valid-skill"])
        #expect(snapshot.warnings.first?.contains("invalid-skill") == true)
    }

    @Test func ignoresHiddenFlagForNonBundledSkillsButKeepsBundledHidden() throws {
        let root = temporarySkillScannerRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundled = root.appendingPathComponent("bundled", isDirectory: true)
        let user = root.appendingPathComponent("user", isDirectory: true)
        _ = try writeCommercialSkill(root: bundled, slug: "internal-helper", name: "Internal Helper", extraFrontmatter: "hidden: true")
        _ = try writeCommercialSkill(root: user, slug: "user-helper", name: "User Helper", extraFrontmatter: "hidden: true")
        let storagePaths = AppStoragePaths(applicationSupportDirectory: root, skillsDirectory: user)
        let scanner = SkillPackageScanner(bundledSkillsDirectory: bundled)

        let snapshot = scanner.scan(storagePaths: storagePaths)

        let bundledPackage = try #require(snapshot.resolution(slug: "internal-helper")?.selected)
        #expect(bundledPackage.manifest.hidden == true)
        let userPackage = try #require(snapshot.resolution(slug: "user-helper")?.selected)
        #expect(userPackage.manifest.hidden == false)
        #expect(userPackage.manifest.warnings.contains { $0.contains("only bundled Connor skills may be hidden") })
    }
}
