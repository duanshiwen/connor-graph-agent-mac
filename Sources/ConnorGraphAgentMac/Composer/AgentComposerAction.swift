import Foundation
import ConnorGraphCore
import ConnorGraphAgent

enum AgentComposerAction {
    case inputChanged(String)
    case submit
    case cancelActiveRun
    case importFiles([URL])
    case showAttachmentImportError(String)
    case removeAttachment(String)
    case previewAttachment(AgentMessageAttachmentRef)
    case selectSkill(String)
    case clearSkill
    case setPermissionMode(AgentPermissionMode)
    case setSessionStatus(AgentSessionStatus)
    case setRemoteKnowledgeBaseIDs([String]?)
    case toggleBrowserWorkspaceVisibility
    case toggleSpeechTranscription
    case beginSpeechTranscription(NSRange?)
    case finishSpeechTranscription
    case showBackgroundTasks
}
