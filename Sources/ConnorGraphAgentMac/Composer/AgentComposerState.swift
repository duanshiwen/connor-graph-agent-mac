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
    var allowedMCPToolNames: [String]?
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
        allowedMCPToolNames: [String]? = nil,
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
        self.allowedMCPToolNames = allowedMCPToolNames
        self.permissionMode = permissionMode
        self.selectedSessionStatus = selectedSessionStatus
        self.isSpeechTranscriptionEnabled = isSpeechTranscriptionEnabled
        self.isSpeechTranscriptionRunning = isSpeechTranscriptionRunning
        self.speechTranscriptionStatus = speechTranscriptionStatus
        self.speechProvisionalTranscript = speechProvisionalTranscript
    }
}

struct MCPToolSelection: Equatable {
    var availableToolNames: [String]
    var explicitToolNames: [String]?

    var selectedToolNames: Set<String> {
        let available = Set(availableToolNames)
        guard let explicitToolNames else { return available }
        return Set(explicitToolNames).intersection(available)
    }

    var isAutomatic: Bool { explicitToolNames == nil }

    var label: String {
        guard !availableToolNames.isEmpty else { return "MCP：无工具" }
        if isAutomatic { return "MCP：自动" }
        if selectedToolNames.isEmpty { return "MCP：关闭" }
        return "MCP：\(selectedToolNames.count)/\(availableToolNames.count)"
    }

    func toggling(_ toolName: String) -> [String] {
        var next = selectedToolNames
        if next.contains(toolName) { next.remove(toolName) } else { next.insert(toolName) }
        return next.sorted()
    }

    func togglingSource(toolNames: [String]) -> [String] {
        let sourceNames = Set(toolNames)
        var next = selectedToolNames
        if sourceNames.isSubset(of: next) {
            next.subtract(sourceNames)
        } else {
            next.formUnion(sourceNames)
        }
        return next.sorted()
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
