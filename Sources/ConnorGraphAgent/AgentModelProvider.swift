import Foundation

public enum AgentModelMessageRole: String, Codable, Sendable, Equatable {
    case system
    case user
    case assistant
    case tool
}

public struct AgentModelMessage: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var role: AgentModelMessageRole
    public var content: String
    public var toolCallID: String?
    public var name: String?
    public var toolCalls: [AgentToolCall]?

    public init(
        id: String = UUID().uuidString,
        role: AgentModelMessageRole,
        content: String,
        toolCallID: String? = nil,
        name: String? = nil,
        toolCalls: [AgentToolCall]? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.toolCallID = toolCallID
        self.name = name
        self.toolCalls = toolCalls
    }
}

public struct AgentModelCapabilities: Codable, Sendable, Equatable {
    public var supportsStreaming: Bool
    public var supportsToolCalling: Bool
    public var supportsParallelToolCalls: Bool
    public var supportsStructuredOutput: Bool
    public var supportsVision: Bool

    public init(supportsStreaming: Bool, supportsToolCalling: Bool, supportsParallelToolCalls: Bool, supportsStructuredOutput: Bool, supportsVision: Bool) {
        self.supportsStreaming = supportsStreaming
        self.supportsToolCalling = supportsToolCalling
        self.supportsParallelToolCalls = supportsParallelToolCalls
        self.supportsStructuredOutput = supportsStructuredOutput
        self.supportsVision = supportsVision
    }
}

public struct AgentModelRequest: Sendable, Equatable {
    public var messages: [AgentModelMessage]
    public var tools: [AgentToolDefinition]
    public var temperature: Double
    public var promptDiagnostics: AgentPromptDiagnostics?
    public var instructionPlacement: AgentInstructionPlacement

    public init(
        messages: [AgentModelMessage],
        tools: [AgentToolDefinition] = [],
        temperature: Double = 0.2,
        promptDiagnostics: AgentPromptDiagnostics? = nil,
        instructionPlacement: AgentInstructionPlacement = .systemMessage
    ) {
        self.messages = messages
        self.tools = tools
        self.temperature = temperature
        self.promptDiagnostics = promptDiagnostics
        self.instructionPlacement = instructionPlacement
    }
}

public struct AgentModelUsage: Codable, Sendable, Equatable {
    public var promptTokens: Int
    public var completionTokens: Int
    public var totalTokens: Int

    public init(promptTokens: Int, completionTokens: Int, totalTokens: Int? = nil) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens ?? (promptTokens + completionTokens)
    }
}

public enum AgentModelFinishReason: String, Codable, Sendable, Equatable {
    case stop
    case toolCalls = "tool_calls"
    case length
    case contentFilter = "content_filter"
    case unknown
}

public struct AgentModelResponse: Sendable, Equatable {
    public var text: String?
    public var toolCalls: [AgentToolCall]
    public var usage: AgentModelUsage?
    public var finishReason: AgentModelFinishReason
    public var rawResponseJSON: String?

    public init(text: String?, toolCalls: [AgentToolCall] = [], usage: AgentModelUsage? = nil, finishReason: AgentModelFinishReason = .stop, rawResponseJSON: String? = nil) {
        self.text = text
        self.toolCalls = toolCalls
        self.usage = usage
        self.finishReason = finishReason
        self.rawResponseJSON = rawResponseJSON
    }
}

public protocol AgentModelProvider: Sendable {
    var modelID: String { get }
    var capabilities: AgentModelCapabilities { get }

    func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse
}
