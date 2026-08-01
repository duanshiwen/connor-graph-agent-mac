import Foundation
import Testing
@testable import ConnorGraphAgent

private struct AttentionFixtureTool: AgentTool {
    let name: String
    let description = "attention fixture"
    let permission: AgentPermissionCapability
    let inputSchema = AgentToolInputSchema.object(properties: [:], required: [])

    func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: "{\"source\":\"\(name)\",\"items\":[]}",
            contentJSON: "{\"source\":\"\(name)\",\"items\":[]}"
        )
    }
}

@Test func finalAttentionAttemptsCalendarMailAndRSSReadsInOneRuntimeStage() async {
    var registry = AgentToolRegistry()
    registry.register(AttentionFixtureTool(name: "attention_brief", permission: .readCalendar))
    registry.register(AttentionFixtureTool(name: "rss_search_items", permission: .readRSS))
    let request = AgentChatRequest(runID: "run", sessionID: "session", userMessage: "finish")

    let pack = await AssistantAttentionCoordinator().run(
        request: request,
        registry: registry,
        policy: AgentPolicyEngine(permissionMode: .readOnly),
        now: Date(timeIntervalSince1970: 1_700_000_000)
    )

    #expect(pack.sections.map(\.source) == ["attention_brief", "rss_search_items"])
    #expect(pack.sections.allSatisfy { $0.error == nil })
    #expect(pack.hasAvailableSources)
}

@Test func unavailableAttentionCapabilitiesRemainExplicit() async {
    let request = AgentChatRequest(runID: "run", sessionID: "session", userMessage: "finish")
    let pack = await AssistantAttentionCoordinator().run(
        request: request,
        registry: AgentToolRegistry(),
        policy: AgentPolicyEngine(permissionMode: .readOnly)
    )

    #expect(pack.sections.count == 2)
    #expect(pack.sections.allSatisfy { $0.error == "capability unavailable" })
    #expect(!pack.hasAvailableSources)
}
