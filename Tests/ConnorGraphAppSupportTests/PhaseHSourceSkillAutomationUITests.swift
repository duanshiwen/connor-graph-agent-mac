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
        #expect(presentation.summary.projectScopedCount == 0)
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

    @Test func automationUIPresentationBuildsRuleTriggerAndHistoryCards() {
        let config = ProductOSAutomationConfig(rules: [
            ProductOSAutomationRule(
                id: "rule-archive",
                name: "Archive done sessions",
                isEnabled: true,
                trigger: ProductOSAutomationTrigger(kind: .sessionStatusChanged, status: .done),
                actions: [ProductOSAutomationAction(kind: .appendTimelineEvent, message: "done")],
                requiresReview: false,
                tags: ["cleanup"]
            ),
            ProductOSAutomationRule(
                id: "rule-review",
                name: "Review graph memory",
                isEnabled: false,
                trigger: ProductOSAutomationTrigger(kind: .skillRegistryChanged),
                actions: [ProductOSAutomationAction(kind: .triggerSkill, skillID: "superpowers", message: "review")],
                requiresReview: true,
                tags: ["review"]
            )
        ])
        let triggers = [ProductOSAutomationTriggerRecord(
            id: "trigger-1",
            ruleID: "rule-archive",
            ruleName: "Archive done sessions",
            trigger: .sessionStatusChanged,
            sessionID: "session-1",
            actionSummaries: ["done"],
            requiresReview: false
        )]
        let history = [ProductOSAutomationExecutionHistoryRecord(
            id: "history-1",
            sessionID: "session-1",
            trigger: .sessionStatusChanged,
            ruleIDs: ["rule-archive"],
            appliedActionCount: 1,
            skippedActionCount: 0,
            eventCount: 2,
            outcome: .completed,
            message: "Applied"
        )]

        let presentation = AutomationRuntimeUIPresentation.build(config: config, triggers: triggers, history: history)

        #expect(presentation.summary.totalRuleCount == 2)
        #expect(presentation.summary.enabledRuleCount == 1)
        #expect(presentation.summary.pendingReviewRuleCount == 1)
        #expect(presentation.ruleCards.map(\.id) == ["rule-archive", "rule-review"])
        #expect(presentation.ruleCards[0].dispositionLabel == "ready")
        #expect(presentation.ruleCards[1].severity == .warning)
        #expect(presentation.triggerCards.first?.detail == "done")
        #expect(presentation.historyCards.first?.title == "completed · sessionStatusChanged")
    }

    @Test func automationRouteIsWiredToNativePanel() {
        let route = ConnorNativeShellRouteResolver().route(for: .automation)

        #expect(route.legacySidebarID == "automation")
        #expect(route.isPlaceholder == false)
    }
}
