import Foundation
import ConnorGraphCore
import ConnorGraphAgent

@MainActor
struct AgentComposerStore {
    unowned var viewModel: AppViewModel

    func state(input: String, canSubmit: Bool, selectedSession: AgentSession?) -> AgentComposerState {
        let isNoteBeforeFirstMessage: Bool = {
            guard let session = selectedSession else { return false }
            guard session.governance.kind == .note else { return false }
            guard session.messages.isEmpty else { return false }
            guard !viewModel.isSubmittingChat else { return false }
            return true
        }()
        return AgentComposerState(
            input: input,
            pendingAttachments: viewModel.pendingAttachmentRefs,
            activeSkillSlug: viewModel.activeSkillSlug,
            activeSkillDisplayName: viewModel.activeSkillDisplayName,
            canSubmit: canSubmit && !viewModel.isLoadingSelectedChatSessionDetail,
            isSubmitting: viewModel.isSubmittingChat,
            displayMode: isNoteBeforeFirstMessage ? .note : .normal,
            selectedModel: viewModel.llmSelectedModel,
            sessionHasLLMOverride: viewModel.sessionHasLLMOverride,
            permissionMode: viewModel.agentPermissionMode,
            selectedSessionStatus: selectedSession?.governance.status,
            isSpeechTranscriptionEnabled: viewModel.sessionSpeechTranscriptionEnabled,
            isSpeechTranscriptionRunning: viewModel.isSpeechTranscriptionRunningForSelectedSession,
            speechTranscriptionStatus: viewModel.speechTranscriptionStatus,
            speechProvisionalTranscript: viewModel.speechProvisionalTranscript
        )
    }

    func send(_ action: AgentComposerAction) {
        switch action {
        case .inputChanged(let value):
            viewModel.updateSelectedChatInputDraft(value)
        case .submit:
            break
        case .cancelActiveRun:
            viewModel.cancelActiveChatRun()
        case .importFiles(let urls):
            Task { await viewModel.importAttachments(urls: urls) }
        case .showAttachmentImportError(let message):
            viewModel.showAttachmentToast(title: "粘贴图片失败", message: message, systemImage: "xmark.circle")
        case .removeAttachment(let id):
            viewModel.removePendingAttachment(id: id)
        case .previewAttachment(let attachment):
            viewModel.previewAttachment(attachment)
        case .selectSkill(let slug):
            viewModel.setActiveSkill(slug: slug)
        case .clearSkill:
            viewModel.clearActiveSkill()
        case .setPermissionMode(let mode):
            viewModel.setAgentPermissionMode(mode)
        case .setSessionStatus(let status):
            DispatchQueue.main.async {
                viewModel.setSelectedSessionStatus(status)
            }
        case .toggleBrowserWorkspaceVisibility:
            viewModel.toggleBrowserWorkspaceVisibility()
        case .toggleSpeechTranscription:
            viewModel.toggleSpeechTranscriptionForSelectedSession()
        case .beginSpeechTranscription(let speechInsertionRange):
            viewModel.beginSpeechTranscriptionForSelectedSession(speechInsertionRange: speechInsertionRange)
        case .finishSpeechTranscription:
            viewModel.finishSpeechTranscriptionForSelectedSession()
        case .showBackgroundTasks:
            viewModel.isBackgroundTasksPresented = true
        }
    }
}
