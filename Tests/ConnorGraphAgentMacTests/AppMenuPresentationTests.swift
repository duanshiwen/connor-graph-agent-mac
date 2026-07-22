import Testing
@testable import ConnorGraphAgentMac

@Suite("App menu presentation")
struct AppMenuPresentationTests {
    @Test("Uses Chinese titles for app command menus")
    func usesChineseTitles() {
        #expect(AppMenuPresentation.fileMenuTitle == "文件")
        #expect(AppMenuPresentation.actionMenuTitle == "操作")
        #expect(AppMenuPresentation.newSessionTitle == "新建会话")
        #expect(AppMenuPresentation.newNoteTitle == "新建笔记")
        #expect(AppMenuPresentation.importNotesTitle == "导入笔记…")
        #expect(AppMenuPresentation.importCenterTitle == "导入中心…")
        #expect(AppMenuPresentation.importSkillsTitle == "导入技能…")
    }

    @Test("Uses stable singleton import window identifiers")
    func usesStableImportWindowIdentifiers() {
        #expect(AppMenuPresentation.noteImportWizardWindowID == "note-import-wizard")
        #expect(AppMenuPresentation.noteImportCenterWindowID == "note-import-center")
        #expect(AppMenuPresentation.noteImportWizardWindowID != AppMenuPresentation.noteImportCenterWindowID)
        #expect(AppMenuPresentation.skillImportWindowID == "skill-import")
    }
}
