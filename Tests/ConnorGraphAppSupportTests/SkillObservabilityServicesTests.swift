import Foundation
import Testing
import ConnorGraphAppSupport
import ConnorGraphCore

private func makeObservabilitySkillPackage(slug: String = "skill") -> SkillPackage {
    SkillPackage(
        id: SkillPackageID("user:/tmp/\(slug)"),
        slug: SkillSlug(slug),
        sourceTier: .user,
        manifest: SkillManifest(name: "Skill", description: "Observability skill"),
        instructions: "Do observable work.",
        packagePath: "/tmp/\(slug)",
        skillFilePath: "/tmp/\(slug)/SKILL.md"
    )
}

@Suite("Commercial Skill Observability Services Tests")
struct SkillObservabilityServicesTests {
    @Test func evaluatesInvocationCases() {
        let cases = [
            SkillEvaluationCase(id: "case-1", skillSlug: "review", prompt: "/review file", expectedInvocation: true),
            SkillEvaluationCase(id: "case-2", skillSlug: "review", prompt: "plain text", expectedInvocation: false)
        ]

        let results = SkillObservabilityService().evaluate(cases: cases)

        #expect(results.map(\.outcome) == [.pass, .pass])
    }

    @Test func buildsCommercialReadinessSnapshot() {
        var project = makeObservabilitySkillPackage(slug: "project-risk")
        project.sourceTier = SkillSourceTier.project
        project.trustState = SkillTrustState.projectRequiresTrust
        project.riskLevel = SkillRiskLevel.high
        let resolution = SkillResolution(slug: project.slug, selected: project, candidates: [project])
        let snapshot = SkillPackageScanSnapshot(packages: [project], resolutions: [resolution], warnings: ["invalid skill"])
        let readiness = ["project-risk": [SkillSourceReadiness(sourceSlug: "github", state: .missing, message: "missing")]]
        let evaluations = [SkillEvaluationResult(caseID: "eval", outcome: .fail, message: "failed")]

        let commercial = SkillObservabilityService().readiness(snapshot: snapshot, sourceReadiness: readiness, evaluations: evaluations)

        #expect(commercial.discoveredSkills == 1)
        #expect(commercial.invalidSkills == 1)
        #expect(commercial.riskySkills == 1)
        #expect(commercial.untrustedProjectSkills == 1)
        #expect(commercial.sourceBlockedSkills == 1)
        #expect(commercial.failedEvaluations == 1)
        #expect(commercial.isCommerciallyReady == false)
    }
}
