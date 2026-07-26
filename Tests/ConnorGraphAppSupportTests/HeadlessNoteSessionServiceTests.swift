import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphStore
@testable import ConnorGraphAppSupport

private struct HeadlessRecordingBackend: AgentBackend {
    let recorder: HeadlessPromptRecorder
    func chat(_ request: AgentChatRequest) -> AsyncThrowingStream<AgentEvent, Error> {
        recorder.record(request.userMessage)
        return AsyncThrowingStream { continuation in
            var run = AgentRun(id: request.runID, sessionID: request.sessionID, groupID: request.groupID, status: .running, model: "test")
            continuation.yield(.runStarted(.init(run: run)))
            continuation.yield(.textComplete(.init(runID: request.runID, sessionID: request.sessionID, text: "Processed", citations: [])))
            run.status = .completed; run.completedAt = Date()
            continuation.yield(.runCompleted(.init(run: run)))
            continuation.finish()
        }
    }
}

private final class HeadlessPromptRecorder: @unchecked Sendable {
    private let lock = NSLock(); private var value = ""
    func record(_ prompt: String) { lock.lock(); value = prompt; lock.unlock() }
    func prompt() -> String { lock.lock(); defer { lock.unlock() }; return value }
}

@Suite("Headless note session service")
struct HeadlessNoteSessionServiceTests {
    @Test("Creates a note session without selecting it in UI")
    func createsNoteSession() async throws {
        let fixture = try Fixture()
        let service = fixture.service()
        let session = try await service.createNoteSession(title: "Imported")
        #expect(session.governance.kind == .note)
        #expect(try fixture.repository.loadSession(id: session.id)?.title == "Imported")
        #expect(try AppNoteRepository(store: fixture.repository.store).note(sessionID: session.id) == nil)
    }

    @Test("Creates an imported note with its first message in one operation")
    func createsImportedNoteSession() async throws {
        let fixture = try Fixture()
        let service = fixture.service()
        let attachment = AgentMessageAttachmentRef(
            id: "attachment",
            displayName: "image.png",
            kind: .image,
            byteCount: 42,
            lifecycleStatus: .ready,
            extractionStatus: .pending,
            manifestRelativePath: "attachments/attachment/manifest.json"
        )

        let session = try await service.createImportedNoteSession(
            title: "Imported",
            content: "# Original note",
            attachments: [attachment]
        )

        let loaded = try #require(try fixture.repository.loadSession(id: session.id))
        #expect(loaded.governance.kind == AgentSessionKind.note)
        #expect(loaded.messages.count == 1)
        #expect(loaded.messages[0].content == "# Original note")
        #expect(loaded.messages[0].attachments.map { $0.id } == ["attachment"])
        let note = try #require(try AppNoteRepository(store: fixture.repository.store).note(sessionID: session.id))
        #expect(note.body == "# Original note")
        #expect(note.originKind == .imported)
        await service.associateImportedNote(sessionID: session.id, metadata: NoteImportProjectionMetadata(
            itemID: "item", sourceID: "source", sourceKind: "markdown_folder", sourceIdentity: "note.md",
            relativePath: "note.md", sourceCreatedAt: Date(timeIntervalSince1970: 100)
        ))
        let associated = try #require(try AppNoteRepository(store: fixture.repository.store).note(sessionID: session.id))
        #expect(associated.importItemID == "item")
        #expect(associated.relativePath == "note.md")
    }

    @Test("Reimport replaces every prior conversation message with one exact note body")
    func reimportKeepsOnlyOneBodyMessage() async throws {
        let fixture = try Fixture()
        let service = fixture.service()
        let original = try await service.createImportedNoteSession(
            id: "stable-note",
            title: "Original",
            content: "Original body",
            messageID: "old-message"
        )
        _ = try await service.saveImportedNote(sessionID: original.id, content: "Unwanted follow-up")

        let updated = try await service.createImportedNoteSession(
            id: original.id,
            title: "Updated",
            content: "Exact updated body",
            messageID: "new-message"
        )

        #expect(updated.title == "Updated")
        #expect(updated.messages.count == 1)
        #expect(updated.messages[0].id == "new-message")
        #expect(updated.messages[0].role == .user)
        #expect(updated.messages[0].content == "Exact updated body")
    }

    @Test("Persists display prompt while sending augmented note instructions to backend")
    func submitsHeadlessly() async throws {
        let fixture = try Fixture()
        let recorder = HeadlessPromptRecorder()
        let service = fixture.service(recorder: recorder)
        let session = try await service.createNoteSession(title: "Imported")
        let response = try await service.run(.init(sessionID: session.id, prompt: "# Original note"))
        let loaded = try #require(try fixture.repository.loadSession(id: session.id))
        #expect(loaded.messages.first?.content == "# Original note")
        #expect(loaded.messages.last?.content == "Processed")
        #expect(recorder.prompt().contains("<connor-note-session>"))
        #expect(response.responseText == "Processed")
    }

    @Test("Missing session fails without creating a foreground substitute")
    func missingSession() async throws {
        let fixture = try Fixture(); let service = fixture.service()
        await #expect(throws: HeadlessNoteSessionServiceError.sessionNotFound("missing")) {
            _ = try await service.run(.init(sessionID: "missing", prompt: "Note"))
        }
    }

    private final class Fixture {
        let directory: URL; let repository: AppChatSessionRepository
        init() throws { directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); let store = try SQLiteGraphKernelStore(path: directory.appendingPathComponent("db.sqlite").path); try store.migrate(); repository = AppChatSessionRepository(store: store) }
        deinit { try? FileManager.default.removeItem(at: directory) }
        func service(recorder: HeadlessPromptRecorder = .init()) -> HeadlessNoteSessionService {
            let repository = repository
            return HeadlessNoteSessionService(repository: repository) { session in
                NativeSessionManager(backend: HeadlessRecordingBackend(recorder: recorder), sessionRepository: repository, session: session)
            }
        }
    }
}
