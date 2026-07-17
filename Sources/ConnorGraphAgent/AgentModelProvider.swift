import Foundation

public enum AgentModelMessageRole: String, Codable, Sendable, Equatable {
    case system
    case user
    case assistant
    case tool
}

public struct AgentModelMessageContentPart: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, Equatable {
        case text
        case imageDataURL = "image_data_url"
    }

    public var kind: Kind
    public var text: String?
    public var dataURL: String?
    public var mimeType: String?
    public var detail: String?

    public init(kind: Kind, text: String? = nil, dataURL: String? = nil, mimeType: String? = nil, detail: String? = nil) {
        self.kind = kind
        self.text = text
        self.dataURL = dataURL
        self.mimeType = mimeType
        self.detail = detail
    }

    public static func text(_ text: String) -> AgentModelMessageContentPart {
        AgentModelMessageContentPart(kind: .text, text: text)
    }

    public static func imageDataURL(_ dataURL: String, mimeType: String?, detail: String? = nil) -> AgentModelMessageContentPart {
        AgentModelMessageContentPart(kind: .imageDataURL, dataURL: dataURL, mimeType: mimeType, detail: detail)
    }
}

public struct AgentModelProviderMetadata: Codable, Sendable, Equatable {
    public var providerID: String
    public var rawAssistantContentJSON: String?
    public var rawOutputItemsJSON: String?
    public var rawContentBlocksJSON: String?
    public var stopReason: String?
    public var responseID: String?
    public var reasoningEncryptedContentPresent: Bool

    public init(
        providerID: String,
        rawAssistantContentJSON: String? = nil,
        rawOutputItemsJSON: String? = nil,
        rawContentBlocksJSON: String? = nil,
        stopReason: String? = nil,
        responseID: String? = nil,
        reasoningEncryptedContentPresent: Bool = false
    ) {
        self.providerID = providerID
        self.rawAssistantContentJSON = rawAssistantContentJSON
        self.rawOutputItemsJSON = rawOutputItemsJSON
        self.rawContentBlocksJSON = rawContentBlocksJSON
        self.stopReason = stopReason
        self.responseID = responseID
        self.reasoningEncryptedContentPresent = reasoningEncryptedContentPresent
    }
}

public struct AgentModelMessage: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var role: AgentModelMessageRole
    public var content: String
    public var contentParts: [AgentModelMessageContentPart]?
    public var toolCallID: String?
    public var name: String?
    public var toolCalls: [AgentToolCall]?
    public var providerMetadata: AgentModelProviderMetadata?

    public init(
        id: String = UUID().uuidString,
        role: AgentModelMessageRole,
        content: String,
        contentParts: [AgentModelMessageContentPart]? = nil,
        toolCallID: String? = nil,
        name: String? = nil,
        toolCalls: [AgentToolCall]? = nil,
        providerMetadata: AgentModelProviderMetadata? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.contentParts = contentParts
        self.toolCallID = toolCallID
        self.name = name
        self.toolCalls = toolCalls
        self.providerMetadata = providerMetadata
    }
}

public enum AgentGeneratedMediaKind: String, Codable, Sendable, Equatable {
    case image
    case speech
}

public enum AgentGeneratedMediaCapability: String, Codable, Sendable, Equatable, CaseIterable {
    case imageInput
    case imageGeneration
    case imageEditing
    case audioInput
    case speechGeneration
    case streamingAudioOutput
}

public enum AgentGeneratedImageAction: String, Codable, Sendable, Equatable {
    case generate
    case edit
}

public struct AgentGeneratedMediaRequest: Sendable, Equatable {
    public var kind: AgentGeneratedMediaKind
    public var prompt: String
    public var inputAttachments: [AgentMessageAttachmentRef]
    public var options: [String: String]
    public var imageAction: AgentGeneratedImageAction

    public init(
        kind: AgentGeneratedMediaKind,
        prompt: String,
        inputAttachments: [AgentMessageAttachmentRef] = [],
        options: [String: String] = [:],
        imageAction: AgentGeneratedImageAction = .generate
    ) {
        self.kind = kind
        self.prompt = prompt
        self.inputAttachments = inputAttachments
        self.options = options
        self.imageAction = imageAction
    }
}

public struct AgentGeneratedMediaArtifact: Sendable, Equatable {
    public var temporaryFileURL: URL
    public var mimeType: String
    public var byteCount: Int64
    public var generationMetadata: AgentAttachmentGenerationMetadata

    public init(temporaryFileURL: URL, mimeType: String, byteCount: Int64, generationMetadata: AgentAttachmentGenerationMetadata) {
        self.temporaryFileURL = temporaryFileURL
        self.mimeType = mimeType
        self.byteCount = byteCount
        self.generationMetadata = generationMetadata
    }
}

public struct AgentGeneratedAudioFormat: Codable, Sendable, Equatable {
    public var encoding: String
    public var sampleRate: Double
    public var channelCount: Int
    public var bitsPerChannel: Int

    public init(encoding: String, sampleRate: Double, channelCount: Int, bitsPerChannel: Int) {
        self.encoding = encoding
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.bitsPerChannel = bitsPerChannel
    }
}

public enum AgentGeneratedMediaEvent: Sendable, Equatable {
    case started
    case progress(Double)
    case preview(Data, mimeType: String)
    case audioStreamStarted(AgentGeneratedAudioFormat)
    case audioChunk(sequence: Int, data: Data, presentationTime: TimeInterval?)
    case completed(AgentGeneratedMediaArtifact)
}

public protocol AgentGeneratedMediaProvider: Sendable {
    var modelID: String { get }
    var capabilities: AgentModelCapabilities { get }
    func generateMedia(_ request: AgentGeneratedMediaRequest) -> AsyncThrowingStream<AgentGeneratedMediaEvent, Error>
}

public struct AgentModelCapabilities: Codable, Sendable, Equatable {
    public var supportsStreaming: Bool
    public var supportsToolCalling: Bool
    public var supportsParallelToolCalls: Bool
    public var supportsStructuredOutput: Bool
    public var supportsVision: Bool
    public var generatedMediaCapabilities: Set<AgentGeneratedMediaCapability>

    public init(
        supportsStreaming: Bool,
        supportsToolCalling: Bool,
        supportsParallelToolCalls: Bool,
        supportsStructuredOutput: Bool,
        supportsVision: Bool,
        generatedMediaCapabilities: Set<AgentGeneratedMediaCapability> = []
    ) {
        self.supportsStreaming = supportsStreaming
        self.supportsToolCalling = supportsToolCalling
        self.supportsParallelToolCalls = supportsParallelToolCalls
        self.supportsStructuredOutput = supportsStructuredOutput
        self.supportsVision = supportsVision
        self.generatedMediaCapabilities = generatedMediaCapabilities
    }

    private enum CodingKeys: String, CodingKey {
        case supportsStreaming, supportsToolCalling, supportsParallelToolCalls, supportsStructuredOutput, supportsVision
        case generatedMediaCapabilities
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        supportsStreaming = try container.decode(Bool.self, forKey: .supportsStreaming)
        supportsToolCalling = try container.decode(Bool.self, forKey: .supportsToolCalling)
        supportsParallelToolCalls = try container.decode(Bool.self, forKey: .supportsParallelToolCalls)
        supportsStructuredOutput = try container.decode(Bool.self, forKey: .supportsStructuredOutput)
        supportsVision = try container.decode(Bool.self, forKey: .supportsVision)
        generatedMediaCapabilities = try container.decodeIfPresent(Set<AgentGeneratedMediaCapability>.self, forKey: .generatedMediaCapabilities) ?? []
    }
}

public enum CurrentModelMediaCapabilityDecision: Sendable, Equatable {
    case supported
    case unsupportedByCurrentModel(reason: String)
}

public enum CurrentModelMediaCapabilityGate {
    public static func decision(
        modelID: String,
        capabilities: AgentModelCapabilities,
        requestKind: AgentGeneratedMediaKind,
        requiresStreaming: Bool = false
    ) -> CurrentModelMediaCapabilityDecision {
        let required: Set<AgentGeneratedMediaCapability>
        switch requestKind {
        case .image:
            required = [.imageGeneration]
        case .speech:
            required = requiresStreaming ? [.speechGeneration, .streamingAudioOutput] : [.speechGeneration]
        }
        guard required.isSubset(of: capabilities.generatedMediaCapabilities) else {
            let missing = required.subtracting(capabilities.generatedMediaCapabilities).map(\.rawValue).sorted().joined(separator: ", ")
            return .unsupportedByCurrentModel(reason: "当前模型 \(modelID) 不支持所需媒体能力：\(missing)。请切换到支持该能力的模型。")
        }
        return .supported
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
    public var cacheCreationInputTokens: Int?
    public var cacheReadInputTokens: Int?

    public init(promptTokens: Int, completionTokens: Int, totalTokens: Int? = nil, cacheCreationInputTokens: Int? = nil, cacheReadInputTokens: Int? = nil) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens ?? (promptTokens + completionTokens)
        self.cacheCreationInputTokens = cacheCreationInputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
    }

    public init(promptTokens: Int, completionTokens: Int, totalTokens: Int?) {
        self.init(promptTokens: promptTokens, completionTokens: completionTokens, totalTokens: totalTokens, cacheCreationInputTokens: nil, cacheReadInputTokens: nil)
    }
}

public enum AgentModelFinishReason: String, Codable, Sendable, Equatable {
    case stop
    case toolCalls = "tool_calls"
    case length
    case pause
    case contentFilter = "content_filter"
    case unknown

    public static func openAICompatible(finishReason: String?) -> AgentModelFinishReason {
        switch finishReason {
        case "stop": .stop
        case "tool_calls", "function_call": .toolCalls
        case "length": .length
        case "content_filter": .contentFilter
        default: .unknown
        }
    }

    public static func anthropic(stopReason: String?) -> AgentModelFinishReason {
        switch stopReason {
        case "end_turn", "stop_sequence": .stop
        case "tool_use": .toolCalls
        case "max_tokens", "model_context_window_exceeded": .length
        case "pause_turn": .pause
        case "refusal": .contentFilter
        default: .unknown
        }
    }
}

public struct AgentModelResponse: Sendable, Equatable {
    public var text: String?
    public var toolCalls: [AgentToolCall]
    public var usage: AgentModelUsage?
    public var finishReason: AgentModelFinishReason
    public var rawResponseJSON: String?
    public var providerMetadata: AgentModelProviderMetadata?
    public var warnings: [String]

    public init(text: String?, toolCalls: [AgentToolCall] = [], usage: AgentModelUsage? = nil, finishReason: AgentModelFinishReason = .stop, rawResponseJSON: String? = nil, providerMetadata: AgentModelProviderMetadata? = nil, warnings: [String] = []) {
        self.text = text
        self.toolCalls = toolCalls
        self.usage = usage
        self.finishReason = finishReason
        self.rawResponseJSON = rawResponseJSON
        self.providerMetadata = providerMetadata
        self.warnings = warnings
    }

    public init(text: String?, toolCalls: [AgentToolCall], usage: AgentModelUsage?, finishReason: AgentModelFinishReason, rawResponseJSON: String?) {
        self.init(text: text, toolCalls: toolCalls, usage: usage, finishReason: finishReason, rawResponseJSON: rawResponseJSON, providerMetadata: nil)
    }
}

public enum AgentModelStreamEvent: Sendable, Equatable {
    case textDelta(String)
    case thinkingDelta(String)
    case toolInputDelta(toolCallID: String?, name: String?, partialJSON: String)
    case rawProviderEvent(String)
    case completed(AgentModelResponse)
}

public protocol AgentModelProvider: Sendable {
    var modelID: String { get }
    var capabilities: AgentModelCapabilities { get }

    func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse
}

public protocol StreamingAgentModelProvider: AgentModelProvider {
    func streamComplete(_ request: AgentModelRequest) -> AsyncThrowingStream<AgentModelStreamEvent, Error>
}
