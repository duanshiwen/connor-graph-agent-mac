import Testing
import ConnorGraphAppSupport

@Suite("Skill Creation Fallback Planner Tests")
struct SkillCreationFallbackPlannerTests {
    @Test func suggestsGoExpertIdentityAndAvoidsSlugCollision() {
        let planner = SkillCreationFallbackPlanner()

        let identity = planner.suggestedIdentity(for: "创建一个 Go 语言专家，关注 go.mod 和 .go 文件", existingSlugs: ["go-expert"])

        #expect(identity.name == "Go 语言专家")
        #expect(identity.slug == "go-expert-2")
    }

    @Test func generatesFallbackMarkdownWithGoGlobs() {
        let planner = SkillCreationFallbackPlanner()

        let markdown = planner.generatedSkillMarkdown(name: "Go 语言专家", slug: "go-expert", userRequest: "帮助我做 Golang 性能优化")

        #expect(markdown.contains("name: \"Go 语言专家\""))
        #expect(markdown.contains("**/*.go"))
        #expect(markdown.contains("**/go.mod"))
        #expect(markdown.contains("Created by Connor Skill Manager as `go-expert`"))
    }
}
