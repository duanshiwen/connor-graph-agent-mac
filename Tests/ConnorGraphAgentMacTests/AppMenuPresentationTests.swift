import Foundation
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
        #expect(AppMenuPresentation.importCenterTitle == "笔记导入中心…")
        #expect(AppMenuPresentation.importSkillsTitle == "导入技能…")
    }

    @Test("Uses stable singleton import window identifiers")
    func usesStableImportWindowIdentifiers() {
        #expect(AppMenuPresentation.noteImportWizardWindowID == "note-import-wizard")
        #expect(AppMenuPresentation.noteImportCenterWindowID == "note-import-center")
        #expect(AppMenuPresentation.noteImportWizardWindowID != AppMenuPresentation.noteImportCenterWindowID)
        #expect(AppMenuPresentation.skillImportWindowID == "skill-import")
    }

    @Test("Places note import center directly below note import")
    func noteImportMenuOrder() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ConnorGraphAgentMac/ConnorGraphAgentMacApp.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let notes = try #require(source.range(of: "Button(AppMenuPresentation.importNotesTitle)"))
        let center = try #require(source.range(of: "Button(AppMenuPresentation.importCenterTitle)"))
        let skills = try #require(source.range(of: "Button(AppMenuPresentation.importSkillsTitle)"))

        #expect(notes.lowerBound < center.lowerBound)
        #expect(center.lowerBound < skills.lowerBound)
    }
}
