import Foundation
import Testing
import ConnorGraphAppSupport
import ConnorGraphCore

private func makeRuntimeSkillPackage(slug: String = "superpowers") -> SkillPackage {
    SkillPackage(
        id: SkillPackageID("user:/tmp/\(slug)"),
        slug: SkillSlug(slug),
        sourceTier: .user,
        manifest: SkillManifest(
            name: "Superpowers",
            description: "Disciplined engineering workflow",
            arguments: ["topic"],
            requiredSources: ["kb-source"],
            connor: ConnorSkillExtension(requiredCapabilities: [.readSession, .modelCall], graphContextPolicy: .readOnly, riskLevel: .medium)
        ),
        instructions: "Research $topic with discipline.",
        packagePath: "/tmp/\(slug)",
        skillFilePath: "/tmp/\(slug)/SKILL.md",
        trustState: .userTrusted,
        riskLevel: .medium
    )
}

@Suite("Commercial Skill Invocation Runtime Tests")
struct SkillInvocationRuntimeTests {
    @Test func buildsInvocationPlanWithRenderedInstructionsAndPermissions() throws {
        let package = makeRuntimeSkillPackage()
        let resolution = SkillResolution(slug: package.slug, selected: package, candidates: [package])
        let request = SkillInvocationRequest(slug: package.slug, rawInvocation: "/superpowers", arguments: "skill-system", sessionID: "session-1", runID: "run-1")

        let plan = try SkillInvocationRuntime().buildPlan(request: request, resolution: resolution)

        #expect(plan.renderedInstructions.contains("<connor-skill-invocation"))
        #expect(plan.renderedInstructions.contains("Research skill-system with discipline."))
        #expect(plan.requiredSources == ["kb-source"])
        #expect(plan.permissionRequests.map(\.capability) == [.readSession, .modelCall])
        #expect(plan.permissionRequests.allSatisfy { $0.toolName == "skill:superpowers" })
    }

    @Test func rejectsUserInvocationWhenSkillIsNotUserInvocable() throws {
        var package = makeRuntimeSkillPackage()
        package.manifest.userInvocable = false
        let resolution = SkillResolution(slug: package.slug, selected: package, candidates: [package])
        let request = SkillInvocationRequest(slug: package.slug, rawInvocation: "/superpowers", sessionID: "session-1")

        do {
            _ = try SkillInvocationRuntime().buildPlan(request: request, resolution: resolution)
            Issue.record("Expected user invocation to be rejected")
        } catch let error as SkillInvocationRuntimeError {
            #expect(error == .userInvocationDisabled("superpowers"))
        }
    }

    @Test func writesSkillInvocationAuditToSessionCapsule() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ConnorSkillRuntimeTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storagePaths = AppStoragePaths(applicationSupportDirectory: root)
        let package = makeRuntimeSkillPackage()
        let resolution = SkillResolution(slug: package.slug, selected: package, candidates: [package])
        let request = SkillInvocationRequest(slug: package.slug, rawInvocation: "/superpowers", arguments: "skills", sessionID: "session-1", runID: "run-1")
        let plan = try SkillInvocationRuntime().buildPlan(request: request, resolution: resolution)

        try SkillInvocationAuditWriter(storagePaths: storagePaths).append(plan: plan, outcome: .planned)

        let invocationURL = storagePaths.sessionArtifactDirectories(sessionID: "session-1").state.appendingPathComponent("skill-invocations.jsonl")
        let auditURL = storagePaths.sessionArtifactDirectories(sessionID: "session-1").logs.appendingPathComponent("skill-audit.jsonl")
        #expect(FileManager.default.fileExists(atPath: invocationURL.path))
        #expect(FileManager.default.fileExists(atPath: auditURL.path))
        let content = try String(contentsOf: invocationURL, encoding: .utf8)
        #expect(content.contains("superpowers"))
        #expect(content.contains("planned"))
    }
}
