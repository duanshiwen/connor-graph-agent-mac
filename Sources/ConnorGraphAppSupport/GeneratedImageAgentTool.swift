import Foundation
import ConnorGraphAgent
import ConnorGraphCore

public enum GeneratedImageAgentToolError: Error, Sendable, Equatable, LocalizedError {
    case emptyPrompt
    case unsupportedByCurrentModel(String)
    case completedArtifactMissing

    public var errorDescription: String? {
        switch self {
        case .emptyPrompt:
            return "Image generation requires a non-empty prompt."
        case .unsupportedByCurrentModel(let reason):
            return reason
        case .completedArtifactMissing:
            return "The image provider completed without returning an image artifact."
        }
    }
}

public struct GeneratedImageToolResultPayload: Codable, Sendable, Equatable {
    public var attachment: AgentMessageAttachmentRef
    public var generationMetadata: AgentAttachmentGenerationMetadata

    public init(attachment: AgentMessageAttachmentRef, generationMetadata: AgentAttachmentGenerationMetadata) {
        self.attachment = attachment
        self.generationMetadata = generationMetadata
    }
}

public struct GeneratedImageAgentTool: AgentTool {
    public let name = "generate_image"
    public let description = "Generate an image from a complete text prompt using the current model connection, persist it as a Connor session attachment, and return the generated attachment."
    public let permission: AgentPermissionCapability = .externalNetwork
    public let inputSchema = AgentToolInputSchema.closedObject(
        properties: [
            "prompt": .string(description: "A complete, self-contained description of the image to generate.")
        ],
        required: ["prompt"]
    )
    public let inputExamples: [[String: SendableJSONValue]] = [
        ["prompt": .string("A calm gray tabby cat reading beside a rain-streaked window, warm cinematic light")]
    ]

    public var provider: AnyAgentModelProvider
    public var ingestionService: GeneratedMediaIngestionService

    public init(provider: AnyAgentModelProvider, ingestionService: GeneratedMediaIngestionService) {
        self.provider = provider
        self.ingestionService = ingestionService
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let prompt = arguments.string("prompt")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !prompt.isEmpty else { throw GeneratedImageAgentToolError.emptyPrompt }
        switch CurrentModelMediaCapabilityGate.decision(modelID: provider.modelID, capabilities: provider.capabilities, requestKind: .image) {
        case .supported:
            break
        case .unsupportedByCurrentModel(let reason):
            throw GeneratedImageAgentToolError.unsupportedByCurrentModel(reason)
        }

        var completedArtifact: AgentGeneratedMediaArtifact?
        for try await event in provider.generateMedia(AgentGeneratedMediaRequest(kind: .image, prompt: prompt)) {
            try Task.checkCancellation()
            if case .completed(let artifact) = event { completedArtifact = artifact }
        }
        guard let completedArtifact else { throw GeneratedImageAgentToolError.completedArtifactMissing }

        let manifest = try ingestionService.ingest(artifact: completedArtifact, sessionID: context.sessionID)
        let payload = GeneratedImageToolResultPayload(
            attachment: manifest.messageRef,
            generationMetadata: completedArtifact.generationMetadata
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payloadJSON = String(decoding: try encoder.encode(payload), as: UTF8.self)
        return AgentToolResult(
            runID: context.runID,
            sessionID: context.sessionID,
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: "Image generated and attached to the assistant response.",
            contentJSON: payloadJSON
        )
    }
}
