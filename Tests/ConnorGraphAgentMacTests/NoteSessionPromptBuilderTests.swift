import Testing
@testable import ConnorGraphAgentMac

@Test func initialNoteInstructionDefinesSessionBackedCaptureWithoutImplicitFileWrite() {
    let suffix = NoteSessionPromptBuilder.noteInstructionSuffix

    #expect(suffix.contains("session_kind: note"))
    #expect(suffix.contains("note_phase: initial_capture"))
    #expect(suffix.contains("persistence: session_backed"))
    #expect(suffix.contains("已经由 Session OS 保存"))
    #expect(suffix.contains("自动进入 Memory OS L0/L1"))
    #expect(suffix.contains("不要为了保存这条笔记调用 `Write`、`Edit`、shell、知识库写入或 Memory 写入工具"))
    #expect(suffix.contains("明确要求创建文件、导出到路径或修改现有文件"))
    #expect(suffix.contains("# 📝 笔记已保存"))
}

@Test func noteInstructionDoesNotConvertCaptureIntoAFileArtifact() {
    let suffix = NoteSessionPromptBuilder.noteInstructionSuffix

    #expect(!suffix.contains("生成文件名"))
    #expect(!suffix.contains("创建 Markdown 文件"))
    #expect(!suffix.contains("选择保存路径"))
}
