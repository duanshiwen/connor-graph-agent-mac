import Testing
import ConnorGraphCore
@testable import ConnorGraphAgentMac

@Test func initialNoteInstructionDefinesSessionBackedCaptureWithoutImplicitFileWrite() {
    let suffix = NoteSessionPromptBuilder.noteInstructionSuffix

    #expect(suffix.contains("session_kind: note"))
    #expect(suffix.contains("note_phase: initial_capture"))
    #expect(suffix.contains("persistence: session_backed"))
    #expect(suffix.contains("已经由 Session OS 保存"))
    #expect(suffix.contains("自动进入 Memory OS L0/L1"))
    #expect(suffix.contains("豁免本条消息的用户意图 LLM 规范化"))
    #expect(suffix.contains("后续用户消息仍按常规流程处理"))
    #expect(suffix.contains("不要声称原文已被改写、润色、摘要后保存"))
    #expect(suffix.contains("不要为了保存这条笔记调用 `Write`、`Edit`、shell、知识库写入或 Memory 写入工具"))
    #expect(suffix.contains("明确要求创建文件、导出到路径或修改现有文件"))
    #expect(suffix.contains("# 📝 笔记已保存"))
}

@Test func noteInstructionIsAppendedOnlyToInitialNoteCapture() {
    let prompt = "记录今天的想法"

    let initialNote = NoteSessionPromptBuilder.augmentedPrompt(
        prompt,
        sessionKind: .note,
        hasExistingMessages: false
    )
    let continuingNote = NoteSessionPromptBuilder.augmentedPrompt(
        prompt,
        sessionKind: .note,
        hasExistingMessages: true
    )
    let ordinaryChat = NoteSessionPromptBuilder.augmentedPrompt(
        prompt,
        sessionKind: .chat,
        hasExistingMessages: false
    )
    let emptyNote = NoteSessionPromptBuilder.augmentedPrompt(
        "",
        sessionKind: .note,
        hasExistingMessages: false
    )

    #expect(initialNote == prompt + NoteSessionPromptBuilder.noteInstructionSuffix)
    #expect(continuingNote == prompt)
    #expect(ordinaryChat == prompt)
    #expect(emptyNote.isEmpty)
}

@Test func noteInstructionDoesNotConvertCaptureIntoAFileArtifact() {
    let suffix = NoteSessionPromptBuilder.noteInstructionSuffix

    #expect(suffix.contains("不要生成文件名、创建 Markdown 文件或选择保存路径"))
    #expect(!suffix.contains("请生成文件名"))
    #expect(!suffix.contains("请创建 Markdown 文件"))
    #expect(!suffix.contains("请选择保存路径"))
}
