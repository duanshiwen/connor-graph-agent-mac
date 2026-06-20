import Foundation
import ConnorGraphCore
import ConnorGraphAgent
import ConnorGraphAppSupport

struct AgentComposerState {
    var input: String
    var pendingAttachments: [AgentMessageAttachmentRef]
    var activeSkillSlug: String?
    var activeSkillDisplayName: String?
    var canSubmit: Bool
    var isSubmitting: Bool
    var selectedModel: String
    var sessionHasLLMOverride: Bool
    var permissionMode: AgentPermissionMode
    var selectedSessionStatus: AgentSessionStatus?
    var isSpeechTranscriptionRunning: Bool
    var speechTranscriptionStatus: SessionSpeechTranscriptionStatus
    var speechProvisionalTranscript: String?

    init(
        input: String,
        pendingAttachments: [AgentMessageAttachmentRef],
        activeSkillSlug: String?,
        activeSkillDisplayName: String?,
        canSubmit: Bool,
        isSubmitting: Bool,
        selectedModel: String,
        sessionHasLLMOverride: Bool,
        permissionMode: AgentPermissionMode,
        selectedSessionStatus: AgentSessionStatus?,
        isSpeechTranscriptionRunning: Bool,
        speechTranscriptionStatus: SessionSpeechTranscriptionStatus,
        speechProvisionalTranscript: String?
    ) {
        self.input = input
        self.pendingAttachments = pendingAttachments
        self.activeSkillSlug = activeSkillSlug
        self.activeSkillDisplayName = activeSkillDisplayName
        self.canSubmit = canSubmit
        self.isSubmitting = isSubmitting
        self.selectedModel = selectedModel
        self.sessionHasLLMOverride = sessionHasLLMOverride
        self.permissionMode = permissionMode
        self.selectedSessionStatus = selectedSessionStatus
        self.isSpeechTranscriptionRunning = isSpeechTranscriptionRunning
        self.speechTranscriptionStatus = speechTranscriptionStatus
        self.speechProvisionalTranscript = speechProvisionalTranscript
    }
}
