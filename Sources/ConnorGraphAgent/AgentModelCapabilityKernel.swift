import Foundation

public struct AgentImageDataURL: Sendable, Equatable {
    public var mimeType: String
    public var base64: String
    public var original: String

    public init(mimeType: String, base64: String, original: String) {
        self.mimeType = mimeType
        self.base64 = base64
        self.original = original
    }
}

public enum AgentImageDataURLParser {
    public static func parse(_ dataURL: String, fallbackMimeType: String? = nil) -> AgentImageDataURL? {
        let trimmed = dataURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.lowercased().hasPrefix("data:") {
            guard let commaIndex = trimmed.firstIndex(of: ",") else { return nil }
            let metadata = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 5)..<commaIndex])
            let payload = String(trimmed[trimmed.index(after: commaIndex)...])
            let metadataParts = metadata.split(separator: ";").map { String($0).lowercased() }
            guard let mediaType = metadataParts.first, mediaType.hasPrefix("image/") else { return nil }
            guard metadataParts.contains("base64") else { return nil }
            guard !payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return AgentImageDataURL(mimeType: mediaType, base64: payload, original: trimmed)
        }

        guard let fallbackMimeType else { return nil }
        let normalizedMimeType = fallbackMimeType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedMimeType.hasPrefix("image/"), !trimmed.isEmpty else { return nil }
        return AgentImageDataURL(mimeType: normalizedMimeType, base64: trimmed, original: trimmed)
    }
}

public enum AgentModelProviderKind: String, Codable, Sendable, Equatable {
    case openAICompatible
    case openAIResponses
    case anthropicCompatible
    case unknown
}

public enum AgentModelCapabilitySignal: String, Codable, Sendable, Equatable {
    case explicitConfig
    case providerPreset
    case modelNameHeuristic
    case providerDefault
}

public enum AgentModelCapabilityConfidence: String, Codable, Sendable, Equatable {
    case explicit
    case high
    case medium
    case low
    case unknown
}

public struct AgentModelCapabilityProfile: Codable, Sendable, Equatable {
    public var providerKind: AgentModelProviderKind
    public var modelID: String
    public var supportsStreaming: Bool
    public var supportsToolCalling: Bool
    public var supportsParallelToolCalls: Bool
    public var supportsStructuredOutput: Bool
    public var supportsVision: Bool
    public var generatedMediaCapabilities: Set<AgentGeneratedMediaCapability>
    public var confidence: AgentModelCapabilityConfidence
    public var signals: [AgentModelCapabilitySignal]

    public var agentCapabilities: AgentModelCapabilities {
        AgentModelCapabilities(
            supportsStreaming: supportsStreaming,
            supportsToolCalling: supportsToolCalling,
            supportsParallelToolCalls: supportsParallelToolCalls,
            supportsStructuredOutput: supportsStructuredOutput,
            supportsVision: supportsVision,
            generatedMediaCapabilities: generatedMediaCapabilities
        )
    }

    public init(
        providerKind: AgentModelProviderKind,
        modelID: String,
        supportsStreaming: Bool,
        supportsToolCalling: Bool,
        supportsParallelToolCalls: Bool,
        supportsStructuredOutput: Bool,
        supportsVision: Bool,
        generatedMediaCapabilities: Set<AgentGeneratedMediaCapability> = [],
        confidence: AgentModelCapabilityConfidence,
        signals: [AgentModelCapabilitySignal]
    ) {
        self.providerKind = providerKind
        self.modelID = modelID
        self.supportsStreaming = supportsStreaming
        self.supportsToolCalling = supportsToolCalling
        self.supportsParallelToolCalls = supportsParallelToolCalls
        self.supportsStructuredOutput = supportsStructuredOutput
        self.supportsVision = supportsVision
        self.generatedMediaCapabilities = generatedMediaCapabilities
        self.confidence = confidence
        self.signals = signals
    }
}

public enum AgentVisionSendDecision: Sendable, Equatable {
    case allowed
    case denied(reason: String)
}

public enum AgentModelCapabilityKernel {
    public static func profile(
        providerKind: AgentModelProviderKind,
        modelID: String,
        explicitVisionSupport: Bool? = nil,
        explicitGeneratedMediaCapabilities: Set<AgentGeneratedMediaCapability>? = nil
    ) -> AgentModelCapabilityProfile {
        let base = baseCapabilities(for: providerKind)
        let normalizedModel = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let visionResolution = resolveVisionSupport(providerKind: providerKind, modelID: normalizedModel, explicitVisionSupport: explicitVisionSupport)
        let generatedMediaResolution = resolveGeneratedMediaCapabilities(providerKind: providerKind, modelID: normalizedModel)
        return AgentModelCapabilityProfile(
            providerKind: providerKind,
            modelID: normalizedModel,
            supportsStreaming: base.streaming,
            supportsToolCalling: base.toolCalling,
            supportsParallelToolCalls: base.parallelToolCalls,
            supportsStructuredOutput: base.structuredOutput,
            supportsVision: visionResolution.supportsVision,
            generatedMediaCapabilities: explicitGeneratedMediaCapabilities ?? generatedMediaResolution.capabilities,
            confidence: explicitGeneratedMediaCapabilities != nil ? .explicit : maxConfidence(visionResolution.confidence, generatedMediaResolution.confidence),
            signals: Array(Set(visionResolution.signals + (explicitGeneratedMediaCapabilities != nil ? [.explicitConfig] : generatedMediaResolution.signals)))
        )
    }

    public static func visionSendDecision(
        profile: AgentModelCapabilityProfile,
        request: AgentModelRequest
    ) -> AgentVisionSendDecision {
        guard request.containsImageInput else { return .allowed }
        guard profile.supportsVision else {
            return .denied(reason: "Model \(profile.modelID) does not support vision input according to Connor model capability kernel.")
        }
        return .allowed
    }

    private static func baseCapabilities(for providerKind: AgentModelProviderKind) -> (streaming: Bool, toolCalling: Bool, parallelToolCalls: Bool, structuredOutput: Bool) {
        switch providerKind {
        case .openAICompatible:
            return (streaming: true, toolCalling: true, parallelToolCalls: false, structuredOutput: false)
        case .openAIResponses:
            return (streaming: true, toolCalling: true, parallelToolCalls: true, structuredOutput: true)
        case .anthropicCompatible:
            return (streaming: true, toolCalling: true, parallelToolCalls: false, structuredOutput: false)
        case .unknown:
            return (streaming: false, toolCalling: false, parallelToolCalls: false, structuredOutput: false)
        }
    }

    private static func resolveVisionSupport(
        providerKind: AgentModelProviderKind,
        modelID: String,
        explicitVisionSupport: Bool?
    ) -> (supportsVision: Bool, confidence: AgentModelCapabilityConfidence, signals: [AgentModelCapabilitySignal]) {
        if let explicitVisionSupport {
            return (explicitVisionSupport, .explicit, [.explicitConfig])
        }

        let normalized = modelID.lowercased()
        if containsAny(normalized, in: nonVisionMarkers) {
            return (false, .high, [.modelNameHeuristic])
        }
        if containsAny(normalized, in: visionMarkers) {
            return (true, .high, [.modelNameHeuristic])
        }
        if providerKind == .anthropicCompatible, normalized.contains("claude") {
            return (true, .high, [.providerPreset])
        }
        if providerKind == .openAIResponses, normalized.hasPrefix("gpt-5") || normalized.hasPrefix("gpt-4.1") || normalized.hasPrefix("gpt-4o") {
            return (true, .high, [.providerPreset])
        }
        return (false, .unknown, [.providerDefault])
    }

    private static func resolveGeneratedMediaCapabilities(
        providerKind: AgentModelProviderKind,
        modelID: String
    ) -> (capabilities: Set<AgentGeneratedMediaCapability>, confidence: AgentModelCapabilityConfidence, signals: [AgentModelCapabilitySignal]) {
        let normalized = modelID.lowercased()
        var result: Set<AgentGeneratedMediaCapability> = []
        var confidence: AgentModelCapabilityConfidence = .unknown
        var signals: [AgentModelCapabilitySignal] = []
        if providerKind == .openAIResponses, supportsOpenAIHostedImageTool(normalized) {
            result.insert(.imageGeneration)
            confidence = .high
            signals.append(.providerPreset)
        }
        if normalized.contains("tts") {
            result.formUnion([.speechGeneration, .streamingAudioOutput])
            confidence = .medium
            signals.append(.modelNameHeuristic)
        }
        if normalized.contains("realtime") && providerKind != .anthropicCompatible {
            result.formUnion([.audioInput, .speechGeneration, .streamingAudioOutput])
            confidence = .medium
            signals.append(.modelNameHeuristic)
        }
        if resolveVisionSupport(providerKind: providerKind, modelID: modelID, explicitVisionSupport: nil).supportsVision {
            result.insert(.imageInput)
        }
        return (result, confidence, signals)
    }

    private static func supportsOpenAIHostedImageTool(_ modelID: String) -> Bool {
        let exactModels: Set<String> = ["o3"]
        if exactModels.contains(modelID) { return true }
        return ["gpt-5", "gpt-4.1", "gpt-4o"].contains { family in
            modelID == family || modelID.hasPrefix(family + "-") || modelID.hasPrefix(family + ".")
        }
    }

    private static func maxConfidence(_ lhs: AgentModelCapabilityConfidence, _ rhs: AgentModelCapabilityConfidence) -> AgentModelCapabilityConfidence {
        let rank: [AgentModelCapabilityConfidence: Int] = [.unknown: 0, .low: 1, .medium: 2, .high: 3, .explicit: 4]
        return (rank[lhs] ?? 0) >= (rank[rhs] ?? 0) ? lhs : rhs
    }

    private static func containsAny(_ value: String, in markers: [String]) -> Bool {
        markers.contains { value.contains($0) }
    }

    private static let nonVisionMarkers = [
        "embedding", "embed", "rerank", "tts", "asr", "whisper", "image-edit", "image-editing", "image-generation", "text-to-image", "coder",
        "mimo-v2.5-pro" // Xiaomi MiMo V2.5 Pro / UltraSpeed: pure-text agent models, no vision
    ]

    private static let visionMarkers = [
        "vision", "-vl", "_vl", "vl-", "vl_", "qwen-vl", "qwen3-vl", "omni", "gpt-4o", "gpt-4.1", "gpt-5", "claude", "gemini", "glm-4.5v", "glm-5v", "glm-4v", "minimax-vl", "pixtral",
        "mimo-v2.5" // Xiaomi MiMo V2.5: native omnimodal model with image/video/audio support
    ]
}

public extension AgentModelRequest {
    var containsImageInput: Bool { imageInputCount > 0 }

    var imageInputCount: Int {
        messages.reduce(0) { total, message in
            total + (message.contentParts?.filter { $0.kind == .imageDataURL }.count ?? 0)
        }
    }

    /// 返回一个新请求，移除所有图片内容，保留纯文字。
    /// 如果某条消息只有图片没有文字，保留一条占位提示。
    func stripImageContent() -> AgentModelRequest {
        var stripped = self
        stripped.messages = messages.map { message in
            guard let parts = message.contentParts,
                  parts.contains(where: { $0.kind == .imageDataURL }) else {
                return message
            }
            let textParts = parts.filter { $0.kind == .text }
            var newMessage = message
            if textParts.isEmpty {
                newMessage.content = "[图片内容已忽略]"
                newMessage.contentParts = nil
            } else {
                newMessage.content = textParts.compactMap(\.text).joined(separator: "\n")
                newMessage.contentParts = textParts
            }
            return newMessage
        }
        return stripped
    }
}
