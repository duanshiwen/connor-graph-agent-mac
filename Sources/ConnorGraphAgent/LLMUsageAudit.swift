import Foundation

public enum AgentLLMRequestKind: String, Codable, Sendable, Equatable, CaseIterable {
    case conversationTurn = "conversation_turn"
    case conversationProgressUpdate = "conversation_progress_update"
    case conversationIntentNormalization = "conversation_intent_normalization"
    case conversationRollingSummary = "conversation_rolling_summary"
    case sessionSummary = "session_summary"
    case sessionTitleGeneration = "session_title_generation"
    case memoryL1Extraction = "memory_l1_extraction"
    case memoryBackgroundProcessing = "memory_background_processing"
    case backgroundAgentToolLoop = "background_agent_tool_loop"
    case cloudKnowledgeGeneration = "cloud_knowledge_generation"
    case personalityGeneration = "personality_generation"
    case personalityUpdate = "personality_update"
    case providerHealthCheck = "provider_health_check"
    case providerCapabilityProbe = "provider_capability_probe"
    case generatedMedia = "generated_media"
    case unclassified
}

public struct AgentLLMRequestAuditContext: Codable, Sendable, Equatable {
    public var requestKind: AgentLLMRequestKind
    public var sessionID: String?
    public var runID: String?
    public var backgroundJobID: String?
    public var correlationID: String?
    public var iteration: Int?
    public var operation: String?
    public var initiator: AgentLLMRequestInitiator
    public var metadata: [String: String]

    public init(
        requestKind: AgentLLMRequestKind = .unclassified,
        sessionID: String? = nil,
        runID: String? = nil,
        backgroundJobID: String? = nil,
        correlationID: String? = nil,
        iteration: Int? = nil,
        operation: String? = nil,
        initiator: AgentLLMRequestInitiator = .system,
        metadata: [String: String] = [:]
    ) {
        self.requestKind = requestKind
        self.sessionID = sessionID
        self.runID = runID
        self.backgroundJobID = backgroundJobID
        self.correlationID = correlationID
        self.iteration = iteration
        self.operation = operation
        self.initiator = initiator
        self.metadata = metadata
    }
}

public enum AgentLLMRequestInitiator: String, Codable, Sendable, Equatable, CaseIterable {
    case foreground
    case background
    case system
}

public enum LLMUsageAuditStatus: String, Codable, Sendable, Equatable, CaseIterable {
    case succeeded
    case failed
    case cancelled
}

public enum LLMUsageAuditExecutionMode: String, Codable, Sendable, Equatable {
    case completion
    case streaming
    case generatedMedia = "generated_media"
}

public struct LLMUsageAuditRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var requestKind: AgentLLMRequestKind
    public var startedAt: Date
    public var completedAt: Date
    public var durationMilliseconds: Int
    public var status: LLMUsageAuditStatus
    public var executionMode: LLMUsageAuditExecutionMode
    public var modelID: String
    public var providerID: String?
    public var providerMode: String?
    public var connectionID: String?
    public var sessionID: String?
    public var runID: String?
    public var backgroundJobID: String?
    public var correlationID: String?
    public var iteration: Int?
    public var operation: String?
    public var initiator: AgentLLMRequestInitiator
    public var relatedToolNames: [String]
    public var promptTokens: Int?
    public var completionTokens: Int?
    public var totalTokens: Int?
    public var cacheCreationInputTokens: Int?
    public var cacheReadInputTokens: Int?
    public var uncachedInputTokens: Int?
    public var estimatedInputTokens: Int
    public var messageCount: Int
    public var inputCharacterCount: Int
    public var toolDefinitionCount: Int
    public var containsImages: Bool
    public var outputCharacterCount: Int?
    public var toolCallCount: Int?
    public var finishReason: String?
    public var generatedByteCount: Int64?
    public var errorType: String?
    public var errorMessage: String?
    public var metadata: [String: String]

    public init(
        id: String, requestKind: AgentLLMRequestKind, startedAt: Date, completedAt: Date,
        durationMilliseconds: Int, status: LLMUsageAuditStatus, executionMode: LLMUsageAuditExecutionMode,
        modelID: String, providerID: String?, providerMode: String?, connectionID: String?,
        sessionID: String?, runID: String?, backgroundJobID: String?, correlationID: String?, iteration: Int?,
        operation: String?, initiator: AgentLLMRequestInitiator, relatedToolNames: [String],
        promptTokens: Int?, completionTokens: Int?, totalTokens: Int?, cacheCreationInputTokens: Int?, cacheReadInputTokens: Int?, uncachedInputTokens: Int? = nil,
        estimatedInputTokens: Int, messageCount: Int, inputCharacterCount: Int, toolDefinitionCount: Int, containsImages: Bool,
        outputCharacterCount: Int?, toolCallCount: Int?, finishReason: String?, generatedByteCount: Int64?,
        errorType: String?, errorMessage: String?, metadata: [String: String]
    ) {
        self.id = id
        self.requestKind = requestKind
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.durationMilliseconds = durationMilliseconds
        self.status = status
        self.executionMode = executionMode
        self.modelID = modelID
        self.providerID = providerID
        self.providerMode = providerMode
        self.connectionID = connectionID
        self.sessionID = sessionID
        self.runID = runID
        self.backgroundJobID = backgroundJobID
        self.correlationID = correlationID
        self.iteration = iteration
        self.operation = operation
        self.initiator = initiator
        self.relatedToolNames = relatedToolNames
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
        self.uncachedInputTokens = uncachedInputTokens
        self.estimatedInputTokens = estimatedInputTokens
        self.messageCount = messageCount
        self.inputCharacterCount = inputCharacterCount
        self.toolDefinitionCount = toolDefinitionCount
        self.containsImages = containsImages
        self.outputCharacterCount = outputCharacterCount
        self.toolCallCount = toolCallCount
        self.finishReason = finishReason
        self.generatedByteCount = generatedByteCount
        self.errorType = errorType
        self.errorMessage = errorMessage
        self.metadata = metadata
    }
}

public protocol LLMUsageAuditRecording: Sendable {
    func record(_ record: LLMUsageAuditRecord)
}
