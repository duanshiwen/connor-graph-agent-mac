import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphStore
import ConnorGraphAppSupport
@testable import ConnorGraphAgentMac

@MainActor @Suite("Note import UI presentation")
struct NoteImportViewModelTests {
    @Test("Filters only notes requiring encoding review")
    func encodingReview() {
        let model = NoteImportViewModel()
        model.notes = [
            .init(sourceKind: .markdownFolder, sourceIdentity: "a", title: "A", markdownContent: "A", rawByteHash: "a", normalizedTextHash: "a"),
            .init(sourceKind: .markdownFolder, sourceIdentity: "b", title: "B", markdownContent: "B", rawByteHash: "b", normalizedTextHash: "b", diagnostics: [.init(code: .decodingAmbiguous, severity: .warning, message: "Review")])
        ]
        #expect(model.encodingReview.map(\.title) == ["B"])
    }

    @Test("Wizard uses the four-stage review flow")
    func steps() {
        let model = NoteImportViewModel()
        #expect(model.step == .source)
        model.sourceURL = URL(fileURLWithPath: "/tmp/notes")
        model.advance()
        #expect(model.step == .review)
        model.advance()
        #expect(model.step == .options)
        model.back()
        #expect(model.step == .review)
    }

    @Test("Search filters note titles and paths")
    func filtersNotes() {
        let model = NoteImportViewModel()
        model.notes = [
            .init(sourceKind: .markdownFolder, sourceIdentity: "a", relativePath: "work/plan.md", title: "计划", markdownContent: "A", rawByteHash: "a", normalizedTextHash: "a"),
            .init(sourceKind: .markdownFolder, sourceIdentity: "b", relativePath: "life/log.md", title: "日志", markdownContent: "B", rawByteHash: "b", normalizedTextHash: "b")
        ]
        model.searchText = "work"
        #expect(model.filteredNotes.map(\.title) == ["计划"])
    }

    @Test("Selecting a job loads its items through the async projection reader")
    func selectingJobLoadsItems() async throws {
        let fixture = try ImportLedgerFixture()
        try fixture.repository.saveSource(NoteImportSourceRecord(id: "source", kind: .markdownFolder, displayName: "Notes"))
        try fixture.repository.saveJob(NoteImportJobRecord(id: "first", sourceID: "source", status: .completed))
        try fixture.repository.saveJob(NoteImportJobRecord(id: "second", sourceID: "source", status: .completed))
        try fixture.repository.saveItem(NoteImportItemRecord(
            id: "second-item",
            jobID: "second",
            sourceID: "source",
            sourceIdentity: "second.md",
            title: "Second",
            status: .completed,
            rawByteHash: "raw",
            normalizedTextHash: "normalized"
        ))
        let model = NoteImportViewModel(ledger: fixture.repository)
        await model.reloadJobs()

        await model.selectJob("second")

        #expect(model.selectedJobID == "second")
        #expect(model.selectedJobItems.map(\.id) == ["second-item"])
    }

    @Test("Monitoring refreshes persisted progress and stops at a terminal state")
    func monitoringRefreshesProgress() async throws {
        let fixture = try ImportLedgerFixture()
        try fixture.repository.saveSource(NoteImportSourceRecord(id: "source", kind: .markdownFolder, displayName: "Notes"))
        try fixture.repository.saveJob(NoteImportJobRecord(
            id: "job",
            sourceID: "source",
            status: .processing,
            discoveredCount: 4,
            importedCount: 1
        ))
        try fixture.repository.saveItem(NoteImportItemRecord(id: "completed", jobID: "job", sourceID: "source", sourceIdentity: "completed.md", title: "Completed", status: .completed, rawByteHash: "raw", normalizedTextHash: "text"))
        let model = NoteImportViewModel(ledger: fixture.repository, monitoringInterval: .milliseconds(10))
        await model.reloadJobs()

        #expect(model.activitySummary.progressFraction == 0.25)
        #expect(model.isMonitoringJobs)
        model.startJobMonitoring()
        #expect(model.isMonitoringJobs)

        let persistedJob = try fixture.repository.job(id: "job")
        var updated = try #require(persistedJob)
        updated.importedCount = 3
        updated.status = .completed
        try fixture.repository.saveJob(updated)

        await waitUntil { model.jobs.first?.status == .completed }
        #expect(model.activitySummary.isVisible == false)
        await waitUntil { !model.isMonitoringJobs }
    }

    @Test("Monitoring follows a post-scan job beyond awaiting review")
    func monitoringFollowsAwaitingReviewTransition() async throws {
        let fixture = try ImportLedgerFixture()
        try fixture.repository.saveSource(NoteImportSourceRecord(id: "source", kind: .markdownFolder, displayName: "Notes"))
        try fixture.repository.saveJob(NoteImportJobRecord(
            id: "job",
            sourceID: "source",
            status: .awaitingReview,
            discoveredCount: 392
        ))
        for index in 0..<5 {
            try fixture.repository.saveItem(NoteImportItemRecord(id: "completed-\(index)", jobID: "job", sourceID: "source", sourceIdentity: "completed-\(index).md", title: "Completed", status: .completed, rawByteHash: "raw-\(index)", normalizedTextHash: "text-\(index)"))
        }
        let model = NoteImportViewModel(ledger: fixture.repository, monitoringInterval: .milliseconds(10))
        await model.reloadJobs()

        #expect(model.selectedJob?.status == .awaitingReview)
        #expect(model.isMonitoringJobs)

        let persistedJob = try fixture.repository.job(id: "job")
        var running = try #require(persistedJob)
        running.status = .processing
        running.importedCount = 5
        try fixture.repository.saveJob(running)
        await waitUntil { model.selectedJob?.status == .processing }
        #expect(model.selectedJob?.importedCount == 5)

        running.status = .completed
        try fixture.repository.saveJob(running)
        await waitUntil { model.selectedJob?.status == .completed }
        await waitUntil { !model.isMonitoringJobs }
    }

    @Test("Monitoring refreshes selected Markdown item states and completion count")
    func monitoringRefreshesSelectedItems() async throws {
        let fixture = try ImportLedgerFixture()
        try fixture.repository.saveSource(.init(id: "source", kind: .markdownFolder, displayName: "Notes"))
        try fixture.repository.saveJob(.init(id: "job", sourceID: "source", status: .processing, discoveredCount: 1))
        try fixture.repository.saveItem(.init(id: "item", jobID: "job", sourceID: "source", sourceIdentity: "nested/note.md", relativePath: "nested/note.md", title: "Note", status: .ready, rawByteHash: "raw", normalizedTextHash: "text"))
        let model = NoteImportViewModel(ledger: fixture.repository, monitoringInterval: .milliseconds(10))
        await model.reloadJobs()
        #expect(model.selectedJobItems.first?.status == .ready)

        _ = try fixture.repository.transitionItem(id: "item", to: .creatingSession)
        let loadedImported = try fixture.repository.item(id: "item")
        var imported = try #require(loadedImported)
        imported.status = .imported
        try fixture.repository.saveItem(imported)
        _ = try fixture.repository.transitionItem(id: "item", to: .completed)

        await waitUntil {
            model.selectedJobItems.first?.status == .completed
                && model.selectedJob?.importedCount == 1
        }
        #expect(model.activitySummary.progressFraction == 1)
    }

    @Test("Resume replaces a legacy paused snapshot and executes remaining work")
    func resumeExecutesRemainingWork() async throws {
        let fixture = try ImportLedgerFixture()
        try fixture.repository.saveSource(NoteImportSourceRecord(id: "source", kind: .markdownFolder, displayName: "Notes"))
        try fixture.repository.saveJob(NoteImportJobRecord(
            id: "paused",
            sourceID: "source",
            status: .paused,
            discoveredCount: 4,
            importedCount: 2
        ))
        let payload = ImportedNote(
            sourceKind: .markdownFolder,
            sourceIdentity: "note.md",
            title: "Note",
            markdownContent: "Body",
            rawByteHash: "raw",
            normalizedTextHash: "text"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try fixture.repository.saveItem(NoteImportItemRecord(
            id: "item",
            jobID: "paused",
            sourceID: "source",
            sourceIdentity: "note.md",
            title: "Note",
            status: .ready,
            rawByteHash: "raw",
            normalizedTextHash: "text",
            metadata: ["imported_note_payload": try encoder.encode(payload).base64EncodedString()]
        ))
        let chat = AppChatSessionRepository(store: fixture.graphStore)
        let service = HeadlessNoteSessionService(repository: chat) { session in
            NativeSessionManager(backend: ResumeTestBackend(), sessionRepository: chat, session: session)
        }
        let coordinator = NoteImportCoordinator(ledger: fixture.repository, sessionService: service)
        let model = NoteImportViewModel(
            ledger: fixture.repository,
            coordinator: coordinator,
            monitoringInterval: .milliseconds(10)
        )
        await model.reloadJobs()

        #expect(model.activitySummary.presentationState == .paused)
        #expect(!model.isMonitoringJobs)
        await model.resumeSelectedJob()

        #expect(model.selectedJob?.pauseRequestedAt == nil)
        await waitUntil { model.jobs.first?.status.isTerminal == true }
        #expect(model.selectedJob?.status == .completed)
        #expect(try fixture.repository.item(id: "item")?.status == .completed)
        #expect(try chat.loadRecentSessions(limit: 10).count == 1)
        await waitUntil { !model.isMonitoringJobs }
    }

    @Test("Cancelled jobs with a persisted request timestamp do not keep polling")
    func cancelledJobsDoNotPoll() async throws {
        let fixture = try ImportLedgerFixture()
        try fixture.repository.saveSource(NoteImportSourceRecord(id: "source", kind: .markdownFolder, displayName: "Notes"))
        var cancelled = NoteImportJobRecord(
            id: "cancelled",
            sourceID: "source",
            status: .cancelled,
            discoveredCount: 392,
            importedCount: 253,
            failedCount: 2
        )
        cancelled.cancelRequestedAt = Date()
        try fixture.repository.saveJob(cancelled)

        let model = NoteImportViewModel(ledger: fixture.repository, monitoringInterval: .milliseconds(10))
        await model.reloadJobs()

        #expect(model.selectedJob?.status == .cancelled)
        #expect(!model.isMonitoringJobs)
    }

    @Test("Static paused jobs are loaded without high frequency monitoring")
    func pausedJobsDoNotPoll() async throws {
        let fixture = try ImportLedgerFixture()
        try fixture.repository.saveSource(NoteImportSourceRecord(id: "source", kind: .markdownFolder, displayName: "Notes"))
        try fixture.repository.saveJob(NoteImportJobRecord(
            id: "paused",
            sourceID: "source",
            status: .paused,
            discoveredCount: 4,
            importedCount: 2
        ))
        let model = NoteImportViewModel(ledger: fixture.repository, monitoringInterval: .milliseconds(10))
        await model.reloadJobs()
        #expect(model.activitySummary.presentationState == .paused)
        #expect(!model.isMonitoringJobs)
    }

    @Test("Repeated imports of the same path reuse one authorized source")
    func reusesStableSource() async throws {
        let fixture = try ImportLedgerFixture()
        let notes = fixture.directory.appendingPathComponent("notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        try Data("# Note\nBody".utf8).write(to: notes.appendingPathComponent("note.md"))
        let chat = AppChatSessionRepository(store: fixture.graphStore)
        let service = HeadlessNoteSessionService(repository: chat) { session in
            NativeSessionManager(backend: ResumeTestBackend(), sessionRepository: chat, session: session)
        }
        let access = NoteImportSourceAccessService(codec: TestBookmarkCodec())
        let coordinator = NoteImportCoordinator(ledger: fixture.repository, sessionService: service, sourceAccessService: access)
        let model = NoteImportViewModel(
            ledger: fixture.repository,
            coordinator: coordinator,
            sourceAccessService: access,
            monitoringInterval: .milliseconds(10)
        )
        model.sourceKind = .markdownFolder
        model.sourceURL = notes
        model.notes = [.init(sourceKind: .markdownFolder, sourceIdentity: "note.md", title: "Note", markdownContent: "Body", rawByteHash: "raw", normalizedTextHash: "text")]
        model.options.llmMode = .disabled

        #expect(await model.startImport())
        await waitUntil { model.jobs.first?.status.isTerminal == true }
        model.notes = [.init(sourceKind: .markdownFolder, sourceIdentity: "note.md", title: "Note", markdownContent: "Body", rawByteHash: "raw", normalizedTextHash: "text")]
        #expect(await model.startImport())
        await waitUntil { model.jobs.first?.status.isTerminal == true }

        #expect(try fixture.repository.sources().count == 1)
        #expect(try fixture.repository.jobs().count == 2)
        #expect(try fixture.repository.jobs().allSatisfy { !$0.options.preserveHierarchy })
    }

    private func waitUntil(
        timeout: Duration = .seconds(30),
        condition: @escaping @MainActor () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition(), clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(condition())
    }
}

private struct ResumeTestBackend: AgentBackend {
    func chat(_ request: AgentChatRequest) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

private struct TestBookmarkCodec: NoteImportBookmarkCoding {
    func createBookmark(for url: URL) throws -> Data { Data(url.standardizedFileURL.path.utf8) }
    func resolveBookmark(_ data: Data) throws -> (url: URL, isStale: Bool) {
        guard let path = String(data: data, encoding: .utf8) else {
            throw NoteImportSourceAccessError.bookmarkResolutionFailed("invalid test bookmark")
        }
        return (URL(fileURLWithPath: path), false)
    }
}

private final class ImportLedgerFixture {
    let directory: URL
    let graphStore: SQLiteGraphKernelStore
    let repository: AppNoteImportRepository

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("graph.sqlite").path
        graphStore = try SQLiteGraphKernelStore(path: path)
        try graphStore.migrate()
        repository = try AppNoteImportRepository(databasePath: path)
    }

    deinit { try? FileManager.default.removeItem(at: directory) }
}
