import Foundation
import Testing
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
        let model = NoteImportViewModel(ledger: fixture.repository, monitoringInterval: .milliseconds(10))

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

    @Test("Static paused jobs are loaded without high frequency monitoring")
    func pausedJobsDoNotPoll() throws {
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
        #expect(model.activitySummary.presentationState == .paused)
        #expect(!model.isMonitoringJobs)
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

private final class ImportLedgerFixture {
    let directory: URL
    let repository: AppNoteImportRepository

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("graph.sqlite").path
        let graphStore = try SQLiteGraphKernelStore(path: path)
        try graphStore.migrate()
        repository = try AppNoteImportRepository(databasePath: path)
    }

    deinit { try? FileManager.default.removeItem(at: directory) }
}
