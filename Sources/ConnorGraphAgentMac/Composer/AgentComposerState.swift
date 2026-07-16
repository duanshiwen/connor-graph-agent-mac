import Foundation
import ConnorGraphCore
import ConnorGraphAgent
import ConnorGraphAppSupport

enum ComposerDisplayMode: Equatable {
    case normal
    case note
}

struct AgentComposerState {
    var input: String
    var pendingAttachments: [AgentMessageAttachmentRef]
    var activeSkillSlug: String?
    var activeSkillDisplayName: String?
    var canSubmit: Bool
    var isSubmitting: Bool
    var displayMode: ComposerDisplayMode
    var selectedModel: String
    var sessionHasLLMOverride: Bool
    var remoteKnowledgeBaseIDs: [String]?
    var permissionMode: AgentPermissionMode
    var selectedSessionStatus: AgentSessionStatus?
    var isSpeechTranscriptionEnabled: Bool
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
        displayMode: ComposerDisplayMode = .normal,
        selectedModel: String,
        sessionHasLLMOverride: Bool,
        remoteKnowledgeBaseIDs: [String]? = nil,
        permissionMode: AgentPermissionMode,
        selectedSessionStatus: AgentSessionStatus?,
        isSpeechTranscriptionEnabled: Bool,
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
        self.displayMode = displayMode
        self.selectedModel = selectedModel
        self.sessionHasLLMOverride = sessionHasLLMOverride
        self.remoteKnowledgeBaseIDs = remoteKnowledgeBaseIDs
        self.permissionMode = permissionMode
        self.selectedSessionStatus = selectedSessionStatus
        self.isSpeechTranscriptionEnabled = isSpeechTranscriptionEnabled
        self.isSpeechTranscriptionRunning = isSpeechTranscriptionRunning
        self.speechTranscriptionStatus = speechTranscriptionStatus
        self.speechProvisionalTranscript = speechProvisionalTranscript
    }
}

struct RemoteKnowledgeBaseSelection: Equatable {
    var available: [CloudMarketplaceKnowledgeBase]
    var explicitIDs: [String]?

    var selectedIDs: Set<String> {
        let availableIDs = Set(available.map(\.id))
        guard let explicitIDs else { return availableIDs }
        return Set(explicitIDs).intersection(availableIDs)
    }

    var isAllSelected: Bool {
        !available.isEmpty && selectedIDs.count == available.count
    }

    var toggleAllValue: [String]? {
        isAllSelected ? [] : nil
    }

    var label: String {
        guard !available.isEmpty else { return "知识库：无订阅" }
        if isAllSelected { return "知识库：全部" }
        if selectedIDs.isEmpty { return "知识库：未选择" }
        return "知识库：\(selectedIDs.count)/\(available.count)"
    }

    func toggling(_ id: String) -> [String] {
        var next = selectedIDs
        if next.contains(id) { next.remove(id) } else { next.insert(id) }
        return next.sorted()
    }
}
