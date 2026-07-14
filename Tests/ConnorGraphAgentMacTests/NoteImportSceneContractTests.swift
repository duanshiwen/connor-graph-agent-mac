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

    @Test("Import wizard uses a singleton Window scene")
    func importWizardIsSingleton() throws {
        let source = try appSource()
        #expect(source.contains("Window(\"导入笔记\", id: AppMenuPresentation.noteImportWizardWindowID)"))
        #expect(!source.contains("WindowGroup(\"导入笔记\", id: AppMenuPresentation.noteImportWizardWindowID)"))
        #expect(AppMenuPresentation.noteImportWizardWindowID != AppMenuPresentation.noteImportCenterWindowID)
    }

    @Test("App creates one shared import model for every scene")
    func sharedImportModel() throws {
        let appSource = try appSource()
        let compositionSource = try compositionRootSource()
        #expect(appSource.components(separatedBy: "@StateObject private var root: AppCompositionRoot").count - 1 == 1)
        #expect(compositionSource.components(separatedBy: "viewModel.makeNoteImportViewModel()").count - 1 == 1)
        #expect(appSource.components(separatedBy: "root.noteImportModel").count - 1 == 3)
        #expect(appSource.contains("NoteImportCenterView(model: root.noteImportModel)"))
        #expect(appSource.contains("noteImportModel: root.noteImportModel"))
    }

    private func appSource() throws -> String {
        try projectSource(named: "ConnorGraphAgentMacApp.swift")
    }

    private func compositionRootSource() throws -> String {
        try projectSource(named: "AppCompositionRoot.swift")
    }

    private func projectSource(named filename: String) throws -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ConnorGraphAgentMac/\(filename)")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
