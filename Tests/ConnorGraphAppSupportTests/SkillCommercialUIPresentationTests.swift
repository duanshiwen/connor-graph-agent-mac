import Foundation
import Testing
import ConnorGraphAppSupport
import ConnorGraphCore

private func makeUISkillPackage(slug: String = "skill") -> SkillPackage {
    SkillPackage(
        id: SkillPackageID("user:/tmp/\(slug)"),
        slug: SkillSlug(slug),
        sourceTier: .user,
        manifest: SkillManifest(name: "Skill", description: "UI skill"),
        instructions: "Do UI work.",
        packagePath: "/tmp/\(slug)",
        skillFilePath: "/tmp/\(slug)/SKILL.md"
    )
}

@Suite("Commercial Skill Manager UI Presentation Tests")
struct SkillCommercialUIPresentationTests {
    @Test func buildsCardsWithOverrideChainRiskTrustAndSourceWarnings() throws {
        var user = makeUISkillPackage(slug: "review")
        user.sourceTier = SkillSourceTier.user
        user.manifest.name = "User Review"
        var project = makeUISkillPackage(slug: "review")
        project.sourceTier = SkillSourceTier.project
        project.manifest.name = "Project Review"
        project.trustState = SkillTrustState.projectRequiresTrust
        project.riskLevel = SkillRiskLevel.high
        project.manifest.requiredSources = ["github"]
        project.manifest.connor.requiredCapabilities = [AgentPermissionCapability.readSession, AgentPermissionCapability.runWorkspaceShellCommand]
        let resolution = SkillResolution(slug: SkillSlug("review"), selected: project, candidates: [user, project], warnings: ["override"])
        let snapshot = SkillPackageScanSnapshot(packages: [user, project], resolutions: [resolution])
        let readiness = ["review": [SkillSourceReadiness(sourceSlug: "github", state: .unauthenticated, message: "Required source is not authenticated.")]]

        let presentation = SkillCommercialUIPresentationBuilder().build(snapshot: snapshot, sourceReadiness: readiness)

        #expect(presentation.summary.total == 1)
        #expect(presentation.summary.projectScoped == 1)
        #expect(presentation.summary.risky == 1)
        #expect(presentation.summary.sourceBlocked == 1)
        let card = try #require(presentation.cards.first)
        #expect(card.title == "Project Review")
        #expect(card.sourceTier == "project")
        #expect(card.trustState == "projectRequiresTrust")
        #expect(card.riskLabel == "high")
        #expect(card.overrideChain.count == 2)
        #expect(card.permissionLabels == ["readSession", "runWorkspaceShellCommand"])
        #expect(card.warnings.contains { $0.contains("github") })
    }

    @Test func includesGlobalInvalidSkillWarnings() {
        let snapshot = SkillPackageScanSnapshot(packages: [], resolutions: [], warnings: ["Invalid skill x"])
        let presentation = SkillCommercialUIPresentationBuilder().build(snapshot: snapshot)

        #expect(presentation.summary.invalid == 1)
        #expect(presentation.globalWarnings == ["Invalid skill x"])
    }
}
