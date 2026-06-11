import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Phase H Source Skill Automation UI Integration Tests")
struct PhaseHSourceSkillAutomationUITests {
    @Test func sourceRuntimeUIPresentationBuildsSourceCardsAndSummary() {
        let sources = [
            MCPSourceRuntimeConfiguration(
                sourceID: "linear",
                displayName: "Linear",
                transport: .stdio(command: "npx", arguments: ["-y", "linear-mcp"]),
                status: .enabled,
                credentialRequirement: .apiKeyHeader,
                allowedCapabilities: [.readSession, .externalNetwork],
                toolNamePrefix: "linear",
                graphIngestionEnabled: true,
                graphWritePolicy: .askToWrite,
                tags: ["issues"]
            ),
            MCPSourceRuntimeConfiguration(
                sourceID: "draft-source",
                displayName: "Draft Source",
                transport: .http(url: URL(string: "https://example.com/mcp")!),
                status: .draft,
                credentialRequirement: .none,
                allowedCapabilities: [.readSession],
                graphIngestionEnabled: false,
                graphWritePolicy: .readOnly
            )
        ]

        let presentation = SourceRuntimeUIPresentation.build(sources: sources)

        #expect(presentation.summary.totalCount == 2)
        #expect(presentation.summary.enabledCount == 1)
        #expect(presentation.summary.needsCredentialCount == 1)
        #expect(presentation.cards.map(\.id) == ["draft-source", "linear"])
        #expect(presentation.cards[0].statusLabel == "draft")
        #expect(presentation.cards[0].severity == .warning)
        #expect(presentation.cards[0].transportLabel == "http · https://example.com/mcp")
        #expect(presentation.cards[1].statusLabel == "enabled")
        #expect(presentation.cards[1].capabilityLabels == ["readSession", "externalNetwork"])
        #expect(presentation.cards[1].graphPolicyLabel == "ingest on · askToWrite")
    }

    @Test func sourceRouteIsWiredToNativePanel() {
        let route = ConnorNativeShellRouteResolver().route(for: .sources)

        #expect(route.legacySidebarID == "sources")
        #expect(route.isPlaceholder == false)
        #expect(route.placeholderTitle == nil)
    }

    @Test func skillRuntimeUIPresentationBuildsSkillCardsAndSummary() {
        let definitions = [
            SkillRuntimeDefinition(
                slug: "superpowers",
                scope: .project,
                manifest: SkillRuntimeManifest(
                    name: "Superpowers",
                    description: "Disciplined TDD workflow",
                    triggers: [.manual, .beforeModelRequest],
                    requiredCapabilities: [.readSession, .modelCall],
                    requiredSources: ["kb-source"],
                    globs: ["*.swift"],
                    graphContextPolicy: .readOnly,
                    tags: ["methodology"],
                    icon: "bolt"
                ),
                instructions: "Use RED GREEN REFACTOR.",
                skillURL: URL(fileURLWithPath: "/tmp/project/.agents/skills/superpowers/SKILL.md")
            ),
            SkillRuntimeDefinition(
                slug: "writer",
                scope: .home,
                manifest: SkillRuntimeManifest(
                    name: "Writer",
                    description: "Writing assistant",
                    triggers: [.manual],
                    requiredCapabilities: [.readSession],
                    graphContextPolicy: .askToWrite,
                    tags: ["writing"]
                ),
                instructions: "Write clearly.",
                skillURL: URL(fileURLWithPath: "/tmp/home/writer/SKILL.md")
            )
        ]

        let presentation = SkillRuntimeUIPresentation.build(skills: definitions)

        #expect(presentation.summary.totalCount == 2)
        #expect(presentation.summary.projectScopedCount == 1)
        #expect(presentation.summary.requiresSourceCount == 1)
        #expect(presentation.cards.map(\.id) == ["superpowers", "writer"])
        #expect(presentation.cards[0].scopeLabel == "project")
        #expect(presentation.cards[0].triggerLabels == ["manual", "beforeModelRequest"])
        #expect(presentation.cards[0].requiredSourceLabels == ["kb-source"])
        #expect(presentation.cards[0].graphPolicyLabel == "readOnly")
        #expect(presentation.cards[1].severity == .warning)
    }

    @Test func skillRouteIsWiredToNativePanel() {
        let route = ConnorNativeShellRouteResolver().route(for: .skills)

        #expect(route.legacySidebarID == "skills")
        #expect(route.isPlaceholder == false)
        #expect(route.placeholderTitle == nil)
    }
}
