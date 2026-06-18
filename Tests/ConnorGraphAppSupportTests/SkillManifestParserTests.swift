import Foundation
import Testing
import ConnorGraphAppSupport
import ConnorGraphCore

@Suite("Commercial Skill Manifest Parser Tests")
struct SkillManifestParserTests {
    @Test func parsesCraftCompatibleSkillManifest() throws {
        let markdown = """
        ---
        name: "Code Review"
        description: "Review code with team standards"
        globs: ["*.swift", "*.md"]
        alwaysAllow: ["Bash", "Read"]
        requiredSources:
          - github
          - linear
        icon: "⚡"
        ---
        # Code Review

        Review carefully.
        """

        let parsed = try SkillManifestParser().parse(markdown: markdown, slug: "code-review")

        #expect(parsed.manifest.name == "Code Review")
        #expect(parsed.manifest.description == "Review code with team standards")
        #expect(parsed.manifest.globs == ["*.swift", "*.md"])
        #expect(parsed.manifest.alwaysAllow == ["Bash", "Read"])
        #expect(parsed.manifest.requiredSources == ["github", "linear"])
        #expect(parsed.manifest.icon == "⚡")
        #expect(parsed.manifest.connor.requiredCapabilities.contains(.runWorkspaceShellCommand))
        #expect(parsed.instructions.contains("Review carefully"))
    }

    @Test func parsesClaudeCompatibleInvocationFields() throws {
        let markdown = """
        ---
        name: Research
        description: Research a topic deeply
        when_to_use: Use when a topic needs evidence.
        argument-hint: "[topic]"
        arguments: [topic]
        disable-model-invocation: true
        user-invocable: true
        allowed-tools: "WebFetch"
        disallowed-tools:
          - Write
        model: inherit
        effort: high
        context: fork
        agent: Explore
        shell: bash
        paths:
          - Sources/**
        ---
        # Research

        Research $topic.
        """

        let parsed = try SkillManifestParser().parse(markdown: markdown, slug: "research")

        #expect(parsed.manifest.whenToUse == "Use when a topic needs evidence.")
        #expect(parsed.manifest.argumentHint == "[topic]")
        #expect(parsed.manifest.arguments == ["topic"])
        #expect(parsed.manifest.disableModelInvocation == true)
        #expect(parsed.manifest.userInvocable == true)
        #expect(parsed.manifest.allowedTools == ["WebFetch"])
        #expect(parsed.manifest.disallowedTools == ["Write"])
        #expect(parsed.manifest.model == "inherit")
        #expect(parsed.manifest.effort == "high")
        #expect(parsed.manifest.context == .fork)
        #expect(parsed.manifest.agent == "Explore")
        #expect(parsed.manifest.shell == "bash")
        #expect(parsed.manifest.paths == ["Sources/**"])
    }

    @Test func parsesConnorExtensionAndRejectsAllowAll() throws {
        let safeMarkdown = """
        ---
        name: Graph Review
        description: Review graph candidates
        x-connor:
          requiredCapabilities: [readSession, proposeGraphWrite]
          graphContextPolicy: askToWrite
          sourcePolicy: requireReady
          auditLevel: strict
          riskLevel: high
          lifecycle: beta
          commercialTier: bundled
        ---
        # Graph Review

        Review candidates.
        """
        let parsed = try SkillManifestParser().parse(markdown: safeMarkdown, slug: "graph-review")
        #expect(parsed.manifest.connor.requiredCapabilities == [.readSession, .proposeGraphWrite])
        #expect(parsed.manifest.connor.graphContextPolicy == .askToWrite)
        #expect(parsed.manifest.connor.sourcePolicy == .requireReady)
        #expect(parsed.manifest.connor.auditLevel == .strict)
        #expect(parsed.manifest.connor.riskLevel == .high)
        #expect(parsed.manifest.connor.lifecycle == .beta)
        #expect(parsed.manifest.connor.commercialTier == "bundled")

        let unsafeMarkdown = safeMarkdown.replacingOccurrences(of: "graphContextPolicy: askToWrite", with: "graphContextPolicy: allowAll")
        do {
            _ = try SkillManifestParser().parse(markdown: unsafeMarkdown, slug: "graph-review")
            Issue.record("Expected allowAll graph policy to be rejected")
        } catch let error as SkillManifestParserError {
            #expect(error == .unsafeGraphPolicy("graph-review"))
        }
    }

    @Test func preservesUnsupportedFieldsAsWarnings() throws {
        let markdown = """
        ---
        name: Future Skill
        description: Has future fields
        future-field: value
        ---
        # Future

        Do future work.
        """

        let parsed = try SkillManifestParser().parse(markdown: markdown, slug: "future-skill")

        #expect(parsed.manifest.unsupportedFields == ["future-field"])
        #expect(parsed.manifest.warnings.first?.contains("future-field") == true)
    }
}
