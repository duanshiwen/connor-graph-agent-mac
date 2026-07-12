import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore
@testable import ConnorGraphAppSupport

@Suite("Note import ledger")
struct AppNoteImportRepositoryTests {
    @Test("Persists a recoverable job across repository reopen")
    func persistsRecoverableJob() throws {
        let fixture = try Fixture()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let source = NoteImportSourceRecord(id: "source", kind: .markdownFolder, displayName: "Notes", locationBookmark: Data([1, 2, 3]), createdAt: timestamp)
        let job = NoteImportJobRecord(id: "job", sourceID: source.id, status: .scanning, createdAt: timestamp, updatedAt: timestamp)
        try fixture.repository.saveSource(source)
        try fixture.repository.saveJob(job)

        let reopened = try AppNoteImportRepository(databasePath: fixture.path)
        #expect(try reopened.source(id: source.id) == source)
        #expect(try reopened.recoverableJobs().map(\.id) == [job.id])
    }

    @Test("Terminal jobs are not returned for recovery")
    func excludesTerminalJobs() throws {
        let fixture = try Fixture()
        let source = NoteImportSourceRecord(id: "source", kind: .obsidianVault, displayName: "Vault")
        try fixture.repository.saveSource(source)
        try fixture.repository.saveJob(NoteImportJobRecord(id: "running", sourceID: source.id, status: .processing))
        try fixture.repository.saveJob(NoteImportJobRecord(id: "complete", sourceID: source.id, status: .completed))
        #expect(try fixture.repository.recoverableJobs().map(\.id) == ["running"])
    }

    @Test("Persists item provenance and finds latest source identity")
    func persistsItemProvenance() throws {
        let fixture = try Fixture()
        let source = NoteImportSourceRecord(id: "source", kind: .notionExport, displayName: "Notion")
        let job = NoteImportJobRecord(id: "job", sourceID: source.id, status: .ready)
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let item = NoteImportItemRecord(jobID: job.id, sourceID: source.id, sourceIdentity: "page-123", externalID: "123", relativePath: "Page 123.md", title: "Page", rawByteHash: "raw", normalizedTextHash: "text", sourceEncoding: "utf-8", encodingConfidence: 1, decoderVersion: "1", createdAt: timestamp, updatedAt: timestamp)
        try fixture.repository.saveSource(source)
        try fixture.repository.saveJob(job)
        try fixture.repository.saveItem(item)
        #expect(try fixture.repository.item(id: item.id) == item)
        #expect(try fixture.repository.latestItem(sourceID: source.id, sourceIdentity: item.sourceIdentity)?.id == item.id)
    }

    @Test("Duplicate identity in one job is rejected")
    func rejectsDuplicateJobIdentity() throws {
        let fixture = try Fixture()
        let source = NoteImportSourceRecord(id: "source", kind: .markdownFolder, displayName: "Notes")
        let job = NoteImportJobRecord(id: "job", sourceID: source.id)
        try fixture.repository.saveSource(source)
        try fixture.repository.saveJob(job)
        try fixture.repository.saveItem(NoteImportItemRecord(id: "one", jobID: job.id, sourceID: source.id, sourceIdentity: "same.md", title: "One", rawByteHash: "1", normalizedTextHash: "1"))
        #expect(throws: (any Error).self) {
            try fixture.repository.saveItem(NoteImportItemRecord(id: "two", jobID: job.id, sourceID: source.id, sourceIdentity: "same.md", title: "Two", rawByteHash: "2", normalizedTextHash: "2"))
        }
    }

    @Test("Persists scheduler intent and item leases across reopen")
    func persistsSchedulerState() throws {
        let fixture = try Fixture()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let source = NoteImportSourceRecord(id: "source", kind: .markdownFolder, displayName: "Notes")
        try fixture.repository.saveSource(source)
        try fixture.repository.saveJob(NoteImportJobRecord(id: "job", sourceID: source.id, status: .processing))
        let item = NoteImportItemRecord(id: "item", jobID: "job", sourceID: source.id, sourceIdentity: "one.md", title: "One", status: .queuedForLLM, rawByteHash: "raw", normalizedTextHash: "text", sourceRevision: "v1")
        try fixture.repository.saveItem(item)
        _ = try fixture.repository.requestPause(jobID: "job", now: now)
        _ = try fixture.repository.heartbeat(jobID: "job", schedulerVersion: "2", now: now)
        #expect(try fixture.repository.claimItem(id: item.id, owner: "worker-a", leaseDuration: 60, now: now)?.attemptCount == 1)
        #expect(try fixture.repository.claimItem(id: item.id, owner: "worker-b", leaseDuration: 60, now: now) == nil)

        let reopened = try AppNoteImportRepository(databasePath: fixture.path)
        #expect(try reopened.job(id: "job")?.pauseRequestedAt == now)
        #expect(try reopened.job(id: "job")?.schedulerVersion == "2")
        #expect(try reopened.item(id: item.id)?.leaseOwner == "worker-a")
        #expect(try reopened.claimItem(id: item.id, owner: "worker-b", leaseDuration: 60, now: now.addingTimeInterval(61))?.leaseOwner == "worker-b")
    }

    @Test("Reconciles interrupted stages without recreating an existing session")
    func reconcilesInterruptedStages() throws {
        let fixture = try Fixture()
        let source = NoteImportSourceRecord(id: "source", kind: .markdownFolder, displayName: "Notes")
        try fixture.repository.saveSource(source)
        try fixture.repository.saveJob(NoteImportJobRecord(id: "job", sourceID: source.id, status: .processing))
        let graphStore = try SQLiteGraphKernelStore(path: fixture.path)
        let sessions = AppChatSessionRepository(store: graphStore)
        let existingSession = try sessions.createSession(title: "A")
        let llmSession = try sessions.createSession(title: "C")
        try fixture.repository.saveItem(NoteImportItemRecord(id: "with-session", jobID: "job", sourceID: source.id, sourceIdentity: "a", title: "A", status: .creatingSession, sessionID: existingSession.id, rawByteHash: "a", normalizedTextHash: "a", leaseOwner: "dead", leaseExpiresAt: .distantPast))
        try fixture.repository.saveItem(NoteImportItemRecord(id: "without-session", jobID: "job", sourceID: source.id, sourceIdentity: "b", title: "B", status: .creatingSession, rawByteHash: "b", normalizedTextHash: "b"))
        try fixture.repository.saveItem(NoteImportItemRecord(id: "llm", jobID: "job", sourceID: source.id, sourceIdentity: "c", title: "C", status: .runningLLM, sessionID: llmSession.id, rawByteHash: "c", normalizedTextHash: "c"))

        _ = try fixture.repository.reconcileInterruptedItems(jobID: "job")
        #expect(try fixture.repository.item(id: "with-session")?.status == .imported)
        #expect(try fixture.repository.item(id: "with-session")?.sessionID == existingSession.id)
        #expect(try fixture.repository.item(id: "without-session")?.status == .ready)
        #expect(try fixture.repository.item(id: "llm")?.status == .queuedForLLM)
        #expect(try fixture.repository.item(id: "with-session")?.leaseOwner == nil)
    }

    @Test("Repository validates persisted transitions")
    func validatesTransitions() throws {
        let fixture = try Fixture()
        let source = NoteImportSourceRecord(id: "source", kind: .evernoteENEX, displayName: "Evernote")
        try fixture.repository.saveSource(source)
        try fixture.repository.saveJob(NoteImportJobRecord(id: "job", sourceID: source.id))
        #expect(try fixture.repository.transitionJob(id: "job", to: .scanning).status == .scanning)
        #expect(throws: NoteImportStateTransitionError.invalidJobTransition(from: .scanning, to: .completed)) {
            _ = try fixture.repository.transitionJob(id: "job", to: .completed)
        }
    }

    private final class Fixture {
        let directory: URL
        let path: String
        let repository: AppNoteImportRepository

        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            path = directory.appendingPathComponent("graph.sqlite").path
            let graphStore = try SQLiteGraphKernelStore(path: path)
            try graphStore.migrate()
            repository = try AppNoteImportRepository(databasePath: path)
        }

        deinit { try? FileManager.default.removeItem(at: directory) }
    }
}
