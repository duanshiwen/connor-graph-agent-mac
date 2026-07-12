import Foundation
import ConnorGraphAgent
import ConnorGraphCore

public enum EditImageAgentToolError: Error, Sendable, Equatable { case emptyPrompt, missingAttachment, attachmentIsNotImage, providerDoesNotSupportEditing, completedArtifactMissing }

public struct EditImageAgentTool: AgentTool {
    public let name = "edit_image"
    public let description = "Edit an existing Connor session image attachment using a complete instruction and return a new persisted image attachment."
    public let permission: AgentPermissionCapability = .externalNetwork
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
        "prompt": .string(description: "A complete instruction describing the requested image edit."),
        "attachment_id": .string(description: "The Connor session attachment ID of the source image.")
    ], required: ["prompt", "attachment_id"])
    public let inputExamples: [[String: SendableJSONValue]] = [["prompt": .string("Make the scene look like sunrise while preserving composition"), "attachment_id": .string("attachment-id")]]
    public var provider: AnyAgentModelProvider; public var ingestionService: GeneratedMediaIngestionService; public var attachmentStore: AppSessionAttachmentStore
    public init(provider: AnyAgentModelProvider, ingestionService: GeneratedMediaIngestionService, attachmentStore: AppSessionAttachmentStore) { self.provider = provider; self.ingestionService = ingestionService; self.attachmentStore = attachmentStore }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let prompt = arguments.string("prompt")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""; guard !prompt.isEmpty else { throw EditImageAgentToolError.emptyPrompt }
        let attachmentID = arguments.string("attachment_id")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""; guard !attachmentID.isEmpty else { throw EditImageAgentToolError.missingAttachment }
        guard provider.capabilities.generatedMediaCapabilities.contains(.imageEditing) else { throw EditImageAgentToolError.providerDoesNotSupportEditing }
        let manifest = try attachmentStore.loadManifest(sessionID: context.sessionID, attachmentID: attachmentID); guard manifest.kind == .image else { throw EditImageAgentToolError.attachmentIsNotImage }
        let reference = manifest.messageRef
        var completed: AgentGeneratedMediaArtifact?
        for try await event in provider.generateMedia(AgentGeneratedMediaRequest(kind: .image, prompt: prompt, inputAttachments: [reference], imageAction: .edit)) { try Task.checkCancellation(); if case .completed(let artifact) = event { completed = artifact } }
        guard let completed else { throw EditImageAgentToolError.completedArtifactMissing }
        let output = try ingestionService.ingest(artifact: completed, sessionID: context.sessionID); let payload = GeneratedImageToolResultPayload(attachment: output.messageRef, generationMetadata: completed.generationMetadata)
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return AgentToolResult(runID: context.runID, sessionID: context.sessionID, toolCallID: context.toolCallID, toolName: name, contentText: "Image edited and attached to the assistant response.", contentJSON: String(decoding: try encoder.encode(payload), as: UTF8.self))
    }
}
