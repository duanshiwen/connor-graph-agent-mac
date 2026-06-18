import Foundation
import Testing
import ConnorGraphAppSupport
import ConnorGraphCore

@Suite("Commercial Skill Invocation Parser Tests")
struct SkillInvocationParserTests {
    @Test func parsesSlashInvocationWithArguments() {
        let parser = SkillInvocationParser()
        let invocations = parser.parse("/review-pr 123 --deep", availableSlugs: ["review-pr"])

        #expect(invocations.count == 1)
        #expect(invocations[0].slug.rawValue == "review-pr")
        #expect(invocations[0].rawInvocation == "/review-pr")
        #expect(invocations[0].arguments == "123 --deep")
    }

    @Test func parsesBracketMentionWithWorkspacePrefix() {
        let parser = SkillInvocationParser()
        let invocations = parser.parse("use [skill:shiwens-knowledge-base:superpowers] please", availableSlugs: ["superpowers"])

        #expect(invocations.count == 1)
        #expect(invocations[0].slug.rawValue == "superpowers")
        #expect(invocations[0].rawInvocation == "[skill:shiwens-knowledge-base:superpowers]")
    }

    @Test func preservesMentionAsSemanticText() {
        let parser = SkillInvocationParser()
        let text = parser.semanticText("find root cause in [skill:datadog-api]", skillNames: ["datadog-api": "Datadog API"])

        #expect(text == "find root cause in [Mentioned skill: Datadog API (slug: datadog-api)]")
    }

    @Test func substitutesPositionalAndNamedArguments() {
        let parser = SkillInvocationParser()
        let invocation = ParsedSkillInvocation(slug: SkillSlug("fix-issue"), rawInvocation: "/fix-issue", arguments: "123 \"login bug\"")
        let rendered = parser.substituteArguments(in: "Fix $issue named $title. First=$0 All=$ARGUMENTS", invocation: invocation, declaredArguments: ["issue", "title"])

        #expect(rendered == "Fix 123 named login bug. First=123 All=123 \"login bug\"")
    }

    @Test func appendsArgumentsWhenNoPlaceholderExists() {
        let parser = SkillInvocationParser()
        let invocation = ParsedSkillInvocation(slug: SkillSlug("research"), rawInvocation: "/research", arguments: "skill systems")
        let rendered = parser.substituteArguments(in: "Research carefully.", invocation: invocation)

        #expect(rendered.contains("ARGUMENTS: skill systems"))
    }
}
