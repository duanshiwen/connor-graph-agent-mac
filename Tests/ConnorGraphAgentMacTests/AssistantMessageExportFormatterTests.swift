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
        #expect(!AgentAssistantMessageActionsPresentation(message: AgentMessage(role: .user, content: "问题")).showsActions)
        #expect(!AgentAssistantMessageActionsPresentation(message: AgentMessage(role: .assistant, content: "  \n\t ")).showsActions)
    }

    @Test("actions expose compact titles and accessibility copy")
    func actionsExposeCompactTitlesAndAccessibilityCopy() {
        let presentation = AgentAssistantMessageActionsPresentation(
            message: AgentMessage(role: .assistant, content: "回答")
        )

        #expect(presentation.copyTitle == "复制")
        #expect(presentation.exportTitle == "导出到文件")
        #expect(presentation.copyAccessibilityLabel == "复制这条助理回复")
        #expect(presentation.exportAccessibilityLabel == "导出这条助理回复到文件")
        #expect(presentation.copyHelp == "复制原始 Markdown 文本")
        #expect(presentation.exportHelp == "保存为 Markdown 文件到当前会话 exports 目录")
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
