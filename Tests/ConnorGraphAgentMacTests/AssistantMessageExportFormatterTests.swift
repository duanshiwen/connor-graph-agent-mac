import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport
@testable import ConnorGraphAgentMac

@Suite("Assistant message export formatter tests")
struct AssistantMessageExportFormatterTests {
    @Test("filename includes turn timestamp id prefix and markdown extension")
    func filenameIncludesTurnTimestampIDPrefixAndMarkdownExtension() {
        let message = presentation(
            id: "message-export-123456",
            role: .assistant,
            content: "## 回答\n\n正文",
            turnNumber: 3
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let date = calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 8,
            hour: 1,
            minute: 32,
            second: 45
        ))!

        let filename = AssistantMessageExportFormatter.filename(for: message, date: date, calendar: calendar)

        #expect(filename == "assistant-reply-turn-003-20260708-013245-message-.md")
    }

    @Test("filename sanitizes unsafe message id characters")
    func filenameSanitizesUnsafeMessageIDCharacters() {
        let message = presentation(
            id: "id/with:?bad",
            role: .assistant,
            content: "content",
            turnNumber: 12
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = Date(timeIntervalSince1970: 0)

        let filename = AssistantMessageExportFormatter.filename(for: message, date: date, calendar: calendar)

        #expect(filename == "assistant-reply-turn-012-19700101-000000-id-with-.md")
        #expect(!filename.contains("/"))
        #expect(!filename.contains(":"))
        #expect(!filename.contains("?"))
    }

    @Test("actions are shown only for non-empty assistant messages")
    func actionsAreShownOnlyForNonEmptyAssistantMessages() {
        #expect(AgentAssistantMessageActionsPresentation(message: AgentMessage(role: .assistant, content: "回答")).showsActions)
        #expect(!AgentAssistantMessageActionsPresentation(message: AgentMessage(role: .assistant, content: "处理中"), isEnabled: false).showsActions)
        #expect(!AgentAssistantMessageActionsPresentation(message: AgentMessage(role: .user, content: "问题")).showsActions)
        #expect(!AgentAssistantMessageActionsPresentation(message: AgentMessage(role: .assistant, content: "  \n\t ")).showsActions)
    }

    @Test("activity header chevron appears only on hover or while expanded")
    func activityHeaderChevronAppearsOnlyOnHoverOrWhileExpanded() {
        let idle = AgentActivityHeaderDisclosurePresentation(isExpanded: false, isHovering: false)
        let hovered = AgentActivityHeaderDisclosurePresentation(isExpanded: false, isHovering: true)
        let expanded = AgentActivityHeaderDisclosurePresentation(isExpanded: true, isHovering: false)

        #expect(!idle.showsChevron)
        #expect(idle.systemImage == "chevron.right")
        #expect(hovered.showsChevron)
        #expect(hovered.systemImage == "chevron.right")
        #expect(expanded.showsChevron)
        #expect(expanded.systemImage == "chevron.down")
    }

    @Test("activity header omits turn and operation counts")
    func activityHeaderOmitsTurnAndOperationCounts() {
        let presentation = AgentActivityHeaderTextPresentation(
            statusText: "已完成",
            toolNames: ["查找文件", "执行终端命令", "搜索知识图谱", "读取日历"]
        )

        #expect(presentation.text == "已完成 · 查找文件、执行终端命令、搜索知识图谱等")
        #expect(!presentation.text.contains("第"))
        #expect(!presentation.text.contains("轮"))
        #expect(!presentation.text.contains("4"))
        #expect(!presentation.text.contains("项操作"))
    }

    @Test("activity header omits routine preflight tools")
    func activityHeaderOmitsRoutinePreflightTools() {
        let mixed = AgentActivityHeaderTextPresentation(
            statusText: "已完成",
            toolNames: ["获取当前时间", "查询近期记忆", "查询长期记忆", "读取用户偏好", "搜索笔记", "搜索日程"]
        )
        let routineOnly = AgentActivityHeaderTextPresentation(
            statusText: "正在处理",
            toolNames: ["获取当前时间", "搜索短期记忆", "搜索长期记忆", "获取用户偏好"]
        )

        #expect(mixed.text == "已完成 · 搜索日程")
        #expect(routineOnly.text == "正在处理")
    }

    @Test("activity header gives active compaction exclusive status text")
    func activityHeaderShowsCompactionWithoutToolSuffix() {
        let presentation = AgentActivityHeaderTextPresentation(
            statusText: "正在压缩上下文",
            toolNames: ["读取文件", "执行终端命令"]
        )

        #expect(presentation.text == "正在压缩上下文")
    }

    @Test("actions expose compact titles and accessibility copy")
    func actionsExposeCompactTitlesAndAccessibilityCopy() {
        let presentation = AgentAssistantMessageActionsPresentation(
            message: AgentMessage(role: .assistant, content: "回答")
        )

        #expect(presentation.copyTitle == "复制")
        #expect(presentation.exportTitle == "导出到文件")
        #expect(presentation.copyAccessibilityLabel == "复制这条助理回复")
        #expect(presentation.exportAccessibilityLabel == "导出这条助理回复为 Markdown 文件")
        #expect(presentation.copyHelp == "复制原始 Markdown 文本")
        #expect(presentation.exportHelp == "选择保存位置和文件名，导出为 Markdown 文件")
    }

    @Test("long assistant replies expose reversible expansion controls")
    func longAssistantRepliesExposeReversibleExpansionControls() {
        let content = String(
            repeating: "a",
            count: AgentMarkdownPreviewRenderStrategy.deferredPreviewCharacterThreshold
        )
        let message = AgentMessage(role: .assistant, content: content)

        let collapsed = AgentAssistantMessageExpansionPresentation(message: message, isExpanded: false)
        let expanded = AgentAssistantMessageExpansionPresentation(message: message, isExpanded: true)

        #expect(collapsed.isAvailable)
        #expect(collapsed.title == "展开")
        #expect(collapsed.systemImage == "chevron.down")
        #expect(collapsed.accessibilityLabel == "展开这条助理回复")
        #expect(expanded.isAvailable)
        #expect(expanded.title == "收起")
        #expect(expanded.systemImage == "chevron.up")
        #expect(expanded.accessibilityLabel == "收起这条助理回复")
    }

    @Test("long user messages also expose expansion controls")
    func longUserMessagesAlsoExposeExpansionControls() {
        let threshold = AgentMarkdownPreviewRenderStrategy.deferredPreviewCharacterThreshold
        let shortReply = AgentMessage(role: .assistant, content: String(repeating: "a", count: threshold - 1))
        let longUserMessage = AgentMessage(role: .user, content: String(repeating: "a", count: threshold))
        let longSystemMessage = AgentMessage(role: .system, content: String(repeating: "a", count: threshold))

        let userPresentation = AgentAssistantMessageExpansionPresentation(
            message: longUserMessage,
            isExpanded: false
        )

        #expect(!AgentAssistantMessageExpansionPresentation(message: shortReply, isExpanded: false).isAvailable)
        #expect(userPresentation.isAvailable)
        #expect(userPresentation.title == "展开")
        #expect(userPresentation.accessibilityLabel == "展开这条用户消息")
        #expect(!AgentAssistantMessageExpansionPresentation(message: longSystemMessage, isExpanded: false).isAvailable)
    }

    @Test("copy and export payload preserves the complete long reply")
    func fullContentPayloadPreservesTheCompleteLongReply() {
        let body = String(
            repeating: "正文段落\n",
            count: AgentMarkdownPreviewRenderStrategy.deferredPreviewCharacterThreshold
        )
        let content = "# 开头\n\n\(body)\n完整结尾"
        let message = presentation(
            id: "long-reply",
            role: .assistant,
            content: content,
            turnNumber: 1
        )

        let payload = AssistantMessageFullContentProvider.markdown(for: message)

        #expect(payload == content)
        #expect(payload.count == content.count)
        #expect(payload.hasPrefix("# 开头"))
        #expect(payload.hasSuffix("完整结尾"))
    }

    @Test("only the first message in a note session uses note body presentation")
    func noteBodyPresentationIsLimitedToFirstNoteMessage() {
        #expect(AgentChatMessagePresentationPolicy.isNoteBody(sessionKind: .note, firstMessageID: "first", messageID: "first"))
        #expect(!AgentChatMessagePresentationPolicy.isNoteBody(sessionKind: .note, firstMessageID: "first", messageID: "second"))
        #expect(!AgentChatMessagePresentationPolicy.isNoteBody(sessionKind: .chat, firstMessageID: "first", messageID: "first"))
    }

    private func presentation(
        id: String,
        role: AgentRole,
        content: String,
        turnNumber: Int
    ) -> AgentChatMessagePresentation {
        AgentChatMessagePresentation(
            message: AgentMessage(id: id, role: role, content: content),
            turnNumber: turnNumber,
            isLatestAssistantMessage: false,
            lastContext: nil
        )
    }
}
