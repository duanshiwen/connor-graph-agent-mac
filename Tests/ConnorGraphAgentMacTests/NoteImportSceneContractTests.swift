import Foundation
import Testing
@testable import ConnorGraphAgentMac

@Suite("Note import scene contracts")
struct NoteImportSceneContractTests {
    @Test("Import center uses a singleton Window scene")
    func importCenterIsSingleton() throws {
        let source = try appSource()
        #expect(source.contains("Window(\"导入中心\", id: AppMenuPresentation.noteImportCenterWindowID)"))
        #expect(!source.contains("WindowGroup(\"导入中心\", id: AppMenuPresentation.noteImportCenterWindowID)"))
    }

    @Test("Import wizard retains its independent WindowGroup behavior")
    func importWizardRemainsWindowGroup() throws {
        let source = try appSource()
        #expect(source.contains("WindowGroup(\"导入笔记\", id: AppMenuPresentation.noteImportWizardWindowID)"))
    }

    @Test("App creates one shared import model for every scene")
    func sharedImportModel() throws {
        let source = try appSource()
        #expect(source.components(separatedBy: "@StateObject private var noteImportModel").count - 1 == 1)
        #expect(source.components(separatedBy: "NoteImportCenterView(model: noteImportModel)").count - 1 == 1)
        #expect(source.contains("noteImportModel: noteImportModel"))
    }

    private func appSource() throws -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ConnorGraphAgentMac/ConnorGraphAgentMacApp.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
