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
    @Published var selectedJobID: String?
    @Published var selectedJobItems: [NoteImportItemRecord] = []
    @Published var activity: Activity = .idle
    @Published var error: String?
    @Published var searchText = ""

    let ledger: AppNoteImportRepository?
    let coordinator: NoteImportCoordinator?
    let runtime: NoteImportRuntime?
    let sourceAccessService: NoteImportSourceAccessService
    private let onImportedSessionsChanged: @MainActor () -> Void
    private var runtimeObservationTask: Task<Void, Never>?
    private var observedImportedCount = 0

    init(
        ledger: AppNoteImportRepository? = nil,
        coordinator: NoteImportCoordinator? = nil,
        runtime: NoteImportRuntime? = nil,
        sourceAccessService: NoteImportSourceAccessService = .init(),
        configurationError: String? = nil,
        onImportedSessionsChanged: @escaping @MainActor () -> Void = {}
    ) {
        self.ledger = ledger
        self.coordinator = coordinator
        self.runtime = runtime
        self.sourceAccessService = sourceAccessService
        self.onImportedSessionsChanged = onImportedSessionsChanged
        self.error = configurationError
        reloadJobs()
        observedImportedCount = jobs.reduce(0) { $0 + $1.importedCount }
        observeRuntime()
    }

    deinit { runtimeObservationTask?.cancel() }

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
        guard let ledger, let coordinator, let sourceURL, !notes.isEmpty else {
            error = "没有可导入的笔记。"
            return false
        }
        activity = .starting
        error = nil
        do {
            var source = NoteImportSourceRecord(kind: sourceKind, displayName: sourceURL.deletingPathExtension().lastPathComponent)
            source = try sourceAccessService.authorize(url: sourceURL, source: source)
            try ledger.saveSource(source)
            let job = NoteImportJobRecord(sourceID: source.id, options: options)
            try ledger.saveJob(job)
            reloadJobs(selecting: job.id)
            activity = .importing(job.id)
            let adapter = adapterForCurrentSource()
            let request = NoteImportScanRequest(sourceID: source.id, sourceURL: sourceURL, kind: sourceKind, options: options)
            _ = try await coordinator.scan(jobID: job.id, adapter: adapter, request: request)
            reloadJobs(selecting: job.id)
            if let runtime {
                _ = await runtime.submit(jobID: job.id)
            } else {
                _ = try await coordinator.execute(jobID: job.id)
                activity = .idle
                reloadJobs(selecting: job.id)
            }
            return true
        } catch {
            self.error = userFacing(error)
            activity = .idle
            reloadJobs()
            return false
        }
    }

    func reloadJobs(selecting jobID: String? = nil) {
        guard let ledger else { return }
        do {
            let latestJobs = try ledger.jobs()
            let importedCount = latestJobs.reduce(0) { $0 + $1.importedCount }
            jobs = latestJobs
            if importedCount > observedImportedCount { onImportedSessionsChanged() }
            observedImportedCount = importedCount
            if let jobID { selectedJobID = jobID }
            else if selectedJobID == nil { selectedJobID = jobs.first?.id }
            reloadSelectedJobItems()
        } catch { self.error = userFacing(error) }
    }

    func selectJob(_ id: String?) {
        selectedJobID = id
        reloadSelectedJobItems()
    }

    func reloadSelectedJobItems() {
        guard let ledger, let selectedJobID else { selectedJobItems = []; return }
        do { selectedJobItems = try ledger.items(jobID: selectedJobID) }
        catch { self.error = userFacing(error) }
    }

    func pauseSelectedJob() async {
        guard let id = selectedJobID else { return }
        do {
            if let runtime { try await runtime.pause(jobID: id) }
            else if let coordinator { try await coordinator.pause(jobID: id) }
            reloadJobs(selecting: id)
        } catch { self.error = userFacing(error) }
    }

    func resumeSelectedJob() async {
        guard let id = selectedJobID else { return }
        do {
            if let runtime { try await runtime.resume(jobID: id) }
            else if let coordinator { try await coordinator.resume(jobID: id) }
            reloadJobs(selecting: id)
        } catch { self.error = userFacing(error) }
    }

    func cancelSelectedJob() async {
        guard let id = selectedJobID else { return }
        do {
            if let runtime { try await runtime.cancel(jobID: id) }
            else if let coordinator { try await coordinator.cancel(jobID: id) }
            reloadJobs(selecting: id)
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

    private func observeRuntime() {
        guard let runtime else { return }
        runtimeObservationTask = Task { [weak self] in
            let events = await runtime.events()
            do { try await runtime.recover() }
            catch { await MainActor.run { self?.error = self?.userFacing(error) } }
            for await event in events {
                guard !Task.isCancelled else { return }
                switch event {
                case .ledgerChanged(let jobID):
                    await MainActor.run {
                        self?.reloadJobs(selecting: jobID ?? self?.selectedJobID)
                        if let jobID, self?.jobs.first(where: { $0.id == jobID })?.status.isTerminal == true {
                            self?.activity = .idle
                        }
                    }
                case .noteSessionCreated:
                    break
                case .jobFailed(let jobID, let message):
                    await MainActor.run {
                        self?.error = message
                        self?.activity = .idle
                        self?.reloadJobs(selecting: jobID)
                    }
                }
            }
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

