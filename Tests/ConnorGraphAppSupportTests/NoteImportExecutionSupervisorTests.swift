import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphStore
@testable import ConnorGraphAppSupport

@Suite("Note import execution supervisor")
struct NoteImportExecutionSupervisorTests {
    @Test("Recovers an orphaned cancelling job to a terminal state")
    func recoversOrphanedCancellation() async throws {
        let fixture = try SupervisorFixture(status: .processing, cancelRequestedAt: Date())
        try fixture.saveReadyItem()
        let supervisor = NoteImportExecutionSupervisor(coordinator: fixture.coordinator)

        await supervisor.recoverPersistedJobs()
        await fixture.waitUntilTerminal()

        #expect(try fixture.ledger.job(id: "job")?.status == .cancelled)
        #expect(try fixture.ledger.item(id: "item")?.status == .cancelled)
        #expect(await !supervisor.isRunning(jobID: "job"))
    }

    @Test("Does not auto-run a persisted paused job")
    func leavesPausedJobStopped() async throws {
        let fixture = try SupervisorFixture(status: .paused)
        try fixture.saveReadyItem()
        let supervisor = NoteImportExecutionSupervisor(coordinator: fixture.coordinator)

        await supervisor.recoverPersistedJobs()
        try await Task.sleep(for: .milliseconds(30))

        #expect(try fixture.ledger.job(id: "job")?.status == .paused)
        #expect(try fixture.ledger.item(id: "item")?.status == .ready)
        #expect(await !supervisor.isRunning(jobID: "job"))
    }

    @Test("Repeated ensureRunning calls share one job driver")
    func ensureRunningIsIdempotent() async throws {
        let fixture = try SupervisorFixture(status: .processing)
        let supervisor = NoteImportExecutionSupervisor(coordinator: fixture.coordinator)

        await supervisor.ensureRunning(jobID: "job")
        await supervisor.ensureRunning(jobID: "job")
        await fixture.waitUntilTerminal()

        #expect(try fixture.ledger.job(id: "job")?.status == .completed)
        #expect(await !supervisor.isRunning(jobID: "job"))
    }
}

private struct SupervisorBackend: AgentBackend {
    func chat(_ request: AgentChatRequest) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

private final class SupervisorFixture: @unchecked Sendable {
    let directory: URL
    let ledger: AppNoteImportRepository
    let coordinator: NoteImportCoordinator

    init(status: NoteImportJobStatus, cancelRequestedAt: Date? = nil) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("graph.sqlite").path
        let store = try SQLiteGraphKernelStore(path: path)
        try store.migrate()
        let chat = AppChatSessionRepository(store: store)
        ledger = try AppNoteImportRepository(databasePath: path)
        try ledger.saveSource(NoteImportSourceRecord(id: "source", kind: .markdownFolder, displayName: "Notes"))
        try ledger.saveJob(NoteImportJobRecord(
            id: "job",
            sourceID: "source",
            status: status,
            options: .init(llmMode: .disabled),
            discoveredCount: 1,
            cancelRequestedAt: cancelRequestedAt
        ))
        let service = HeadlessNoteSessionService(repository: chat) { session in
            NativeSessionManager(backend: SupervisorBackend(), sessionRepository: chat, session: session)
        }
        coordinator = NoteImportCoordinator(ledger: ledger, sessionService: service)
    }

    func saveReadyItem() throws {
        let note = ImportedNote(
            sourceKind: .markdownFolder,
            sourceIdentity: "note.md",
            title: "Note",
            markdownContent: "Body",
            rawByteHash: "raw",
            normalizedTextHash: "text"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try ledger.saveItem(NoteImportItemRecord(
            id: "item",
            jobID: "job",
            sourceID: "source",
            sourceIdentity: note.sourceIdentity,
            title: note.title,
            status: .ready,
            rawByteHash: note.rawByteHash,
            normalizedTextHash: note.normalizedTextHash,
            metadata: ["imported_note_payload": try encoder.encode(note).base64EncodedString()]
        ))
    }

    func waitUntilTerminal(timeout: Duration = .seconds(5)) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if (try? ledger.job(id: "job")?.status.isTerminal) == true { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Timed out waiting for note import job to become terminal")
    }

    deinit { try? FileManager.default.removeItem(at: directory) }
}
