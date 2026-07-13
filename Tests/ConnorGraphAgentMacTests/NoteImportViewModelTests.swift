import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore
import ConnorGraphAppSupport
@testable import ConnorGraphAgentMac

@MainActor @Suite("Note import UI presentation")
struct NoteImportViewModelTests {
    @Test("Filters only notes requiring encoding review")
    func encodingReview() {
        let model = NoteImportViewModel()
        model.notes = [
            .init(sourceKind: .markdownFolder, sourceIdentity: "a", title: "A", markdownContent: "A", rawByteHash: "a", normalizedTextHash: "a"),
            .init(sourceKind: .markdownFolder, sourceIdentity: "b", title: "B", markdownContent: "B", rawByteHash: "b", normalizedTextHash: "b", diagnostics: [.init(code: .decodingAmbiguous, severity: .warning, message: "Review")])
        ]
        #expect(model.encodingReview.map(\.title) == ["B"])
    }

    @Test("Wizard uses the four-stage review flow")
    func steps() {
        let model = NoteImportViewModel()
        #expect(model.step == .source)
        model.sourceURL = URL(fileURLWithPath: "/tmp/notes")
        model.advance()
        #expect(model.step == .review)
        model.advance()
        #expect(model.step == .options)
        model.back()
        #expect(model.step == .review)
    }

    @Test("Notifies the app when imported note sessions become visible")
    func notifiesImportedSessionsChanged() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("graph.sqlite").path
        let store = try SQLiteGraphKernelStore(path: path)
        try store.migrate()
        let sessions = AppChatSessionRepository(store: store)
        let ledger = try AppNoteImportRepository(databasePath: path)
        let source = NoteImportSourceRecord(id: "source", kind: .markdownFolder, displayName: "Notes")
        try ledger.saveSource(source)
        try ledger.saveJob(NoteImportJobRecord(id: "job", sourceID: source.id, status: .importing))
        var refreshCount = 0
        let model = NoteImportViewModel(ledger: ledger, onImportedSessionsChanged: { refreshCount += 1 })
        let session = try sessions.createSession(title: "Imported")
        try ledger.saveItem(NoteImportItemRecord(id: "item", jobID: "job", sourceID: source.id, sourceIdentity: "note.md", title: "Note", status: .imported, sessionID: session.id, rawByteHash: "raw", normalizedTextHash: "text"))
        _ = try ledger.refreshJobProgress(jobID: "job")

        model.reloadJobs(selecting: "job")
        model.reloadJobs(selecting: "job")
        #expect(refreshCount == 1)
    }

    @Test("Search filters note titles and paths")
    func filtersNotes() {
        let model = NoteImportViewModel()
        model.notes = [
            .init(sourceKind: .markdownFolder, sourceIdentity: "a", relativePath: "work/plan.md", title: "计划", markdownContent: "A", rawByteHash: "a", normalizedTextHash: "a"),
            .init(sourceKind: .markdownFolder, sourceIdentity: "b", relativePath: "life/log.md", title: "日志", markdownContent: "B", rawByteHash: "b", normalizedTextHash: "b")
        ]
        model.searchText = "work"
        #expect(model.filteredNotes.map(\.title) == ["计划"])
    }
}
