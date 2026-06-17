import Testing
import ConnorGraphAppSupport

@Suite("Skill Agent Prompt Builder Tests")
struct SkillAgentPromptBuilderTests {
    @Test func addPromptRegistersCreateToolAndSuggestedSlug() {
        let prompt = SkillAgentPromptBuilder().addSkillPrompt(
            userRequest: "帮我创建 Go 专家技能",
            skillRootPath: "/tmp/skills",
            existingSlugs: []
        )

        #expect(prompt.contains("connor_skill_create"))
        #expect(prompt.contains("Go 语言专家"))
        #expect(prompt.contains("/tmp/skills/go-expert/"))
    }

    @Test func editPromptRegistersUpdateToolAndSkillContext() {
        let card = SkillManagerCard(
            id: "go-expert",
            title: "Go 语言专家",
            subtitle: "Go review skill",
            path: "/tmp/skills/go-expert/SKILL.md",
            packagePath: "/tmp/skills/go-expert",
            instructions: "# Go 语言专家\n\nReview Go code.",
            sourceTier: "user",
            trustState: "userTrusted",
            riskLabel: "low",
            lifecycleLabel: "stable",
            requiredSources: [],
            permissionLabels: ["readSession"],
            overrideChain: [],
            warnings: []
        )

        let prompt = SkillAgentPromptBuilder().editSkillPrompt(card: card, userRequest: "增加性能检查")

        #expect(prompt.contains("connor_skill_update"))
        #expect(prompt.contains("slug: go-expert"))
        #expect(prompt.contains("增加性能检查"))
        #expect(prompt.contains("Review Go code."))
    }
}
