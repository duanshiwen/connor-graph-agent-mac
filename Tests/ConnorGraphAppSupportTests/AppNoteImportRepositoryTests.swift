import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore
@testable import ConnorGraphAppSupport

@Suite("Note import ledger")
struct AppNoteImportRepositoryTests {
    @Test("Pages every import job and item with stable tie-break ordering")
    func pagesAllJobsAndItems() throws {
        let fixture = try Fixture()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let source = NoteImportSourceRecord(id: "source", kind: .markdownFolder, displayName: "Notes", createdAt: timestamp)
        try fixture.repository.saveSource(source)
        for index in 0..<137 {
            let id = String(format: "job-%03d", index)
            try fixture.repository.saveJob(.init(id: id, sourceID: source.id, status: .completed, createdAt: timestamp, updatedAt: timestamp))
        }
        try fixture.repository.saveJob(.init(id: "item-job", sourceID: source.id, status: .completed, createdAt: timestamp, updatedAt: timestamp.addingTimeInterval(-1)))
        for index in 0..<137 {
            let id = String(format: "item-%03d", index)
            try fixture.repository.saveItem(.init(id: id, jobID: "item-job", sourceID: source.id, sourceIdentity: "\(id).md", title: id, status: .completed, rawByteHash: id, normalizedTextHash: id, createdAt: timestamp, updatedAt: timestamp))
        }

        var jobIDs: [String] = []
        var jobCursor: String?
        repeat {
            let page = try fixture.repository.jobPage(cursor: jobCursor, pageSize: 50)
            jobIDs += page.jobs.map(\.id)
            jobCursor = page.nextCursor
        } while jobCursor != nil

        var itemIDs: [String] = []
        var itemCursor: String?
        repeat {
            let page = try fixture.repository.itemPage(jobID: "item-job", cursor: itemCursor, pageSize: 50)
            itemIDs += page.items.map(\.id)
            itemCursor = page.nextCursor
        } while itemCursor != nil

        #expect(jobIDs == ["item-job"] + (0..<137).map { String(format: "job-%03d", $0) })
        #expect(Set(jobIDs).count == 138)
        #expect(itemIDs == (0..<137).map { String(format: "item-%03d", $0) })
        #expect(Set(itemIDs).count == 137)
    }

    @Test("Batch scan persists items and updates job counters atomically")
    func batchScanPersistsItemsAndUpdatesCounters() throws {
        let fixture = try Fixture()
        let source = NoteImportSourceRecord(kind: .markdownFolder, displayName: "Batch")
        try fixture.repository.saveSource(source)
        let job = NoteImportJobRecord(sourceID: source.id)
        try fixture.repository.saveJob(job)
        let first = NoteImportItemRecord(
            jobID: job.id,
            sourceID: source.id,
            sourceIdentity: "first.md",
            title: "First",
            status: .ready,
            rawByteHash: "raw-1",
            normalizedTextHash: "normalized-1"
        )
        let duplicate = NoteImportItemRecord(
            jobID: job.id,
            sourceID: source.id,
            sourceIdentity: "first.md",
            title: "Duplicate",
            status: .ready,
            rawByteHash: "raw-2",
            normalizedTextHash: "normalized-2"
        )
        let second = NoteImportItemRecord(
            jobID: job.id,
            sourceID: source.id,
            sourceIdentity: "second.md",
            title: "Second",
            status: .ready,
            rawByteHash: "raw-3",
            normalizedTextHash: "normalized-3"
        )

        let result = try fixture.repository.appendScannedItems(jobID: job.id, items: [first, duplicate, second])

        #expect(result.inserted == 2)
        #expect(result.duplicates == 1)
        #expect(try fixture.repository.items(jobID: job.id).count == 2)
        let loadedJob = try fixture.repository.job(id: job.id)
        let persisted = try #require(loadedJob)
        #expect(persisted.discoveredCount == 2)
        #expect(persisted.duplicateCount == 1)
    }

    @Test("Updates completion counters immediately and repairs stale active-job projections")
    func liveProgressCounters() throws {
        let fixture = try Fixture()
        let source = NoteImportSourceRecord(id: "source", kind: .markdownFolder, displayName: "Notes")
        try fixture.repository.saveSource(source)
        try fixture.repository.saveJob(.init(id: "job", sourceID: source.id, status: .processing, discoveredCount: 2))
        try fixture.repository.saveItem(.init(id: "done", jobID: "job", sourceID: source.id, sourceIdentity: "done.md", title: "Done", status: .ready, rawByteHash: "raw", normalizedTextHash: "text"))

        _ = try fixture.repository.transitionItem(id: "done", to: .creatingSession)
        let loadedImported = try fixture.repository.item(id: "done")
        var imported = try #require(loadedImported)
        imported.status = .imported
        try fixture.repository.saveItem(imported)
        #expect(try fixture.repository.job(id: "job")?.importedCount == 0)
        _ = try fixture.repository.transitionItem(id: "done", to: .completed)
        #expect(try fixture.repository.job(id: "job")?.importedCount == 1)

        try fixture.repository.saveItem(.init(id: "failed", jobID: "job", sourceID: source.id, sourceIdentity: "failed.md", title: "Failed", status: .sessionFailed, rawByteHash: "raw-2", normalizedTextHash: "text-2"))
        #expect(try fixture.repository.job(id: "job")?.failedCount == 1)

        let loadedStale = try fixture.repository.job(id: "job")
        var stale = try #require(loadedStale)
        stale.importedCount = 0
        stale.failedCount = 0
        try fixture.repository.saveJob(stale)
        let projectedJobs = try fixture.repository.jobsWithLiveCounts()
        let projected = try #require(projectedJobs.first)
        #expect(projected.importedCount == 1)
        #expect(projected.failedCount == 1)
        #expect(try fixture.repository.job(id: "job")?.importedCount == 0)
    }

    @Test("Deletes only terminal import records and preserves imported sessions")
    func deletesTerminalJobRecords() throws {
        let fixture = try Fixture()
        let source = NoteImportSourceRecord(id: "source", kind: .markdownFolder, displayName: "Notes")
        try fixture.repository.saveSource(source)
        let graph = try SQLiteGraphKernelStore(path: fixture.path)
        let sessions = AppChatSessionRepository(store: graph)
        let session = try sessions.createImportedNoteSession(title: "Imported", content: "Body")
        try fixture.repository.saveJob(.init(id: "completed", sourceID: source.id, status: .completed, discoveredCount: 1, importedCount: 1))
        try fixture.repository.saveItem(.init(id: "item", jobID: "completed", sourceID: source.id, sourceIdentity: "note.md", title: "Imported", status: .completed, sessionID: session.id, rawByteHash: "raw", normalizedTextHash: "text"))

        try fixture.repository.deleteJob(id: "completed")

        #expect(try fixture.repository.job(id: "completed") == nil)
        #expect(try fixture.repository.item(id: "item") == nil)
        #expect(try fixture.repository.source(id: source.id) != nil)
        #expect(try sessions.loadSession(id: session.id) != nil)

        try fixture.repository.saveJob(.init(id: "active", sourceID: source.id, status: .processing))
        #expect(throws: AppNoteImportRepositoryError.jobControlUnavailable("Active import tasks cannot be deleted")) {
            try fixture.repository.deleteJob(id: "active")
        }
    }
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

    @Test("Pause and resume preserve an active processing phase")
    func pauseAndResumeActiveJob() throws {
        let fixture = try Fixture()
        let pausedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let resumedAt = pausedAt.addingTimeInterval(5)
        let source = NoteImportSourceRecord(id: "source", kind: .markdownFolder, displayName: "Notes")
        try fixture.repository.saveSource(source)
        try fixture.repository.saveJob(NoteImportJobRecord(id: "job", sourceID: source.id, status: .processing))

        let paused = try fixture.repository.requestPause(jobID: "job", now: pausedAt)
        #expect(paused.status == .processing)
        #expect(paused.pauseRequestedAt == pausedAt)

        let resumed = try fixture.repository.resumeJob(jobID: "job", now: resumedAt)
        #expect(resumed.status == .processing)
        #expect(resumed.pauseRequestedAt == nil)
        #expect(resumed.resumedAt == resumedAt)
    }

    @Test("Resume migrates a legacy paused job to its persisted work phase")
    func resumesLegacyPausedJob() throws {
        let fixture = try Fixture()
        let source = NoteImportSourceRecord(id: "source", kind: .markdownFolder, displayName: "Notes")
        try fixture.repository.saveSource(source)
        try fixture.repository.saveJob(NoteImportJobRecord(id: "job", sourceID: source.id, status: .paused))
        try fixture.repository.saveItem(NoteImportItemRecord(
            id: "item",
            jobID: "job",
            sourceID: source.id,
            sourceIdentity: "note.md",
            title: "Note",
            status: .runningLLM,
            rawByteHash: "raw",
            normalizedTextHash: "text"
        ))

        let resumed = try fixture.repository.resumeJob(jobID: "job")
        #expect(resumed.status == .processing)
        #expect(resumed.pauseRequestedAt == nil)
        #expect(resumed.resumedAt != nil)
    }

    @Test("Terminal jobs reject pause and resume controls")
    func terminalJobsRejectControls() throws {
        let fixture = try Fixture()
        let source = NoteImportSourceRecord(id: "source", kind: .markdownFolder, displayName: "Notes")
        try fixture.repository.saveSource(source)
        try fixture.repository.saveJob(NoteImportJobRecord(id: "job", sourceID: source.id, status: .completed))

        #expect(throws: AppNoteImportRepositoryError.jobControlUnavailable("Task cannot be paused from completed")) {
            _ = try fixture.repository.requestPause(jobID: "job")
        }
        #expect(throws: AppNoteImportRepositoryError.jobControlUnavailable("Task is not paused")) {
            _ = try fixture.repository.resumeJob(jobID: "job")
        }
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
