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
