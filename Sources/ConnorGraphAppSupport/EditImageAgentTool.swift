import Foundation
import ImageIO
import UniformTypeIdentifiers
import ConnorGraphAgent
import ConnorGraphCore

public enum EditImageAgentToolError: Error, Sendable, Equatable { case emptyPrompt, missingAttachment, attachmentIsNotImage, providerDoesNotSupportEditing, inputImageTooLarge, completedArtifactMissing }

public struct EditImageAgentTool: AgentTool {
    public let name = "edit_image"
    public let description = "Edit an existing Connor session image attachment using a complete instruction and return a new persisted image attachment."
    public let permission: AgentPermissionCapability = .externalNetwork
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
        "prompt": .string(description: "A complete instruction describing the requested image edit."),
        "attachmentID": .string(description: "The Connor session attachment ID of the source image.")
    ], required: ["prompt", "attachmentID"])
    public let inputExamples: [[String: SendableJSONValue]] = [["prompt": .string("Make the scene look like sunrise while preserving composition"), "attachmentID": .string("attachment-id")]]
    public var provider: AnyAgentModelProvider; public var ingestionService: GeneratedMediaIngestionService; public var attachmentStore: AppSessionAttachmentStore
    public init(provider: AnyAgentModelProvider, ingestionService: GeneratedMediaIngestionService, attachmentStore: AppSessionAttachmentStore) { self.provider = provider; self.ingestionService = ingestionService; self.attachmentStore = attachmentStore }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let prompt = arguments.string("prompt")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""; guard !prompt.isEmpty else { throw EditImageAgentToolError.emptyPrompt }
        let attachmentID = (arguments.string("attachmentID") ?? arguments.string("attachment_id"))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""; guard !attachmentID.isEmpty else { throw EditImageAgentToolError.missingAttachment }
        guard provider.capabilities.generatedMediaCapabilities.contains(.imageEditing) else { throw EditImageAgentToolError.providerDoesNotSupportEditing }
        let manifest = try attachmentStore.loadManifest(sessionID: context.sessionID, attachmentID: attachmentID); guard manifest.kind == .image else { throw EditImageAgentToolError.attachmentIsNotImage }
        let reference = manifest.messageRef
        let sourceURL = attachmentStore.paths.sessionArtifactDirectories(sessionID: context.sessionID).root.appendingPathComponent(manifest.storedRelativePath)
        let inputImage = try Self.preparedInputImage(
            attachmentID: attachmentID,
            mimeType: manifest.mimeType ?? "image/png",
            sourceURL: sourceURL
        )
        var completed: AgentGeneratedMediaArtifact?
        for try await event in provider.generateMedia(AgentGeneratedMediaRequest(
            kind: .image,
            prompt: prompt,
            inputAttachments: [reference],
            inputImages: [inputImage],
            imageAction: .edit,
            auditContext: AgentLLMRequestAuditContext(
                requestKind: .generatedMedia,
                sessionID: context.sessionID,
                runID: context.runID,
                correlationID: context.toolCallID,
                operation: "EditImageAgentTool.execute",
                initiator: .foreground,
                metadata: ["tool_name": name]
            )
        )) { try Task.checkCancellation(); if case .completed(let artifact) = event { completed = artifact } }
        guard var completed else { throw EditImageAgentToolError.completedArtifactMissing }
        completed.generationMetadata.parameters[AgentAttachmentGenerationMetadata.sourceAttachmentIDParameterKey] = attachmentID
        let output = try ingestionService.ingest(artifact: completed, sessionID: context.sessionID); let payload = GeneratedImageToolResultPayload(attachment: output.messageRef, generationMetadata: completed.generationMetadata)
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return AgentToolResult(runID: context.runID, sessionID: context.sessionID, toolCallID: context.toolCallID, toolName: name, contentText: "Image edited and attached to the assistant response.", contentJSON: String(decoding: try encoder.encode(payload), as: UTF8.self))
    }

    private static func preparedInputImage(
        attachmentID: String,
        mimeType: String,
        sourceURL: URL,
        maximumPixelSize: Int = 4_096,
        maximumBytes: Int = 20_000_000
    ) throws -> AgentGeneratedMediaInputImage {
        let original = try Data(contentsOf: sourceURL)
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            guard original.count <= maximumBytes else { throw EditImageAgentToolError.inputImageTooLarge }
            return AgentGeneratedMediaInputImage(attachmentID: attachmentID, mimeType: mimeType, data: original)
        }
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        guard original.count > maximumBytes || max(width, height) > maximumPixelSize else {
            return AgentGeneratedMediaInputImage(attachmentID: attachmentID, mimeType: mimeType, data: original)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw EditImageAgentToolError.inputImageTooLarge
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw EditImageAgentToolError.inputImageTooLarge
        }
        CGImageDestinationAddImage(destination, thumbnail, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination), output.length <= maximumBytes else {
            throw EditImageAgentToolError.inputImageTooLarge
        }
        return AgentGeneratedMediaInputImage(attachmentID: attachmentID, mimeType: "image/jpeg", data: output as Data)
    }
}
