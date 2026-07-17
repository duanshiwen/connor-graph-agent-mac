import Foundation
import ConnorGraphCore
import ConnorGraphAgent

@MainActor
struct AgentComposerStore {
    let model: ChatFeatureModel
    let actions: ChatFeatureActions

    func state(input: String, canSubmit: Bool, selectedSession: AgentSession?) -> AgentComposerState {
        let isNoteBeforeFirstMessage: Bool = {
            guard let session = selectedSession,
                  session.governance.kind == .note,
                  session.messages.isEmpty,
                  !model.run.isSubmitting
            else { return false }
            return true
        }()
        return AgentComposerState(
            input: input,
            pendingAttachments: model.composer.pendingAttachmentRefs,
            activeSkillSlug: model.composer.activeSkillSlug,
            activeSkillDisplayName: model.composer.activeSkillDisplayName,
            canSubmit: canSubmit && !actions.session.isLoadingSelectedChatSessionDetail,
            isSubmitting: model.run.isSubmitting,
            displayMode: isNoteBeforeFirstMessage ? .note : .normal,
            selectedModel: actions.dependencies.aiConnections.selectedModel,
            sessionHasLLMOverride: actions.dependencies.sessionHasLLMOverride(),
            remoteKnowledgeBaseIDs: model.composer.remoteKnowledgeBaseIDs,
            permissionMode: actions.dependencies.permissionMode(),
            selectedSessionStatus: selectedSession?.governance.status,
            isSpeechTranscriptionEnabled: actions.dependencies.inputSettings.sessionSpeechTranscriptionEnabled,
            isSpeechTranscriptionRunning: actions.composer.isSpeechTranscriptionRunningForSelectedSession,
            speechTranscriptionStatus: model.composer.speechTranscriptionStatus,
            speechProvisionalTranscript: model.composer.speechProvisionalTranscript
        )
    }

    func send(_ action: AgentComposerAction) {
        switch action {
        case .inputChanged(let value):
            actions.composer.updateSelectedChatInputDraft(value)
        case .submit:
            break
        case .cancelActiveRun:
            actions.run.cancelActiveChatRun()
        case .importFiles(let urls):
            actions.composer.enqueueAttachmentImport(urls: urls)
        case .showAttachmentImportError(let message):
            actions.composer.showAttachmentToast(title: "粘贴图片失败", message: message, systemImage: "xmark.circle")
        case .removeAttachment(let id):
            actions.composer.removePendingAttachment(id: id)
        case .previewAttachment(let attachment):
            actions.composer.previewAttachment(attachment)
        case .selectSkill(let slug):
            actions.composer.setActiveSkill(slug: slug)
        case .clearSkill:
            actions.composer.clearActiveSkill()
        case .setPermissionMode(let mode):
            actions.run.setAgentPermissionMode(mode)
        case .setSessionStatus(let status):
            DispatchQueue.main.async { actions.session.setSelectedSessionStatus(status) }
        case .setRemoteKnowledgeBaseIDs(let ids):
            actions.run.setSessionRemoteKnowledgeBaseIDs(ids)
        case .toggleBrowserWorkspaceVisibility:
            actions.dependencies.browser.toggleWorkspaceVisibility()
        case .toggleSpeechTranscription:
            actions.composer.toggleSpeechTranscriptionForSelectedSession()
        case .beginSpeechTranscription(let range):
            actions.composer.beginSpeechTranscriptionForSelectedSession(speechInsertionRange: range)
        case .finishSpeechTranscription:
            actions.composer.finishSpeechTranscriptionForSelectedSession()
        case .showBackgroundTasks:
            model.sessions.isBackgroundTasksPresented = true
        }
    }
}
