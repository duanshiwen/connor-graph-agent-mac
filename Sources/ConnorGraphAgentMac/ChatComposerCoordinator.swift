import AppKit
import Foundation
import Observation
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore

@MainActor
@Observable
final class ChatComposerCoordinator {
    let model: ChatComposerModel
    private let storagePaths: AppStoragePaths?
    private let speech = SessionSpeechTranscriptionCoordinator(transcriber: SessionSpeechTranscriptionController())
    private var draftsBySessionID: [String: String] = [:]
    private var liveDraftSessionID: String?
    private var liveDraft = ""
    private var pendingAttachmentsBySessionID: [String: [AgentMessageAttachmentRef]] = [:]
    private var toastTask: Task<Void, Never>?
    private var importTasks: [UUID: Task<Void, Never>] = [:]
    private var extractionTasksBySessionID: [String: Task<Void, Never>] = [:]
    private var generation = 0
    private var isShutdown = false
    private var isRestoring = false

    @ObservationIgnored var selectedSessionID: () -> String? = { nil }
    @ObservationIgnored var autoSaveDraftsEnabled: () -> Bool = { true }
    @ObservationIgnored var speechEnabled: () -> Bool = { false }
    @ObservationIgnored var selectedModelID: () -> String = { "" }
    @ObservationIgnored var skillDisplayName: (String) -> String = { $0 }
    @ObservationIgnored var onBackgroundTask: (AppSessionBackgroundTask) -> Void = { _ in }

    init(model: ChatComposerModel, storagePaths: AppStoragePaths?) {
        self.model = model
        self.storagePaths = storagePaths
    }

    var canSubmit: Bool {
        !model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.pendingAttachmentRefs.isEmpty
    }

    var isSpeechRunningForSelectedSession: Bool { speech.isRunning(sessionID: selectedSessionID()) }

    func updateSelectedDraft(_ draft: String) {
        guard !isShutdown, !isRestoring, let sessionID = selectedSessionID() else { return }
        updateLiveDraft(draft, sessionID: sessionID)
        if autoSaveDraftsEnabled() { draftsBySessionID[sessionID] = draft }
        speech.noteUserEditedDraft(sessionID: sessionID, draft: draft)
    }

    func currentSelectedDraft() -> String {
        guard let sessionID = selectedSessionID() else { return model.input }
        if liveDraftSessionID == sessionID { return liveDraft }
        return autoSaveDraftsEnabled() ? (draftsBySessionID[sessionID] ?? model.input) : model.input
    }

    func appendToSelectedDraft(_ addition: String) {
        let updated = [currentSelectedDraft(), addition]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
        updateSelectedDraft(updated)
        model.applyInput(updated)
    }

    func restore(sessionID: String?) {
        guard !isShutdown else { return }
        let draft: String
        if let sessionID, liveDraftSessionID == sessionID { draft = liveDraft }
        else if let sessionID, autoSaveDraftsEnabled() { draft = draftsBySessionID[sessionID] ?? "" }
        else { draft = "" }
        setPublishedDraft(draft, sessionID: sessionID)
        model.pendingAttachmentRefs = sessionID.flatMap { pendingAttachmentsBySessionID[$0] } ?? []
    }

    func consumeForSubmission(sessionID: String) {
        draftsBySessionID[sessionID] = ""
        pendingAttachmentsBySessionID[sessionID] = []
        if selectedSessionID() == sessionID {
            setPublishedDraft("", sessionID: sessionID)
            model.pendingAttachmentRefs = []
        }
    }

    func removeSession(_ sessionID: String) {
        extractionTasksBySessionID.removeValue(forKey: sessionID)?.cancel()
        draftsBySessionID.removeValue(forKey: sessionID)
        pendingAttachmentsBySessionID.removeValue(forKey: sessionID)
        if liveDraftSessionID == sessionID { liveDraftSessionID = nil; liveDraft = "" }
    }

    func currentModelSupportsImages() -> Bool {
        let modelID = selectedModelID().lowercased()
        if modelID.contains("gpt-4") || modelID.contains("gpt-4o") || modelID.contains("o1") || modelID.contains("o3") { return true }
        if modelID.contains("claude-3") || modelID.contains("claude-4") || modelID.contains("claude-sonnet") || modelID.contains("claude-opus") || modelID.contains("claude-haiku") { return true }
        if modelID.contains("gemini-1.5") || modelID.contains("gemini-2") || modelID.contains("gemini-2.5") { return true }
        return false
    }

    func setActiveSkill(slug: String) {
        model.activeSkillSlug = slug
        model.activeSkillDisplayName = skillDisplayName(slug)
    }

    func clearActiveSkill() {
        model.activeSkillSlug = nil
        model.activeSkillDisplayName = nil
    }

    func removePendingAttachment(id: String) {
        model.pendingAttachmentRefs.removeAll { $0.id == id }
        if let sessionID = selectedSessionID() { pendingAttachmentsBySessionID[sessionID] = model.pendingAttachmentRefs }
    }

    func preview(_ attachment: AgentMessageAttachmentRef) {
        guard let sessionID = selectedSessionID(), let storagePaths else { return }
        model.attachmentPreviewModel = AttachmentPreviewLoader(store: AppSessionAttachmentStore(paths: storagePaths))
            .load(sessionID: sessionID, attachment: attachment)
    }

    func localFileURL(_ attachment: AgentMessageAttachmentRef) -> URL? {
        guard let sessionID = selectedSessionID(), let storagePaths else { return nil }
        return AttachmentPreviewLoader(store: AppSessionAttachmentStore(paths: storagePaths))
            .load(sessionID: sessionID, attachment: attachment).sourceFileURL
    }

    func enqueueAttachmentImport(urls: [URL]) {
        guard !isShutdown else { return }
        let id = UUID()
        importTasks[id] = Task { [weak self] in
            guard let self else { return }
            _ = await self.importAttachments(urls: urls)
            self.importTasks.removeValue(forKey: id)
        }
    }

    @discardableResult
    func importAttachments(urls: [URL]) async -> AttachmentImportBatchResult {
        guard !isShutdown, let sessionID = selectedSessionID(), let storagePaths else { return AttachmentImportBatchResult() }
        let store = AppSessionAttachmentStore(paths: storagePaths)
        var imported: [AgentMessageAttachmentRef] = []
        var rejected: [AttachmentRejectedFile] = []
        for url in urls {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do { imported.append(try store.importFile(at: url, sessionID: sessionID).messageRef) }
            catch let error as AppSessionAttachmentImportError {
                if case .rejected(let filename, let reason) = error { rejected.append(AttachmentRejectedFile(filename: filename, reason: reason)) }
            } catch {
                rejected.append(AttachmentRejectedFile(filename: url.lastPathComponent, reason: .unsupportedUnknownExtension(url.pathExtension.isEmpty ? "unknown" : url.pathExtension.lowercased())))
            }
        }
        guard !isShutdown else { return AttachmentImportBatchResult(accepted: imported, rejected: rejected) }
        if !imported.isEmpty {
            model.pendingAttachmentRefs.append(contentsOf: imported)
            pendingAttachmentsBySessionID[sessionID] = model.pendingAttachmentRefs
            runExtractionJobs(sessionID: sessionID)
        }
        let result = AttachmentImportBatchResult(accepted: imported, rejected: rejected)
        if !rejected.isEmpty { showImportToast(result) }
        return result
    }

    func retryExtraction(attachmentID: String) {
        guard let sessionID = selectedSessionID(), let storagePaths else { return }
        do {
            let manifest = try AppSessionAttachmentStore(paths: storagePaths).loadManifest(sessionID: sessionID, attachmentID: attachmentID)
            _ = try AttachmentExtractionJobStore(paths: storagePaths).appendStatus(
                AgentAttachmentExtractionJob(sessionID: sessionID, attachmentID: attachmentID, requestedCapabilities: AppSessionAttachmentStore.requestedCapabilities(for: manifest.kind)),
                status: .queued
            )
            showToast(title: "已重新排队解析", message: manifest.displayName, systemImage: "arrow.clockwise")
            runExtractionJobs(sessionID: sessionID)
        } catch {
            showToast(title: "重新解析失败", message: String(describing: error), systemImage: "xmark.circle")
        }
    }

    func showToast(title: String, message: String, systemImage: String = "exclamationmark.triangle") {
        guard !isShutdown else { return }
        let toast = AgentChatToast(title: title, message: message, systemImage: systemImage)
        model.attachmentToast = toast
        toastTask?.cancel()
        let currentGeneration = generation
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(4_500))
            guard let self, self.generation == currentGeneration, self.model.attachmentToast?.id == toast.id else { return }
            self.model.attachmentToast = nil
            self.toastTask = nil
        }
    }

    func toggleSpeech(speechInsertionRange: NSRange? = nil) {
        if isSpeechRunningForSelectedSession { finishSpeech() }
        else { beginSpeech(speechInsertionRange: speechInsertionRange) }
    }

    func beginSpeech(speechInsertionRange: NSRange? = nil) {
        guard speechEnabled() else { return }
        publishBackgroundTask(speech.beginHoldToTalk(
            selectedSessionID: selectedSessionID(),
            currentDraft: currentSelectedDraft(),
            speechInsertionRange: speechInsertionRange,
            setDraft: { [weak self] sessionID, draft in self?.setSpeechDraft(draft, sessionID: sessionID) },
            setProvisionalTranscript: { [weak self] sessionID, transcript in self?.setProvisionalTranscript(transcript, sessionID: sessionID) }
        ))
        syncSpeechState()
    }

    func finishSpeech() { publishBackgroundTask(speech.finishHoldToTalk()); syncSpeechState() }

    @discardableResult
    func stopSpeechForLeavingSession(_ sessionID: String?) -> AppSessionBackgroundTask? {
        let task = speech.stopIfRunningForLeavingSession(sessionID)
        if selectedSessionID() == sessionID { model.speechProvisionalTranscript = nil }
        syncSpeechState(); publishBackgroundTask(task); return task
    }

    @discardableResult
    func stopSpeechForDeletedSession(_ sessionID: String?) -> AppSessionBackgroundTask? {
        let task = speech.stopIfRunningForDeletedSession(sessionID)
        if selectedSessionID() == sessionID { model.speechProvisionalTranscript = nil }
        syncSpeechState(); publishBackgroundTask(task); return task
    }

    func stopSpeechForDisabledSetting() {
        guard model.speechTranscriptionStatus.isRunning else { return }
        let task = speech.stop(reason: .appLifecycle)
        model.speechProvisionalTranscript = nil
        syncSpeechState(); publishBackgroundTask(task)
    }

    private func updateLiveDraft(_ draft: String, sessionID: String) { liveDraftSessionID = sessionID; liveDraft = draft }
    private func setPublishedDraft(_ draft: String, sessionID: String?) {
        if let sessionID { updateLiveDraft(draft, sessionID: sessionID) }
        else { liveDraftSessionID = nil; liveDraft = draft }
        isRestoring = true; model.input = draft; isRestoring = false
    }
    private func setSpeechDraft(_ draft: String, sessionID: String) {
        draftsBySessionID[sessionID] = draft
        if selectedSessionID() == sessionID { setPublishedDraft(draft, sessionID: sessionID) }
    }
    private func setProvisionalTranscript(_ transcript: String?, sessionID: String) {
        guard selectedSessionID() == sessionID else { return }
        model.speechProvisionalTranscript = transcript?.isEmpty == true ? nil : transcript
    }
    private func syncSpeechState() { model.speechTranscriptionStatus = speech.status }
    private func publishBackgroundTask(_ task: AppSessionBackgroundTask?) { if let task { onBackgroundTask(task) } }

    private func runExtractionJobs(sessionID: String) {
        guard extractionTasksBySessionID[sessionID] == nil, let storagePaths, !isShutdown else { return }
        let currentGeneration = generation
        extractionTasksBySessionID[sessionID] = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == currentGeneration { self.extractionTasksBySessionID.removeValue(forKey: sessionID) } }
            do {
                let queue = AttachmentExtractionQueue(jobStore: AttachmentExtractionJobStore(paths: storagePaths), processor: AttachmentExtractionJobProcessor(paths: storagePaths))
                try await queue.drain(sessionID: sessionID)
                try Task.checkCancellation()
                guard self.generation == currentGeneration else { return }
                self.refreshPendingAttachments(sessionID: sessionID)
            } catch is CancellationError { return }
            catch { self.showToast(title: "附件解析失败", message: String(describing: error), systemImage: "exclamationmark.triangle") }
        }
    }

    private func refreshPendingAttachments(sessionID: String) {
        guard let storagePaths else { return }
        let store = AppSessionAttachmentStore(paths: storagePaths)
        let refs = (pendingAttachmentsBySessionID[sessionID] ?? []).map { (try? store.loadManifest(sessionID: sessionID, attachmentID: $0.id).messageRef) ?? $0 }
        pendingAttachmentsBySessionID[sessionID] = refs
        if selectedSessionID() == sessionID {
            model.pendingAttachmentRefs = refs
            if let preview = model.attachmentPreviewModel, refs.contains(where: { $0.id == preview.attachment.id }) {
                model.attachmentPreviewModel = AttachmentPreviewLoader(store: store).load(sessionID: sessionID, attachment: preview.attachment)
            }
        }
    }

    private func showImportToast(_ result: AttachmentImportBatchResult) {
        let supported = "Connor 当前支持添加文本、Markdown、日志、JSON/JSONL、CSV/TSV、XML/YAML、代码文件、常见图片（PNG/JPEG/GIF/WebP/HEIC/BMP/ICO/TIFF），以及 PDF、Word、Excel、PowerPoint 和 Apple iWork（Pages/Numbers/Keynote）文档附件。暂不支持 HTML、音频、视频、压缩包、SVG/AVIF、数据库、可执行文件或未知格式。"
        let lines = result.rejected.prefix(8).map { "- \($0.filename)：\($0.reason.userMessage)" }.joined(separator: "\n")
        let remaining = result.rejected.count > 8 ? "\n…另有 \(result.rejected.count - 8) 个文件未添加" : ""
        let message = result.accepted.isEmpty ? "\(supported)\n\n未添加：\n\(lines)\(remaining)" : "已添加 \(result.accepted.count) 个附件，\(result.rejected.count) 个文件未添加。\n\n\(supported)\n\n未添加：\n\(lines)\(remaining)"
        showToast(title: result.accepted.isEmpty ? "附件未添加" : "部分附件未添加", message: message, systemImage: result.accepted.isEmpty ? "xmark.circle" : "exclamationmark.triangle")
    }

    func shutdown() {
        guard !isShutdown else { return }
        isShutdown = true; generation += 1
        toastTask?.cancel(); toastTask = nil
        for task in importTasks.values { task.cancel() }
        importTasks.removeAll()
        for task in extractionTasksBySessionID.values { task.cancel() }
        extractionTasksBySessionID.removeAll()
        let backgroundTask = speech.stop(reason: .appLifecycle)
        publishBackgroundTask(backgroundTask)
        model.speechProvisionalTranscript = nil
        syncSpeechState()
    }
}

extension ChatComposerCoordinator: ChatComposerCommanding {
    var canSubmitCurrentChat: Bool { canSubmit }
    var isSpeechTranscriptionRunningForSelectedSession: Bool { isSpeechRunningForSelectedSession }
    func updateSelectedChatInputDraft(_ draft: String) { updateSelectedDraft(draft) }
    func appendToSelectedChatInputDraft(_ addition: String) { appendToSelectedDraft(addition) }
    func showAttachmentToast(title: String, message: String, systemImage: String) { showToast(title: title, message: message, systemImage: systemImage) }
    func previewAttachment(_ attachment: AgentMessageAttachmentRef) { preview(attachment) }
    func localAttachmentFileURL(_ attachment: AgentMessageAttachmentRef) -> URL? { localFileURL(attachment) }
    func retryAttachmentExtraction(attachmentID: String) { retryExtraction(attachmentID: attachmentID) }
    func toggleSpeechTranscriptionForSelectedSession() { toggleSpeech() }
    func beginSpeechTranscriptionForSelectedSession(speechInsertionRange: NSRange?) { beginSpeech(speechInsertionRange: speechInsertionRange) }
    func finishSpeechTranscriptionForSelectedSession() { finishSpeech() }
}
