import Foundation
import Testing
import ConnorGraphAppSupport
import ConnorGraphCore

private func makeIntegrationSkillPackage(slug: String = "skill") -> SkillPackage {
    SkillPackage(
        id: SkillPackageID("user:/tmp/\(slug)"),
        slug: SkillSlug(slug),
        sourceTier: .user,
        manifest: SkillManifest(name: "Skill", description: "Integration skill"),
        instructions: "Do integration work.",
        packagePath: "/tmp/\(slug)",
        skillFilePath: "/tmp/\(slug)/SKILL.md"
    )
}

@Suite("Commercial Skill Integration Services Tests")
struct SkillIntegrationServicesTests {
    @Test func buildsAutomationTriggerPlansForSkillActions() {
        let config = ProductOSAutomationConfig(rules: [
            ProductOSAutomationRule(
                id: "rule-review",
                name: "Review sessions",
                isEnabled: true,
                trigger: ProductOSAutomationTrigger(kind: .sessionStatusChanged, status: .done),
                actions: [ProductOSAutomationAction(kind: .triggerSkill, skillID: "session-review", message: "$SESSION_ID")],
                requiresReview: true
            )
        ])

        let plans = SkillAutomationIntegrationService().triggerPlans(config: config)

        #expect(plans.count == 1)
        #expect(plans[0].ruleID == "rule-review")
        #expect(plans[0].skillSlug == "session-review")
        #expect(plans[0].arguments == "$SESSION_ID")
        #expect(plans[0].requiresReview == true)
    }

    @Test func graphMemoryContextRequestNeverAllowsDirectWrites() {
        var package = makeIntegrationSkillPackage(slug: "graph-reader")
        package.manifest.connor.graphContextPolicy = AgentPermissionMode.askToWrite

        let request = SkillGraphMemoryIntegrationService().graphContextRequest(for: package, domains: ["software-engineering"], workObjectID: "connor-agent-core")

        #expect(request.skillSlug == "graph-reader")
        #expect(request.policy == AgentPermissionMode.askToWrite)
        #expect(request.domains == ["software-engineering"])
        #expect(request.workObjectID == "connor-agent-core")
        #expect(request.canWriteDirectly == false)
    }
}
