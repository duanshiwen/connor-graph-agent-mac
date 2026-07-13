import Foundation
import Testing
import ConnorGraphCore
@testable import ConnorGraphAppSupport

@Suite("Note import payload staging")
struct NoteImportPayloadStoreTests {
    @Test("Stores and loads a note without inline base64 metadata")
    func roundTripsPayload() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NoteImportPayloadStore(rootDirectory: root)
        let note = ImportedNote(
            sourceKind: .markdownFolder,
            sourceIdentity: "note.md",
            title: "Note",
            markdownContent: "# Large content",
            rawByteHash: "raw",
            normalizedTextHash: "normalized"
        )

        let metadata = try store.save(note, jobID: "job", itemID: "item")
        let loaded = try store.load(metadata: metadata)

        #expect(metadata[NoteImportPayloadStore.referenceMetadataKey] == "job/item.json")
        #expect(metadata["imported_note_payload"] == nil)
        #expect(loaded == note)
    }

    @Test("Rejects references that escape the staging root")
    func rejectsTraversal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = NoteImportPayloadStore(rootDirectory: root)
        #expect(throws: NoteImportPayloadStoreError.invalidReference("../secret")) {
            _ = try store.load(metadata: [NoteImportPayloadStore.referenceMetadataKey: "../secret"])
        }
    }

    @Test("Rejects payload content changed after staging")
    func validatesHash() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NoteImportPayloadStore(rootDirectory: root)
        let note = ImportedNote(sourceKind: .markdownFolder, sourceIdentity: "note.md", title: "Note", markdownContent: "Original", rawByteHash: "raw", normalizedTextHash: "normalized")
        let metadata = try store.save(note, jobID: "job", itemID: "item")
        try Data("tampered".utf8).write(to: root.appendingPathComponent("job/item.json"))

        #expect(throws: NoteImportPayloadStoreError.hashMismatch("job/item.json")) {
            _ = try store.load(metadata: metadata)
        }
    }
}
