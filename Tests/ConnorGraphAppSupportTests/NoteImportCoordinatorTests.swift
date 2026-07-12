import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphStore
@testable import ConnorGraphAppSupport

private struct CoordinatorBackend: AgentBackend {
    func chat(_ request: AgentChatRequest) -> AsyncThrowingStream<AgentEvent, Error> { AsyncThrowingStream { c in var run = AgentRun(id: request.runID, sessionID: request.sessionID, groupID: request.groupID, status: .running); c.yield(.runStarted(.init(run: run))); c.yield(.textComplete(.init(runID: request.runID, sessionID: request.sessionID, text: "Done", citations: []))); run.status = .completed; c.yield(.runCompleted(.init(run: run))); c.finish() } }
}

@Suite("Note import coordinator")
struct NoteImportCoordinatorTests {
    @Test("Scans, creates note sessions, and processes them headlessly")
    func endToEnd() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        try Data("# First\nBody".utf8).write(to: root.appendingPathComponent("first.md"))
        try Data("# Second\nBody".utf8).write(to: root.appendingPathComponent("second.md"))
        let store = try SQLiteGraphKernelStore(path: root.appendingPathComponent("db.sqlite").path); try store.migrate()
        let chat = AppChatSessionRepository(store: store); let ledger = try AppNoteImportRepository(databasePath: root.appendingPathComponent("db.sqlite").path)
        let source = NoteImportSourceRecord(id: "source", kind: .markdownFolder, displayName: "Notes"); try ledger.saveSource(source)
        let job = NoteImportJobRecord(id: "job", sourceID: source.id, options: .init(llmMode: .automatic)); try ledger.saveJob(job)
        let sessionService = HeadlessNoteSessionService(repository: chat) { session in NativeSessionManager(backend: CoordinatorBackend(), sessionRepository: chat, session: session) }
        let coordinator = NoteImportCoordinator(ledger: ledger, sessionService: sessionService)
        let request = NoteImportScanRequest(sourceID: source.id, sourceURL: root, kind: .markdownFolder, options: job.options)
        #expect(try await coordinator.scan(jobID: job.id, adapter: MarkdownFolderNoteImportAdapter(), request: request).status == .awaitingReview)
        #expect(try await coordinator.execute(jobID: job.id).status == .completed)
        let progress = try await coordinator.progress(jobID: job.id)
        #expect(progress.discovered == 2); #expect(progress.completed == 2); #expect(progress.failed == 0)
        let sessions = try chat.loadRecentSessions(limit: 10)
        #expect(sessions.count == 2); #expect(sessions.allSatisfy { $0.governance.kind == .note && $0.messages.count == 2 })
    }
}
