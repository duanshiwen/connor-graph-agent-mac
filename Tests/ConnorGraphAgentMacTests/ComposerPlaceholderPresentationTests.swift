import Testing
@testable import ConnorGraphAgentMac

@Suite("Composer placeholder presentation")
struct ComposerPlaceholderPresentationTests {
    @Test func fileWorkPromptsForWorkingDirectoryWhenNoneIsSelected() {
        let placeholder = ComposerPlaceholderPresentation.text(
            isNoteMode: false,
            hasWorkingDirectory: false,
            sendHint: "Shift + Return 换行"
        )

        #expect(placeholder.contains("输入 / 调用技能"))
        #expect(placeholder.contains("输入 @ 提及人物"))
        #expect(placeholder.contains("如需创建、更新或删除文件，请先选择一个工作目录"))
        #expect(placeholder.contains("Shift + Return 换行"))
    }

    @Test func regularPlaceholderRemainsWhenWorkspaceIsSelected() {
        let placeholder = ComposerPlaceholderPresentation.text(
            isNoteMode: false,
            hasWorkingDirectory: true,
            sendHint: "⌘ + Return 发送"
        )

        #expect(placeholder == "输入 / 调用技能，输入 @ 提及人物；⌘ + Return 发送")
    }

    @Test func noteModeKeepsItsDedicatedPlaceholder() {
        let placeholder = ComposerPlaceholderPresentation.text(
            isNoteMode: true,
            hasWorkingDirectory: false,
            sendHint: "Shift + Return 换行"
        )

        #expect(placeholder == "写下你的笔记...")
    }
}
