import Foundation
import Observation
import ConnorGraphCore
import ConnorGraphAppSupport

@MainActor
@Observable
final class SkillRuntimeFeatureModel {
    enum Event {
        case operationSucceeded
        case operationFailed(String)
    }

    typealias AddRequestHandler = @MainActor (String) async throws -> String
    typealias EditRequestHandler = @MainActor (SkillManagerCard, String) async throws -> Void

    var definitions: [SkillRuntimeDefinition] = []
    var presentation: SkillManagerPresentation = SkillRuntimeFeatureModel.emptyPresentation()
    var selectedCardID: String?
    var isAddDialogPresented = false
    var addRequestDraft = ""
    var isSubmittingAddRequest = false
    var addDialogMessage: String?
    var isEditDialogPresented = false
    var editRequestDraft = ""
    var editingCard: SkillManagerCard?
    var isSubmittingEditRequest = false
    var editDialogMessage: String?
    var pendingDeletionCard: SkillManagerCard?
    var importCandidates: [ExternalSkillImportCandidate] = []
    var selectedImportCandidateIDs: Set<String> = []
    var importWarnings: [String] = []
    var importDialogMessage: String?
    var isImporting = false
    var importSearchText = ""
    var importSourceFilter: ExternalSkillLibrarySource?
    var customImportRoots: [ExternalSkillLibraryRoot] = []

    @ObservationIgnored private let repository: AppSkillRuntimeRepository?
    @ObservationIgnored private let storagePaths: AppStoragePaths?
    @ObservationIgnored private let externalSkillImporter: ExternalSkillLibraryImporter
    @ObservationIgnored var onAddRequest: AddRequestHandler?
    @ObservationIgnored var onEditRequest: EditRequestHandler?
    @ObservationIgnored var onEvent: ((Event) -> Void)?

    init(
        repository: AppSkillRuntimeRepository?,
        storagePaths: AppStoragePaths?,
        externalSkillImporter: ExternalSkillLibraryImporter = ExternalSkillLibraryImporter()
    ) {
        self.repository = repository
        self.storagePaths = storagePaths
        self.externalSkillImporter = externalSkillImporter
        if storagePaths == nil {
            presentation = Self.emptyPresentation(warnings: ["Storage paths are not initialized."])
        }
    }

    func applyStartupSnapshot(_ result: StartupDomainResult<SkillRuntimeContentSnapshot>) {
        guard let snapshot = result.value else {
            if let failureMessage = result.failureMessage { onEvent?(.operationFailed(failureMessage)) }
            return
        }
        definitions = snapshot.definitions
        presentation = snapshot.presentation
        if let selectedCardID,
           !presentation.cards.contains(where: { $0.id == selectedCardID }) {
            self.selectedCardID = nil
        }
    }

    func reload() {
        do {
            definitions = try repository?.list() ?? []
            presentation = buildPresentation()
            if let selectedCardID,
               !presentation.cards.contains(where: { $0.id == selectedCardID }) {
                self.selectedCardID = nil
            }
            onEvent?(.operationSucceeded)
        } catch {
            onEvent?(.operationFailed(String(describing: error)))
        }
    }

    func reloadIfNeeded(after eventPresentation: AgentEventPresentation) {
        guard eventPresentation.kind == AgentEventKind.toolFinished.rawValue else { return }
        let skillMutationToolNames: Set<String> = [
            "connor_skill_create",
            "connor_skill_update",
            "connor_skill_delete"
        ]
        guard skillMutationToolNames.contains(where: { eventPresentation.title.contains($0) }) else { return }
        reload()
    }

    func selectCard(_ id: String) {
        selectedCardID = id
    }

    func presentAddDialog() {
        addRequestDraft = ""
        addDialogMessage = nil
        isSubmittingAddRequest = false
        isAddDialogPresented = true
    }

    func cancelAddDialog() {
        guard !isSubmittingAddRequest else { return }
        isAddDialogPresented = false
        addRequestDraft = ""
        addDialogMessage = nil
    }

    func submitAddRequest() async {
        let request = addRequestDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, !isSubmittingAddRequest else { return }
        guard let onAddRequest else {
            addDialogMessage = "会话系统尚未初始化。"
            return
        }
        isSubmittingAddRequest = true
        addDialogMessage = "康纳正在根据你的需求创建技能…"
        do {
            let createdSlug = try await onAddRequest(request)
            addRequestDraft = ""
            addDialogMessage = "技能已创建：\(createdSlug)。"
            reload()
            selectedCardID = createdSlug
            onEvent?(.operationSucceeded)
        } catch {
            addDialogMessage = "创建失败：\(String(describing: error))"
            onEvent?(.operationFailed(String(describing: error)))
        }
        isSubmittingAddRequest = false
    }

    func presentEditDialog(card: SkillManagerCard) {
        editingCard = card
        editRequestDraft = ""
        editDialogMessage = nil
        isSubmittingEditRequest = false
        isEditDialogPresented = true
    }

    func cancelEditDialog() {
        guard !isSubmittingEditRequest else { return }
        isEditDialogPresented = false
        editRequestDraft = ""
        editDialogMessage = nil
        editingCard = nil
    }

    func submitEditRequest() async {
        guard let card = editingCard else { return }
        let request = editRequestDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, !isSubmittingEditRequest else { return }
        guard let onEditRequest else {
            editDialogMessage = "会话系统尚未初始化。"
            return
        }
        isSubmittingEditRequest = true
        editDialogMessage = "康纳正在根据你的需求修改技能…"
        do {
            try await onEditRequest(card, request)
            editRequestDraft = ""
            editDialogMessage = "修改请求已提交。完成后技能列表会自动刷新。"
            reload()
            selectedCardID = card.id
            onEvent?(.operationSucceeded)
        } catch {
            editDialogMessage = "修改失败：\(String(describing: error))"
            onEvent?(.operationFailed(String(describing: error)))
        }
        isSubmittingEditRequest = false
    }

    func requestDelete(card: SkillManagerCard) {
        pendingDeletionCard = card
    }

    func cancelDelete() {
        pendingDeletionCard = nil
    }

    func prepareSkillImport() {
        importDialogMessage = nil
        isImporting = false
        refreshImportCandidates()
    }

    func resetSkillImport() {
        guard !isImporting else { return }
        selectedImportCandidateIDs = []
        importDialogMessage = nil
        importSearchText = ""
        importSourceFilter = nil
    }

    func setImportCandidateSelected(_ id: String, isSelected: Bool) {
        guard importCandidates.contains(where: { $0.id == id && !$0.isAlreadyImported }) else { return }
        if isSelected {
            selectedImportCandidateIDs.insert(id)
        } else {
            selectedImportCandidateIDs.remove(id)
        }
    }

    func selectAllVisibleImportCandidates() {
        selectedImportCandidateIDs.formUnion(filteredImportCandidates.lazy.filter { !$0.isAlreadyImported }.map(\.id))
    }

    func deselectAllImportCandidates() {
        selectedImportCandidateIDs = []
    }

    func addCustomImportRoot(_ directoryURL: URL) {
        let normalized = directoryURL.standardizedFileURL
        guard !customImportRoots.contains(where: { $0.directoryURL.standardizedFileURL == normalized }) else { return }
        customImportRoots.append(ExternalSkillLibraryRoot(source: .custom, directoryURL: normalized))
        refreshImportCandidates()
    }

    var filteredImportCandidates: [ExternalSkillImportCandidate] {
        let query = importSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return importCandidates.filter { candidate in
            let matchesSource = importSourceFilter == nil || candidate.source == importSourceFilter
            let matchesQuery = query.isEmpty
                || candidate.name.localizedCaseInsensitiveContains(query)
                || candidate.description.localizedCaseInsensitiveContains(query)
                || candidate.slug.localizedCaseInsensitiveContains(query)
            return matchesSource && matchesQuery
        }
    }

    var discoveredImportSources: [ExternalSkillLibrarySource] {
        Array(Set(importCandidates.map(\.source))).sorted { $0.title < $1.title }
    }

    func submitSkillImport() async {
        guard let storagePaths, !isImporting else { return }
        let selected = importCandidates.filter { selectedImportCandidateIDs.contains($0.id) && !$0.isAlreadyImported }
        guard !selected.isEmpty else { return }
        isImporting = true
        importDialogMessage = "正在导入 \(selected.count) 个技能…"
        do {
            let importer = externalSkillImporter
            let destination = storagePaths.skillsDirectory
            let result = try await Task.detached {
                try importer.importSkills(selected, destinationDirectory: destination)
            }.value
            reload()
            refreshImportCandidates()
            let skipped = result.skippedIDs.count
            importDialogMessage = skipped == 0
                ? "已导入 \(result.importedIDs.count) 个技能。"
                : "已导入 \(result.importedIDs.count) 个技能，跳过 \(skipped) 个同名技能。"
        } catch {
            importDialogMessage = "导入失败：\(error.localizedDescription)"
            onEvent?(.operationFailed(error.localizedDescription))
        }
        isImporting = false
    }

    func confirmDelete() {
        guard let card = pendingDeletionCard else { return }
        do {
            try delete(card: card)
            pendingDeletionCard = nil
            reload()
            if selectedCardID == card.id {
                selectedCardID = nil
            }
            onEvent?(.operationSucceeded)
        } catch {
            onEvent?(.operationFailed(String(describing: error)))
        }
    }

    private func delete(card: SkillManagerCard) throws {
        guard card.sourceTier == SkillSourceTier.user.rawValue else {
            throw AppSkillRuntimeRepositoryError.unsafePermissionMode("Only user skills can be deleted from the skill manager. Skill \(card.id) is \(card.sourceTier).")
        }
        let packagePath = card.packagePath.isEmpty
            ? URL(fileURLWithPath: card.path).deletingLastPathComponent().path
            : card.packagePath
        guard let storagePaths else {
            throw SkillRuntimeFeatureModelError.storagePathsUnavailable
        }
        let packageURL = URL(fileURLWithPath: packagePath, isDirectory: true).standardizedFileURL
        let rootURL = storagePaths.skillsDirectory.standardizedFileURL
        guard packageURL.path == rootURL.appendingPathComponent(card.id, isDirectory: true).standardizedFileURL.path else {
            throw AppSkillRuntimeRepositoryError.unsafePermissionMode("Refusing to delete skill outside user skill directory: \(packageURL.path)")
        }
        try FileManager.default.removeItem(at: packageURL)
    }

    private func buildPresentation() -> SkillManagerPresentation {
        guard let storagePaths else {
            return Self.emptyPresentation(warnings: ["Storage paths are not initialized."])
        }
        let snapshot = SkillPackageScanner().scan(storagePaths: storagePaths)
        return SkillCommercialUIPresentationBuilder().build(snapshot: snapshot)
    }

    private func refreshImportCandidates() {
        guard let storagePaths else {
            importCandidates = []
            selectedImportCandidateIDs = []
            importWarnings = ["Storage paths are not initialized."]
            return
        }
        let discovery = externalSkillImporter.discover(
            destinationDirectory: storagePaths.skillsDirectory,
            additionalRoots: customImportRoots
        )
        importCandidates = discovery.candidates
        importWarnings = discovery.warnings
        selectedImportCandidateIDs = Set(discovery.candidates.lazy.filter { !$0.isAlreadyImported }.map(\.id))
    }

    private static func emptyPresentation(warnings: [String] = []) -> SkillManagerPresentation {
        SkillManagerPresentation(
            summary: SkillManagerSummary(total: 0, enabled: 0, projectScoped: 0, risky: 0, invalid: 0, sourceBlocked: 0),
            cards: [],
            globalWarnings: warnings
        )
    }
}

enum SkillRuntimeFeatureModelError: Error, CustomStringConvertible {
    case storagePathsUnavailable

    var description: String {
        switch self {
        case .storagePathsUnavailable:
            "Native chat runtime is unavailable. Configure storage/runtime before sending messages."
        }
    }
}
