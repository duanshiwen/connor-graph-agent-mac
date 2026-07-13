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

    @Test("Cancelling an import stops undispatched work immediately")
    func cancellationStopsScheduler() throws {
        let coordinator = try appSupportSource("NoteImportCoordinator.swift")
        #expect(coordinator.contains("activeSchedulers[jobID] = scheduler"))
        #expect(coordinator.contains("await activeSchedulers[jobID]?.cancel()"))
        #expect(coordinator.contains("defer { activeSchedulers.removeValue(forKey: jobID) }"))
    }

    @Test("Import center list omits relative update times")
    func listOmitsRelativeTime() throws {
        let center = try source("NoteImportCenterView.swift")
        #expect(!center.contains("job.updatedAt, style: .relative"))
    }

    @Test("Import center owns transient list selection without publishing during view updates")
    func localListSelection() throws {
        let center = try source("NoteImportCenterView.swift")
        #expect(center.contains("@State private var selectedJobID"))
        #expect(center.contains("List(selection: $selectedJobID)"))
        #expect(center.contains(".task(id: selectedJobID)"))
        #expect(!center.contains("set: { newValue in model.selectJob(newValue) }"))
        #expect(!center.contains(".onChange(of: model.selectedJobID) { _, _ in model.reloadSelectedJobItems() }"))
    }

    @Test("Import center renders one state-driven pause or resume control")
    func stateDrivenControl() throws {
        let center = try source("NoteImportCenterView.swift")
        #expect(center.contains("if let presentation = NoteImportControlPresentation("))
        #expect(center.contains("runtimeState: model.runtimeSnapshot.state(for: job.id)"))
        #expect(center.contains("switch presentation.action"))
        #expect(!center.contains("if job.pauseRequestedAt == nil"))
        #expect(!center.contains("if job.pauseRequestedAt != nil || job.status == .paused"))
    }

    private func source(_ filename: String) throws -> String {
        try source(filename, target: "ConnorGraphAgentMac")
    }

    private func appSupportSource(_ filename: String) throws -> String {
        try source(filename, target: "ConnorGraphAppSupport")
    }

    private func source(_ filename: String, target: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent("Sources/\(target)/\(filename)"),
            encoding: .utf8
        )
    }
}
