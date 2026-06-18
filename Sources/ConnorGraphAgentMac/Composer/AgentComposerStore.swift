import Foundation
import ConnorGraphCore
import ConnorGraphAgent

@MainActor
struct AgentComposerStore {
    unowned var viewModel: AppViewModel

    func state(input: String, canSubmit: Bool, selectedSession: AgentSession?) -> AgentComposerState {
        AgentComposerState(
            input: input,
            pendingAttachments: viewModel.pendingAttachmentRefs,
            activeSkillSlug: viewModel.activeSkillSlug,
            activeSkillDisplayName: viewModel.activeSkillDisplayName,
            canSubmit: canSubmit,
            isSubmitting: viewModel.isSubmittingChat,
            selectedModel: viewModel.llmSelectedModel,
            sessionHasLLMOverride: viewModel.sessionHasLLMOverride,
            permissionMode: viewModel.sidecarPermissionMode,
            selectedSessionStatus: selectedSession?.governance.status
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
            viewModel.setSidecarPermissionMode(mode)
        case .setSessionStatus(let status):
            viewModel.deferViewUpdate {
                viewModel.setSelectedSessionStatus(status)
            }
        case .toggleBrowserWorkspaceVisibility:
            viewModel.toggleBrowserWorkspaceVisibility()
        case .showBackgroundTasks:
            viewModel.isBackgroundTasksPresented = true
        }
    }
}
