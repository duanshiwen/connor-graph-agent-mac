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
    private let draftPersistence: ChatComposerDraftPersistence?
    private let speech = SessionSpeechTranscriptionCoordinator(transcriber: SessionSpeechTranscriptionController())
    private var draftsBySessionID: [String: String] = [:]
    private var activeSkillSlugBySessionID: [String: String] = [:]
    private var activeSkillDisplayNameBySessionID: [String: String] = [:]
    private var liveDraftSessionID: String?
    private var liveDraft = ""
    private var pendingAttachmentsBySessionID: [String: [AgentMessageAttachmentRef]] = [:]
    private var pendingAttachmentRejectionsBySessionID: [String: [String: AttachmentImportRejectionReason]] = [:]
    private var toastTask: Task<Void, Never>?
    private var importTasks: [UUID: Task<Void, Never>] = [:]
    private var extractionTasksBySessionID: [String: Task<Void, Never>] = [:]
    private var generation = 0
    private var isShutdown = false
    private var isRestoring = false
    private var restoredPublishedDraftSessionID: String?

    @ObservationIgnored var selectedSessionID: () -> String? = { nil }
    @ObservationIgnored var autoSaveDraftsEnabled: () -> Bool = { true }
    @ObservationIgnored var speechEnabled: () -> Bool = { false }
    @ObservationIgnored var selectedModelID: () -> String = { "" }
    @ObservationIgnored var skillDisplayName: (String) -> String = { $0 }
    @ObservationIgnored var onBackgroundTask: (AppSessionBackgroundTask) -> Void = { _ in }

    init(model: ChatComposerModel, storagePaths: AppStoragePaths?, draftSaveDelay: TimeInterval = 0.3) {
        self.model = model
        self.storagePaths = storagePaths
        self.draftPersistence = storagePaths.map {
            ChatComposerDraftPersistence(
                repository: ChatComposerDraftRepository(storagePaths: $0),
                saveDelay: draftSaveDelay
            )
        }
    }

    var canSubmit: Bool {
        !model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.pendingActiveAttachmentRefs.isEmpty
    }

    var isSpeechRunningForSelectedSession: Bool { speech.isRunning(sessionID: selectedSessionID()) }

    func updateSelectedDraft(_ draft: String) {
        guard !isShutdown, !isRestoring, let sessionID = selectedSessionID() else { return }
        updateLiveDraft(draft, sessionID: sessionID)
        if autoSaveDraftsEnabled() {
            draftsBySessionID[sessionID] = draft
            draftPersistence?.scheduleSave(draft, sessionID: sessionID)
        }
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
        guard restoredPublishedDraftSessionID != sessionID else { return }
        let draft: String
        if let sessionID, liveDraftSessionID == sessionID { draft = liveDraft }
        else if let sessionID, autoSaveDraftsEnabled() {
            let restored = draftsBySessionID[sessionID] ?? draftPersistence?.load(sessionID: sessionID) ?? ""
            draftsBySessionID[sessionID] = restored
            draft = restored
        }
        else { draft = "" }
        setPublishedDraft(draft, sessionID: sessionID)
        model.pendingAttachmentRefs = sessionID.flatMap { pendingAttachmentsBySessionID[$0] } ?? []
        model.pendingAttachmentRejections = sessionID.flatMap { pendingAttachmentRejectionsBySessionID[$0] } ?? [:]
        model.attachmentRejectionAlert = nil
        // 技能与草稿/附件一样按会话隔离：切换会话时恢复该会话自己选中的技能，
        // 避免上一个会话的技能“跟随”到新会话，也避免回到原会话后技能丢失。
        model.activeSkillSlug = sessionID.flatMap { activeSkillSlugBySessionID[$0] }
        model.activeSkillDisplayName = sessionID.flatMap { activeSkillDisplayNameBySessionID[$0] }
    }

    func consumeForSubmission(sessionID: String) {
        draftsBySessionID[sessionID] = ""
        draftPersistence?.remove(sessionID: sessionID)
        pendingAttachmentsBySessionID[sessionID] = []
        pendingAttachmentRejectionsBySessionID[sessionID] = [:]
        if selectedSessionID() == sessionID {
            setPublishedDraft("", sessionID: sessionID)
            model.pendingAttachmentRefs = []
            model.pendingAttachmentRejections = [:]
            model.attachmentRejectionAlert = nil
        }
    }

    func removeSession(_ sessionID: String) {
        extractionTasksBySessionID.removeValue(forKey: sessionID)?.cancel()
        draftsBySessionID.removeValue(forKey: sessionID)
        draftPersistence?.remove(sessionID: sessionID)
        pendingAttachmentsBySessionID.removeValue(forKey: sessionID)
        pendingAttachmentRejectionsBySessionID.removeValue(forKey: sessionID)
        activeSkillSlugBySessionID.removeValue(forKey: sessionID)
        activeSkillDisplayNameBySessionID.removeValue(forKey: sessionID)
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
        let displayName = skillDisplayName(slug)
        model.activeSkillSlug = slug
        model.activeSkillDisplayName = displayName
        if let sessionID = selectedSessionID() {
            activeSkillSlugBySessionID[sessionID] = slug
            activeSkillDisplayNameBySessionID[sessionID] = displayName
        }
    }

    func clearActiveSkill() {
        model.activeSkillSlug = nil
        model.activeSkillDisplayName = nil
        if let sessionID = selectedSessionID() {
            activeSkillSlugBySessionID.removeValue(forKey: sessionID)
            activeSkillDisplayNameBySessionID.removeValue(forKey: sessionID)
        }
    }

    /// 提交失败后把消息回填到“发送消息的那个会话”的输入框（而不是当前选中会话），
    /// 避免用户在失败期间切到其他会话导致回填进错误会话、上下文错乱。
    func restoreDraftForFailedSubmission(sessionID: String, text: String) {
        guard !isShutdown else { return }
        if autoSaveDraftsEnabled() {
            draftsBySessionID[sessionID] = text
            draftPersistence?.scheduleSave(text, sessionID: sessionID)
        }
        if selectedSessionID() == sessionID {
            setPublishedDraft(text, sessionID: sessionID)
        }
    }

    func removePendingAttachment(id: String) {
        model.pendingAttachmentRefs.removeAll { $0.id == id }
        if let sessionID = selectedSessionID() {
            pendingAttachmentsBySessionID[sessionID] = model.pendingAttachmentRefs
            pendingAttachmentRejectionsBySessionID[sessionID]?.removeValue(forKey: id)
            model.pendingAttachmentRejections = pendingAttachmentRejectionsBySessionID[sessionID] ?? [:]
        }
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
        var usedCharacters = pendingAttachmentCharacterTotal(sessionID: sessionID, store: store)
        let totalCharacterLimit = Int(AttachmentImportPolicy.defaultTotalAcceptedCharacters)
        for url in urls {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let manifest = try store.importFile(at: url, sessionID: sessionID)
                let ref = manifest.messageRef
                if let characters = AgentAttachmentContextPlanBuilder.extractedContentCharacterCount(
                    store: store,
                    sessionID: sessionID,
                    attachmentID: manifest.id
                ) {
                    guard usedCharacters + characters <= totalCharacterLimit else {
                        rejected.append(AttachmentRejectedFile(
                            filename: url.lastPathComponent,
                            reason: .totalAttachmentBudgetExceeded(Int64(totalCharacterLimit))
                        ))
                        continue
                    }
                    usedCharacters += characters
                }
                imported.append(ref)
            } catch let error as AppSessionAttachmentImportError {
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
            // 会话里加入的附件（选文件/附件库/拖拽/粘贴/笔记图片）一律登记进附件库，
            // 保证“最近附件”与 LLM 会话、笔记里的图片/文件都纳入。
            AttachmentLibraryRegistration.register(urls: urls, paths: storagePaths)
        }
        let result = AttachmentImportBatchResult(accepted: imported, rejected: rejected)
        if !rejected.isEmpty { presentAttachmentRejectionAlert(rejected) }
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

    func awaitAttachmentExtraction(sessionID: String) async {
        runExtractionJobs(sessionID: sessionID)
        await extractionTasksBySessionID[sessionID]?.value
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
        restoredPublishedDraftSessionID = sessionID
        isRestoring = true; model.input = draft; isRestoring = false
    }
    private func setSpeechDraft(_ draft: String, sessionID: String) {
        if autoSaveDraftsEnabled() {
            draftsBySessionID[sessionID] = draft
            draftPersistence?.scheduleSave(draft, sessionID: sessionID)
        }
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
                let rejections = self.rejectOversizePendingAttachments(sessionID: sessionID)
                self.refreshPendingAttachments(sessionID: sessionID)
                if !rejections.isEmpty {
                    self.presentAttachmentRejectionAlert(rejections)
                }
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

    /// 已提取附件的内容字符数之和（尚未提取的文档先按 0 计，提取完成后会再次校验）。
    private func pendingAttachmentCharacterTotal(sessionID: String, store: AppSessionAttachmentStore) -> Int {
        (pendingAttachmentsBySessionID[sessionID] ?? []).reduce(into: 0) { total, ref in
            if let characters = AgentAttachmentContextPlanBuilder.extractedContentCharacterCount(
                store: store,
                sessionID: sessionID,
                attachmentID: ref.id
            ) {
                total += characters
            }
        }
    }

    /// 提取完成后校验：无法完整解析或推高总量上限的附件在附件条上标记“未生效”，
    /// 保留在列表中供用户查看/移除，绝不静默取消；返回本次新增的拒绝项用于弹窗确认。
    @discardableResult
    private func rejectOversizePendingAttachments(sessionID: String) -> [AttachmentRejectedFile] {
        guard let storagePaths else { return [] }
        let store = AppSessionAttachmentStore(paths: storagePaths)
        let totalCharacterLimit = Int(AttachmentImportPolicy.defaultTotalAcceptedCharacters)
        let pending = pendingAttachmentsBySessionID[sessionID] ?? []
        var rejectionsByID = pendingAttachmentRejectionsBySessionID[sessionID] ?? [:]
        var newlyRejected: [AttachmentRejectedFile] = []

        // 1) 无法完整解析的附件（内容过大被跳过 / 解析失败）标记未生效。
        for ref in pending where rejectionsByID[ref.id] == nil {
            let reason: AttachmentImportRejectionReason?
            switch ref.extractionStatus {
            case .skippedOversize:
                reason = .contentTooLargeForExtraction
            case .failed:
                reason = .extractionFailed
            default:
                reason = nil
            }
            if let reason {
                rejectionsByID[ref.id] = reason
                newlyRejected.append(AttachmentRejectedFile(id: ref.id, filename: ref.displayName, reason: reason))
            }
        }

        // 2) 总量超限：按添加顺序保留先加入的附件，标记后续放不下的；被标记的附件不再占用预算。
        var usedCharacters = 0
        for ref in pending {
            if rejectionsByID[ref.id] != nil { continue }
            let characters = AgentAttachmentContextPlanBuilder.extractedContentCharacterCount(
                store: store,
                sessionID: sessionID,
                attachmentID: ref.id
            ) ?? 0
            if usedCharacters + characters > totalCharacterLimit {
                rejectionsByID[ref.id] = .totalAttachmentBudgetExceeded(Int64(totalCharacterLimit))
                newlyRejected.append(AttachmentRejectedFile(
                    id: ref.id,
                    filename: ref.displayName,
                    reason: .totalAttachmentBudgetExceeded(Int64(totalCharacterLimit))
                ))
            } else {
                usedCharacters += characters
            }
        }
        pendingAttachmentRejectionsBySessionID[sessionID] = rejectionsByID
        syncPendingAttachmentRejections(sessionID: sessionID)
        return newlyRejected
    }

    /// 未生效附件确认弹窗：要求用户明确知道附件不会被发送，避免误以为是程序问题。
    func dismissAttachmentRejectionAlert(removeRejected: Bool) {
        let alert = model.attachmentRejectionAlert
        if removeRejected, let sessionID = selectedSessionID(), let alert {
            let rejectedIDs = Set(alert.rejected.map(\.id))
            model.pendingAttachmentRefs.removeAll { rejectedIDs.contains($0.id) }
            pendingAttachmentsBySessionID[sessionID] = model.pendingAttachmentRefs
            for id in rejectedIDs {
                pendingAttachmentRejectionsBySessionID[sessionID]?.removeValue(forKey: id)
            }
            model.pendingAttachmentRejections = pendingAttachmentRejectionsBySessionID[sessionID] ?? [:]
        }
        model.attachmentRejectionAlert = nil
    }

    private func presentAttachmentRejectionAlert(_ rejected: [AttachmentRejectedFile]) {
        guard !isShutdown, !rejected.isEmpty else { return }
        let lines = rejected.prefix(8)
            .map { "- \($0.filename)：\($0.reason.userMessage)" }
            .joined(separator: "\n")
        let remaining = rejected.count > 8 ? "\n…还有 \(rejected.count - 8) 个附件未发送" : ""
        model.attachmentRejectionAlert = AgentAttachmentRejectionAlert(
            title: "部分附件不会发送",
            message: "以下附件不会随消息发送给助手：\n\(lines)\(remaining)\n\n它们会保留在附件栏并标记“未发送”，你可以移除，或先移除部分附件后再重新添加。",
            rejected: rejected
        )
    }

    private func syncPendingAttachmentRejections(sessionID: String) {
        guard selectedSessionID() == sessionID else { return }
        model.pendingAttachmentRejections = pendingAttachmentRejectionsBySessionID[sessionID] ?? [:]
    }

    func shutdown() {
        guard !isShutdown else { return }
        draftPersistence?.flush(draftsBySessionID)
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
