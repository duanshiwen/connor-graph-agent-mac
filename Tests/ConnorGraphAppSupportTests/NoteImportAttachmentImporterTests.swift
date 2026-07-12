import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphStore
@testable import ConnorGraphAppSupport

private struct AttachmentBackend: AgentBackend {
    func chat(_ request: AgentChatRequest) -> AsyncThrowingStream<AgentEvent, Error> { AsyncThrowingStream { c in var run = AgentRun(id: request.runID, sessionID: request.sessionID, groupID: request.groupID, status: .running); c.yield(.runStarted(.init(run: run))); run.status = .completed; c.yield(.runCompleted(.init(run: run))); c.finish() } }
}

@Suite("Note import attachment pipeline")
struct NoteImportAttachmentImporterTests {
    @Test("Copies into session storage, verifies hash, and reuses within a session")
    func importsIdempotently() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let file = fixture.root.appendingPathComponent("picture.txt"); try Data("attachment".utf8).write(to: file)
        let hash = try AppSessionAttachmentStore.sha256Hex(forItemAt: file)
        let attachment = ImportedNoteAttachment(sourcePath: file.path, displayName: "picture.txt", byteCount: 10, contentHash: hash)
        let importer = NoteImportAttachmentImporter(store: fixture.attachmentStore)
        let first = try await importer.importAttachment(attachment, sessionID: fixture.session.id)
        let second = try await importer.importAttachment(attachment, sessionID: fixture.session.id)
        #expect(first.reused == false); #expect(second.reused == true); #expect(first.messageRef.id == second.messageRef.id)
        try FileManager.default.removeItem(at: file)
        #expect(try fixture.attachmentStore.loadManifest(sessionID: fixture.session.id, attachmentID: first.messageRef.id).sha256 == hash)
    }

    @Test("Headless run persists imported attachment refs on the user message")
    func persistsOnMessage() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let file = fixture.root.appendingPathComponent("note.txt"); try "context".write(to: file, atomically: true, encoding: .utf8)
        let manifest = try fixture.attachmentStore.importFile(at: file, sessionID: fixture.session.id)
        let attachedService = HeadlessNoteSessionService(repository: fixture.chat, managerFactory: { session in NativeSessionManager(backend: AttachmentBackend(), sessionRepository: fixture.chat, session: session) }, attachmentStore: fixture.attachmentStore)
        _ = try await attachedService.run(.init(sessionID: fixture.session.id, prompt: "hello", attachmentIDs: [manifest.id]))
        let loaded = try fixture.chat.loadSession(id: fixture.session.id)
        let reloaded = try #require(loaded)
        #expect(reloaded.messages.first?.attachments.map(\.id) == [manifest.id])
    }

    @Test("Rejects a mismatched source hash")
    func rejectsHashMismatch() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let file = fixture.root.appendingPathComponent("bad.txt"); try "bad".write(to: file, atomically: true, encoding: .utf8)
        let importer = NoteImportAttachmentImporter(store: fixture.attachmentStore)
        await #expect(throws: NoteImportAttachmentImporterError.self) { _ = try await importer.importAttachment(.init(sourcePath: file.path, displayName: "bad.txt", contentHash: "wrong"), sessionID: fixture.session.id) }
    }

    private final class Fixture: @unchecked Sendable {
        let root: URL; let chat: AppChatSessionRepository; let attachmentStore: AppSessionAttachmentStore; let session: AgentSession
        init() throws { root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); let store = try SQLiteGraphKernelStore(path: root.appendingPathComponent("db.sqlite").path); try store.migrate(); chat = AppChatSessionRepository(store: store); session = try chat.createSession(title: "Note"); attachmentStore = AppSessionAttachmentStore(paths: AppStoragePaths(applicationSupportDirectory: root.appendingPathComponent("support"))) }
        func cleanup() { try? FileManager.default.removeItem(at: root) }
    }
}
