import Testing
@testable import ConnorGraphAgentMac
import ConnorGraphAppSupport

@MainActor
@Suite("Composer Model Selection Presentation Tests")
struct ComposerModelSelectionPresentationTests {
    @Test func emptyModelFallsBackToUnselectedTitle() {
        let presentation = ComposerModelSelectionPresentation(
            selectedModel: "",
            sessionHasOverride: false
        )

        #expect(presentation.title == "未选择模型")
        #expect(presentation.accessibilityLabel == "模型：未选择模型")
        #expect(presentation.showsSessionOverrideIndicator == false)
    }

    @Test func longModelNameIsPreservedForAccessibility() {
        let model = "claude-sonnet-4-20250514-very-long-provider-specific-model-id"

        let presentation = ComposerModelSelectionPresentation(
            selectedModel: model,
            sessionHasOverride: false
        )

        #expect(presentation.title == model)
        #expect(presentation.accessibilityLabel == "模型：\(model)")
        #expect(presentation.showsSessionOverrideIndicator == false)
    }

    @Test func sessionOverrideAddsIndicatorAndAccessibilityContext() {
        let presentation = ComposerModelSelectionPresentation(
            selectedModel: "gpt-5.4-high-reasoning",
            sessionHasOverride: true
        )

        #expect(presentation.title == "gpt-5.4-high-reasoning")
        #expect(presentation.showsSessionOverrideIndicator == true)
        #expect(presentation.accessibilityLabel == "模型：gpt-5.4-high-reasoning，此会话使用自定义模型")
    }

    @Test func remoteKnowledgeSelectionDefaultsToAllAndSupportsContinuousMultiSelection() {
        let available = [
            CloudMarketplaceKnowledgeBase(id: "kb-1", name: "One", subscribed: true),
            CloudMarketplaceKnowledgeBase(id: "kb-2", name: "Two", subscribed: true),
            CloudMarketplaceKnowledgeBase(id: "kb-3", name: "Three", subscribed: true)
        ]
        let defaultSelection = RemoteKnowledgeBaseSelection(available: available, explicitIDs: nil)

        #expect(defaultSelection.selectedIDs == ["kb-1", "kb-2", "kb-3"])
        #expect(defaultSelection.isAllSelected)
        #expect(defaultSelection.toggleAllValue == [])
        #expect(defaultSelection.label == "知识库：全部")

        let partialIDs = defaultSelection.toggling("kb-2")
        let partialSelection = RemoteKnowledgeBaseSelection(available: available, explicitIDs: partialIDs)
        #expect(partialSelection.selectedIDs == ["kb-1", "kb-3"])
        #expect(partialSelection.label == "知识库：2/3")
        #expect(partialSelection.toggleAllValue == nil)

        let emptySelection = RemoteKnowledgeBaseSelection(available: available, explicitIDs: [])
        #expect(emptySelection.selectedIDs.isEmpty)
        #expect(emptySelection.label == "知识库：未选择")
    }

    @Test func mcpToolSelectionSupportsAutomaticSourceAndToolScopes() {
        let automatic = MCPToolSelection(
            availableToolNames: ["mcp__deepwiki__ask", "mcp__deepwiki__read", "mcp__github__search"],
            explicitToolNames: nil
        )
        #expect(automatic.isAutomatic)
        #expect(automatic.label == "MCP：自动")
        #expect(automatic.selectedToolNames.count == 3)

        let sourceDisabled = automatic.togglingSource(toolNames: ["mcp__deepwiki__ask", "mcp__deepwiki__read"])
        #expect(sourceDisabled == ["mcp__github__search"])

        let partial = MCPToolSelection(
            availableToolNames: automatic.availableToolNames,
            explicitToolNames: sourceDisabled
        )
        #expect(partial.label == "MCP：1/3")
        #expect(partial.toggling("mcp__deepwiki__read") == ["mcp__deepwiki__read", "mcp__github__search"])

        let disabled = MCPToolSelection(
            availableToolNames: automatic.availableToolNames,
            explicitToolNames: []
        )
        #expect(disabled.label == "MCP：关闭")
    }
}
