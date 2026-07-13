import Foundation
import Testing

@Suite("Note import control style contracts")
struct NoteImportControlStyleContractTests {
    @Test("Import progress uses the macOS control accent color")
    func systemAccentColor() throws {
        let presentation = try source("NoteImportPresentation.swift")
        let center = try source("NoteImportCenterView.swift")
        let toolbar = try source("NoteImportToolbarProgressButton.swift")

        #expect(presentation.contains("Color(nsColor: .controlAccentColor)"))
        #expect(center.contains(".tint(NoteImportProgressAppearance.accentColor)"))
        #expect(toolbar.contains("NoteImportProgressAppearance.accentColor"))
        #expect(!toolbar.contains("case .paused: .blue"))
        #expect(!toolbar.contains("case .cancelling: .orange"))
    }

    @Test("Import center renders one state-driven pause or resume control")
    func stateDrivenControl() throws {
        let center = try source("NoteImportCenterView.swift")
        #expect(center.contains("if let presentation = NoteImportControlPresentation(job: job)"))
        #expect(center.contains("switch presentation.action"))
        #expect(!center.contains("if job.pauseRequestedAt == nil"))
        #expect(!center.contains("if job.pauseRequestedAt != nil || job.status == .paused"))
    }

    private func source(_ filename: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent("Sources/ConnorGraphAgentMac/\(filename)"),
            encoding: .utf8
        )
    }
}
