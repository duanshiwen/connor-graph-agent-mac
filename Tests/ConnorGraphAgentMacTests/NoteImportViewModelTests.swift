import Foundation
import Testing
import ConnorGraphCore
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
