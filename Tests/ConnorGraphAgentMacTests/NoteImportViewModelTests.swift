import Foundation
import Testing
import ConnorGraphCore
@testable import ConnorGraphAgentMac

@MainActor @Suite("Note import UI presentation")
struct NoteImportViewModelTests {
    @Test("Filters only notes requiring encoding review")
    func encodingReview() { let model = NoteImportViewModel(); model.notes = [.init(sourceKind: .markdownFolder, sourceIdentity: "a", title: "A", markdownContent: "A", rawByteHash: "a", normalizedTextHash: "a"), .init(sourceKind: .markdownFolder, sourceIdentity: "b", title: "B", markdownContent: "B", rawByteHash: "b", normalizedTextHash: "b", diagnostics: [.init(code: .decodingAmbiguous, severity: .warning, message: "Review")])]; #expect(model.encodingReview.map(\.title) == ["B"]) }
    @Test("Wizard advances deterministically")
    func steps() { let model = NoteImportViewModel(); #expect(model.step == .source); #expect(!model.canAdvance); model.sourceURL = URL(fileURLWithPath: "/tmp/notes"); #expect(model.canAdvance); model.advance(); #expect(model.step == .preview); model.back(); #expect(model.step == .source) }
}
