import Foundation
import Testing
import ConnorGraphAppSupport
import ConnorGraphCore

private func makeLifecycleSkillPackage(slug: String = "skill") -> SkillPackage {
    SkillPackage(
        id: SkillPackageID("user:/tmp/\(slug)"),
        slug: SkillSlug(slug),
        sourceTier: .user,
        manifest: SkillManifest(name: "Skill", description: "Lifecycle skill"),
        instructions: "Do lifecycle work.",
        packagePath: "/tmp/\(slug)",
        skillFilePath: "/tmp/\(slug)/SKILL.md"
    )
}

@Suite("Commercial Skill Lifecycle Services Tests")
struct SkillLifecycleServicesTests {
    @Test func buildsLifecycleRecordFromPackageMetadata() {
        var package = makeLifecycleSkillPackage(slug: "stable-skill")
        package.manifest.version = "1.2.3"
        package.manifest.publisher = "Connor"
        package.manifest.connor.lifecycle = SkillLifecycleState.stable

        let record = SkillLifecycleService().lifecycleRecord(for: package)

        #expect(record.slug == "stable-skill")
        #expect(record.version == "1.2.3")
        #expect(record.publisher == "Connor")
        #expect(record.lifecycle == SkillLifecycleState.stable)
        #expect(record.installationState == SkillInstallationState.enabled)
    }

    @Test func deprecatedSkillDefaultsToDisabledLifecycleRecord() {
        var package = makeLifecycleSkillPackage(slug: "old-skill")
        package.manifest.connor.lifecycle = SkillLifecycleState.deprecated

        let record = SkillLifecycleService().lifecycleRecord(for: package)

        #expect(record.installationState == SkillInstallationState.disabled)
        #expect(record.lifecycle == SkillLifecycleState.deprecated)
    }

    @Test func computesPackageIntegrityForSkillAndSupportingFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ConnorSkillLifecycleTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("examples", isDirectory: true), withIntermediateDirectories: true)
        try "skill".write(to: root.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try "example".write(to: root.appendingPathComponent("examples/a.md"), atomically: true, encoding: .utf8)
        var package = makeLifecycleSkillPackage(slug: "integrity")
        package.packagePath = root.path
        package.supportingFiles = ["examples/a.md"]

        let integrity = SkillLifecycleService().integrity(for: package)

        #expect(integrity.fileCount == 2)
        #expect(integrity.totalBytes == "skill".utf8.count + "example".utf8.count)
        #expect(integrity.fileDigests.keys.sorted() == ["SKILL.md", "examples/a.md"])
    }

    @Test func exportsCommercialManifestSummary() {
        var package = makeLifecycleSkillPackage(slug: "exportable")
        package.manifest.version = "2.0.0"
        package.riskLevel = SkillRiskLevel.high
        let integrity = SkillPackageIntegrity(packageID: package.id.rawValue, fileCount: 3, totalBytes: 99, fileDigests: [:])

        let exported = SkillLifecycleService().exportManifest(package: package, integrity: integrity)

        #expect(exported["slug"] == "exportable")
        #expect(exported["version"] == "2.0.0")
        #expect(exported["riskLevel"] == "high")
        #expect(exported["fileCount"] == "3")
    }
}
