import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphStore
@testable import ConnorGraphAppSupport

private struct RuntimeBackend: AgentBackend {
    func chat(_ request: AgentChatRequest) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            var run = AgentRun(id: request.runID, sessionID: request.sessionID, groupID: request.groupID, status: .running)
            continuation.yield(.runStarted(.init(run: run)))
            run.status = .completed
            continuation.yield(.runCompleted(.init(run: run)))
            continuation.finish()
        }
    }
}

@Suite("Note import runtime")
struct NoteImportRuntimeTests {
    @Test("Deduplicates repeated submissions and completes approved jobs")
    func deduplicatesSubmissions() async throws {
        let fixture = try Fixture()
        try fixture.saveReadyItem(jobID: "job")
        let runtime = fixture.runtime()

        #expect(await runtime.submit(jobID: "job"))
        #expect(await !runtime.submit(jobID: "job"))
        try await waitUntil { try fixture.ledger.job(id: "job")?.status == .completed }
        #expect(try fixture.ledger.job(id: "job")?.importedCount == 1)
        #expect(try fixture.chat.loadRecentSessions(limit: 10).count == 1)
    }

    @Test("Recovers approved jobs but preserves paused jobs")
    func recoversApprovedJobs() async throws {
        let fixture = try Fixture()
        try fixture.saveReadyItem(jobID: "recover")
        try fixture.saveReadyItem(jobID: "paused", paused: true)
        let runtime = fixture.runtime()

        try await runtime.recover()
        try await waitUntil { try fixture.ledger.job(id: "recover")?.status == .completed }
        #expect(try fixture.ledger.job(id: "paused")?.status == .awaitingReview)
        #expect(try fixture.ledger.item(id: "paused-item")?.sessionID == nil)
    }

    private func waitUntil(
        timeout: Duration = .seconds(3),
        condition: @escaping @Sendable () throws -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if try condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("Timed out waiting for note import runtime")
    }

    private final class Fixture: @unchecked Sendable {
        let directory: URL
        let path: String
        let ledger: AppNoteImportRepository
        let chat: AppChatSessionRepository

        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            path = directory.appendingPathComponent("graph.sqlite").path
            let store = try SQLiteGraphKernelStore(path: path)
            try store.migrate()
            chat = AppChatSessionRepository(store: store)
            ledger = try AppNoteImportRepository(databasePath: path)
            try ledger.saveSource(NoteImportSourceRecord(id: "source", kind: .markdownFolder, displayName: "Notes"))
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        func runtime() -> NoteImportRuntime {
            let service = HeadlessNoteSessionService(repository: chat) { session in
                NativeSessionManager(backend: RuntimeBackend(), sessionRepository: self.chat, session: session)
            }
            return NoteImportRuntime(ledger: ledger, coordinator: NoteImportCoordinator(ledger: ledger, sessionService: service))
        }

        func saveReadyItem(jobID: String, paused: Bool = false) throws {
            let note = ImportedNote(sourceKind: .markdownFolder, sourceIdentity: "\(jobID).md", title: jobID, markdownContent: "# \(jobID)", rawByteHash: jobID, normalizedTextHash: jobID)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let payload = try encoder.encode(note).base64EncodedString()
            var job = NoteImportJobRecord(id: jobID, sourceID: "source", status: .awaitingReview, options: .init(llmMode: .disabled), discoveredCount: 1)
            if paused { job.pauseRequestedAt = Date() }
            try ledger.saveJob(job)
            try ledger.saveItem(NoteImportItemRecord(id: "\(jobID)-item", jobID: jobID, sourceID: "source", sourceIdentity: note.sourceIdentity, title: note.title, status: .ready, rawByteHash: note.rawByteHash, normalizedTextHash: note.normalizedTextHash, metadata: ["imported_note_payload": payload]))
        }
    }
}
