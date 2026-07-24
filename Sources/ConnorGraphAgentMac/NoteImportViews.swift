import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ConnorGraphCore
import ConnorGraphAppSupport

@MainActor
final class NoteImportViewModel: ObservableObject {
    enum Step: Int, CaseIterable { case source, review, options, confirm }
    enum Activity: Equatable { case idle, scanning, starting, importing(String) }

    @Published var step: Step = .source
    @Published var sourceKind: NoteImportSourceKind = .markdownFolder
    @Published var sourceURL: URL?
    @Published var options = NoteImportOptions()
    @Published var notes: [ImportedNote] = []
    @Published var jobs: [NoteImportJobRecord] = []
    @Published private(set) var sourceNamesByID: [String: String] = [:]
    @Published var selectedJobID: String?
    @Published var selectedJobItems: [NoteImportItemRecord] = []
    @Published var activity: Activity = .idle
    @Published var runtimeSnapshot = NoteImportRuntimeSnapshot()
    @Published var error: String?
    @Published var searchText = ""
    @Published private(set) var isLoadingMoreJobs = false
    @Published private(set) var isLoadingMoreSelectedJobItems = false

    let ledger: AppNoteImportRepository?
    let coordinator: NoteImportCoordinator?
    let executionSupervisor: NoteImportExecutionSupervisor?
    let sourceAccessService: NoteImportSourceAccessService
    private let activityReader: NoteImportActivityReader?
    private let monitoringInterval: Duration
    private var monitoringTask: Task<Void, Never>?
    private var nextJobsCursor: String?
    private var nextSelectedJobItemsCursor: String?
    private static let pageSize = 50

    init(
        ledger: AppNoteImportRepository? = nil,
        coordinator: NoteImportCoordinator? = nil,
        executionSupervisor: NoteImportExecutionSupervisor? = nil,
        sourceAccessService: NoteImportSourceAccessService = .init(),
        configurationError: String? = nil,
        monitoringInterval: Duration = .milliseconds(750)
    ) {
        self.ledger = ledger
        self.coordinator = coordinator
        self.executionSupervisor = executionSupervisor ?? coordinator.map(NoteImportExecutionSupervisor.init(coordinator:))
        self.sourceAccessService = sourceAccessService
        self.activityReader = ledger.map(NoteImportActivityReader.init(ledger:))
        self.error = configurationError
        self.monitoringInterval = monitoringInterval
        Task { @MainActor [weak self] in await self?.reloadJobs() }
    }

    convenience init(configurationError: String) { self.init(configurationError: Optional(configurationError)) }

    var isBusy: Bool { activity != .idle }
    var encodingReview: [ImportedNote] {
        notes.filter { note in note.diagnostics.contains { $0.code == .decodingAmbiguous || $0.code == .decodingFailed } }
    }
    var attachmentCount: Int { notes.reduce(0) { $0 + $1.attachments.count } }
    var warningCount: Int { notes.reduce(0) { $0 + $1.diagnostics.filter { $0.severity != .info }.count } }
    var filteredNotes: [ImportedNote] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return notes }
        return notes.filter { $0.title.localizedCaseInsensitiveContains(query) || ($0.relativePath?.localizedCaseInsensitiveContains(query) == true) }
    }
    var selectedJob: NoteImportJobRecord? { jobs.first { $0.id == selectedJobID } }
    var activitySummary: NoteImportActivitySummary { NoteImportActivitySummary(jobs: jobs) }
    var isMonitoringJobs: Bool { monitoringTask != nil }

    func startJobMonitoring() {
        guard monitoringTask == nil, hasDynamicallyChangingJobs else { return }
        monitoringTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.monitoringTask = nil }
            while !Task.isCancelled {
                do { try await Task.sleep(for: self.monitoringInterval) }
                catch { return }
                guard !Task.isCancelled else { return }
                guard await self.reloadMonitoredJobs() else { return }
            }
        }
    }

    func stopJobMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    func chooseSource() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        switch sourceKind {
        case .markdownFolder, .obsidianVault, .notionExport:
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.prompt = "选择文件夹"
            panel.message = sourceKind == .notionExport ? "请选择已解压的 Notion 导出文件夹" : "请选择要导入的笔记文件夹"
        case .evernoteENEX:
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.allowedContentTypes = [UTType(filenameExtension: "enex") ?? .xml]
            panel.prompt = "选择 ENEX"
            panel.message = "请选择 Evernote 或印象笔记导出的 ENEX 文件"
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        sourceURL = url
        notes = []
        step = .source
        error = nil
    }

    func scanSource() async {
        guard let sourceURL else { return }
        activity = .scanning
        error = nil
        notes = []
        do {
            let adapter = adapterForCurrentSource()
            var discovered: [ImportedNote] = []
            let request = NoteImportScanRequest(sourceID: "preview", sourceURL: sourceURL, kind: sourceKind, options: options)
            for try await note in adapter.scan(request) {
                try Task.checkCancellation()
                discovered.append(note)
            }
            notes = discovered
            step = .review
        } catch is CancellationError {
            error = "扫描已取消。"
        } catch {
            self.error = userFacing(error)
        }
        activity = .idle
    }

    func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    func back() {
        guard !isBusy, let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    func startImport() async -> Bool {
        guard ledger != nil, let coordinator, let sourceURL, !notes.isEmpty else {
            error = "没有可导入的笔记。"
            return false
        }
        activity = .starting
        error = nil
        do {
            let job = try await coordinator.prepareImport(
                sourceURL: sourceURL,
                kind: sourceKind,
                options: options
            )
            await reloadJobs(selecting: job.id)
            startJobMonitoring()
            activity = .importing(job.id)
            let adapter = adapterForCurrentSource()
            let request = NoteImportScanRequest(sourceID: job.sourceID, sourceURL: sourceURL, kind: sourceKind, options: job.options)
            _ = try await coordinator.scan(jobID: job.id, adapter: adapter, request: request)
            await reloadJobs(selecting: job.id)
            await executionSupervisor?.ensureRunning(jobID: job.id)
            activity = .idle
            return true
        } catch {
            self.error = userFacing(error)
            activity = .idle
            await reloadJobs()
            return false
        }
    }

    private func reloadMonitoredJobs() async -> Bool {
        guard let activityReader else { return false }
        do {
            let monitoredJobID = selectedJobID
            let jobPage = try await activityReader.jobPage(pageSize: max(Self.pageSize, jobs.count))
            let itemPage: NoteImportItemPage? = if let monitoredJobID {
                try await activityReader.itemPage(
                    jobID: monitoredJobID,
                    pageSize: max(Self.pageSize, selectedJobItems.count)
                )
            } else { nil }
            if jobPage.jobs != jobs { jobs = jobPage.jobs }
            nextJobsCursor = jobPage.nextCursor
            if selectedJobID == monitoredJobID, let itemPage {
                if selectedJobItems != itemPage.items { selectedJobItems = itemPage.items }
                nextSelectedJobItemsCursor = itemPage.nextCursor
            }
            await refreshRuntimeSnapshot()
            return hasDynamicallyChangingJobs
        } catch {
            self.error = userFacing(error)
            return false
        }
    }

    func reloadJobs(selecting jobID: String? = nil, reloadSelectedItems: Bool = true) async {
        guard let activityReader else { return }
        do {
            let jobPage = try await activityReader.jobPage(pageSize: max(Self.pageSize, jobs.count))
            let jobSnapshot = jobPage.jobs
            let sourceSnapshot = try await activityReader.sourceNames()
            let preferredID = jobID ?? selectedJobID
            let targetID = preferredID.flatMap { preferred in
                jobSnapshot.contains(where: { $0.id == preferred }) ? preferred : nil
            } ?? jobSnapshot.first?.id
            let itemPage: NoteImportItemPage? = if reloadSelectedItems, let targetID {
                try await activityReader.itemPage(jobID: targetID, pageSize: Self.pageSize)
            } else { nil }
            if jobs != jobSnapshot { jobs = jobSnapshot }
            nextJobsCursor = jobPage.nextCursor
            if sourceNamesByID != sourceSnapshot { sourceNamesByID = sourceSnapshot }
            selectedJobID = targetID
            if let itemPage, selectedJobID == targetID {
                if selectedJobItems != itemPage.items { selectedJobItems = itemPage.items }
                nextSelectedJobItemsCursor = itemPage.nextCursor
            }
            if hasDynamicallyChangingJobs { startJobMonitoring() }
        } catch { self.error = userFacing(error) }
    }

    func selectJob(_ id: String?) async {
        if selectedJobID != id { selectedJobID = id }
        guard let id else {
            selectedJobItems = []
            nextSelectedJobItemsCursor = nil
            return
        }
        guard let activityReader else {
            selectedJobItems = []
            nextSelectedJobItemsCursor = nil
            return
        }
        do {
            let page = try await activityReader.itemPage(jobID: id, pageSize: Self.pageSize)
            try Task.checkCancellation()
            guard selectedJobID == id else { return }
            selectedJobItems = page.items
            nextSelectedJobItemsCursor = page.nextCursor
        } catch is CancellationError {
            return
        } catch {
            guard selectedJobID == id else { return }
            self.error = userFacing(error)
        }
    }

    func loadMoreJobsIfNeeded(currentJobID: String) async {
        guard currentJobID == jobs.last?.id,
              !isLoadingMoreJobs,
              let cursor = nextJobsCursor,
              let activityReader else { return }
        isLoadingMoreJobs = true
        defer { isLoadingMoreJobs = false }
        do {
            let page = try await activityReader.jobPage(cursor: cursor, pageSize: Self.pageSize)
            let existingIDs = Set(jobs.map(\.id))
            jobs.append(contentsOf: page.jobs.filter { !existingIDs.contains($0.id) })
            nextJobsCursor = page.nextCursor
        } catch { self.error = userFacing(error) }
    }

    func loadMoreSelectedJobItemsIfNeeded(currentItemID: String) async {
        guard currentItemID == selectedJobItems.last?.id,
              let jobID = selectedJobID,
              !isLoadingMoreSelectedJobItems,
              let cursor = nextSelectedJobItemsCursor,
              let activityReader else { return }
        isLoadingMoreSelectedJobItems = true
        defer { isLoadingMoreSelectedJobItems = false }
        do {
            let page = try await activityReader.itemPage(jobID: jobID, cursor: cursor, pageSize: Self.pageSize)
            guard selectedJobID == jobID else { return }
            let existingIDs = Set(selectedJobItems.map(\.id))
            selectedJobItems.append(contentsOf: page.items.filter { !existingIDs.contains($0.id) })
            nextSelectedJobItemsCursor = page.nextCursor
        } catch { self.error = userFacing(error) }
    }

    func recoverPersistedJobs() async {
        await executionSupervisor?.recoverPersistedJobs()
        await refreshRuntimeSnapshot()
        await reloadJobs(reloadSelectedItems: false)
        startJobMonitoring()
    }

    func restartSelectedJob() async {
        guard let executionSupervisor, let id = selectedJobID else { return }
        await executionSupervisor.ensureRunning(jobID: id)
        await refreshRuntimeSnapshot()
        await reloadJobs(selecting: id)
        startJobMonitoring()
    }

    func pauseSelectedJob() async {
        guard let executionSupervisor, let id = selectedJobID else { return }
        do {
            try await executionSupervisor.requestPause(jobID: id)
            await refreshRuntimeSnapshot()
            await reloadJobs(selecting: id)
        }
        catch { self.error = userFacing(error) }
    }

    func resumeSelectedJob() async {
        guard let executionSupervisor, let id = selectedJobID else { return }
        do {
            try await executionSupervisor.resume(jobID: id)
            await refreshRuntimeSnapshot()
            await reloadJobs(selecting: id)
            startJobMonitoring()
        } catch { self.error = userFacing(error) }
    }

    func cancelSelectedJob() async {
        guard let executionSupervisor, let id = selectedJobID else { return }
        do {
            try await executionSupervisor.requestCancel(jobID: id)
            await refreshRuntimeSnapshot()
            await reloadJobs(selecting: id)
        }
        catch { self.error = userFacing(error) }
    }

    func deleteJob(id: String) async {
        guard let executionSupervisor,
              jobs.first(where: { $0.id == id })?.status.isTerminal == true else { return }
        do {
            try await executionSupervisor.delete(jobID: id)
            if selectedJobID == id {
                selectedJobID = nil
                selectedJobItems = []
            }
            await reloadJobs()
        } catch { self.error = userFacing(error) }
    }

    func resetWizard() {
        step = .source
        sourceURL = nil
        notes = []
        options = NoteImportOptions()
        searchText = ""
        error = nil
        activity = .idle
    }

    private func refreshRuntimeSnapshot() async {
        runtimeSnapshot = await executionSupervisor?.snapshot() ?? .init()
    }

    private var hasDynamicallyChangingJobs: Bool {
        jobs.contains { job in
            !job.status.isTerminal
                && ([.created, .scanning, .awaitingReview, .ready, .importing, .processing, .cancelling].contains(job.status)
                    || job.cancelRequestedAt != nil)
        }
    }

    private func adapterForCurrentSource() -> any NoteImportSourceAdapter {
        switch sourceKind {
        case .markdownFolder: MarkdownFolderNoteImportAdapter()
        case .obsidianVault: ObsidianVaultNoteImportAdapter()
        case .notionExport: NotionExportNoteImportAdapter()
        case .evernoteENEX: ENEXNoteImportAdapter()
        }
    }

    private func userFacing(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription { return description }
        return String(describing: error)
    }
}
