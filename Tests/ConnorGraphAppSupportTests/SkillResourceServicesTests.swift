import Foundation
import Testing
import ConnorGraphAppSupport
import ConnorGraphCore

private func makeResourceSkillPackage(slug: String = "skill") -> SkillPackage {
    SkillPackage(
        id: SkillPackageID("user:/tmp/\(slug)"),
        slug: SkillSlug(slug),
        sourceTier: .user,
        manifest: SkillManifest(name: "Skill", description: "Resource skill"),
        instructions: "Do resource work.",
        packagePath: "/tmp/\(slug)",
        skillFilePath: "/tmp/\(slug)/SKILL.md"
    )
}

@Suite("Commercial Skill Resource Services Tests")
struct SkillResourceServicesTests {
    @Test func substitutesSkillDirectoryVariables() {
        let package = makeResourceSkillPackage(slug: "visualizer")
        let rendered = SkillResourceService().substituteSkillDirectoryVariables(in: "Run ${CONNOR_SKILL_DIR}/scripts/a.py and ${CLAUDE_SKILL_DIR}/templates/t.md", package: package)

        #expect(rendered.contains("/tmp/visualizer/scripts/a.py"))
        #expect(rendered.contains("/tmp/visualizer/templates/t.md"))
    }

    @Test func loadsSupportingResourceInsidePackage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ConnorSkillResourceTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let templateDir = root.appendingPathComponent("templates", isDirectory: true)
        try FileManager.default.createDirectory(at: templateDir, withIntermediateDirectories: true)
        try "Hello template".write(to: templateDir.appendingPathComponent("brief.md"), atomically: true, encoding: .utf8)
        var package = makeResourceSkillPackage(slug: "with-resource")
        package.packagePath = root.path

        let resource = try SkillResourceService().loadSupportingResource(relativePath: "templates/brief.md", package: package)

        #expect(resource.relativePath == "templates/brief.md")
        #expect(resource.preview == "Hello template")
        #expect(resource.byteCount == "Hello template".utf8.count)
    }

    @Test func rejectsResourceOutsidePackage() throws {
        var package = makeResourceSkillPackage(slug: "safe")
        package.packagePath = "/tmp/safe"

        do {
            _ = try SkillResourceService().loadSupportingResource(relativePath: "../secret.txt", package: package)
            Issue.record("Expected outside package access to fail")
        } catch let error as SkillResourceError {
            #expect(error == .outsidePackage("../secret.txt"))
        }
    }

    @Test func detectsShellDynamicContextAsGovernedPlaceholder() {
        let text = """
        Before
        !git diff HEAD
        After
        """
        let result = SkillResourceService().detectDynamicContextPlaceholders(in: text, shellExecutionEnabled: false)

        #expect(result.placeholders.count == 1)
        #expect(result.placeholders[0].command == "git diff HEAD")
        #expect(result.rendered.contains("shell command execution disabled"))
    }
}
