import Foundation
import ImageIO
import UniformTypeIdentifiers
import ConnorGraphAgent
import ConnorGraphCore

public enum LoadAttachmentContextAgentToolError: Error, Sendable, Equatable {
    case missingAttachmentIDs
    case tooManyAttachments
    case invalidStoredContent
}

public struct LoadAttachmentContextAgentTool: AgentTool {
    public let name = "load_attachment_context"
    public let description = "Load selected historical session attachments into this model run only. Use exact IDs from the historical media catalog and call only when the current task actually depends on their content. Images are supplied as bounded visual inputs; audio/video/documents use an available transcript or extracted-text derivative. Original binaries remain unchanged."
    public let permission: AgentPermissionCapability = .readSession
    public let inputSchema = AgentToolInputSchema.closedObject(
        properties: [
            "attachmentIDs": .array(
                items: .string(description: "Exact attachment ID from the historical media catalog."),
                description: "One to eight historical attachment IDs needed for the current task."
            )
        ],
        required: ["attachmentIDs"]
    )
    public let inputExamples: [[String: SendableJSONValue]] = [
        ["attachmentIDs": .array([.string("exact-attachment-id")])]
    ]

    public var store: AppSessionAttachmentStore
    public var maximumAttachmentCount: Int
    public var maximumTextCharactersPerAttachment: Int
    public var maximumImagePixelSize: Int
    public var maximumImageBytes: Int

    public init(
        store: AppSessionAttachmentStore,
        maximumAttachmentCount: Int = 8,
        maximumTextCharactersPerAttachment: Int = 40_000,
        maximumImagePixelSize: Int = 2_048,
        maximumImageBytes: Int = 4_000_000
    ) {
        self.store = store
        self.maximumAttachmentCount = max(1, maximumAttachmentCount)
        self.maximumTextCharactersPerAttachment = max(1, maximumTextCharactersPerAttachment)
        self.maximumImagePixelSize = max(512, maximumImagePixelSize)
        self.maximumImageBytes = max(256_000, maximumImageBytes)
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let attachmentIDs = (arguments.array("attachmentIDs") ?? arguments.array("attachment_ids") ?? [])
            .compactMap(\.stringValue)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !attachmentIDs.isEmpty else { throw LoadAttachmentContextAgentToolError.missingAttachmentIDs }
        guard attachmentIDs.count <= maximumAttachmentCount else { throw LoadAttachmentContextAgentToolError.tooManyAttachments }

        var parts: [AgentModelMessageContentPart] = []
        var summaries: [String] = []
        for attachmentID in attachmentIDs {
            let manifest = try store.loadManifest(sessionID: context.sessionID, attachmentID: attachmentID)
            let sourceURL = store.paths.sessionArtifactDirectories(sessionID: context.sessionID).root.appendingPathComponent(manifest.storedRelativePath)
            switch manifest.kind {
            case .image:
                let payload = try preparedImage(
                    sourceURL: sourceURL,
                    expectedSHA256: manifest.sha256,
                    originalMIMEType: manifest.mimeType ?? "image/png"
                )
                parts.append(.imageDataURL("data:\(payload.mimeType);base64,\(payload.data.base64EncodedString())", mimeType: payload.mimeType, detail: "auto"))
                summaries.append("Loaded image \(manifest.displayName) (\(manifest.id)).")
            default:
                if let text = try extractedText(for: manifest, sessionID: context.sessionID) {
                    parts.append(.text("Attachment \(manifest.displayName) (\(manifest.id), \(manifest.kind.rawValue)):\n\(text)"))
                    summaries.append("Loaded extracted context for \(manifest.displayName) (\(manifest.id)).")
                } else {
                    summaries.append("No model-compatible native or derived representation is available for \(manifest.displayName) (\(manifest.id), \(manifest.kind.rawValue)); the original binary remains stored.")
                }
            }
        }

        return AgentToolResult(
            runID: context.runID,
            sessionID: context.sessionID,
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: summaries.joined(separator: "\n"),
            modelContentParts: parts.isEmpty ? nil : parts
        )
    }

    private func extractedText(for manifest: AgentAttachmentManifest, sessionID: String) throws -> String? {
        let relativePath = manifest.extractedTextRelativePath
            ?? manifest.derivativeRefs.last(where: { $0.kind == .mediaTranscript || $0.kind == .extractedMarkdown })?.relativePath
        guard let relativePath else { return nil }
        let root = store.paths.sessionArtifactDirectories(sessionID: sessionID).root
        let text = try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
        guard !text.isEmpty else { return nil }
        return String(text.prefix(maximumTextCharactersPerAttachment))
    }

    private func preparedImage(sourceURL: URL, expectedSHA256: String, originalMIMEType: String) throws -> (data: Data, mimeType: String) {
        let original = try Data(contentsOf: sourceURL)
        guard AppSessionAttachmentStore.sha256Hex(original) == expectedSHA256 else {
            throw LoadAttachmentContextAgentToolError.invalidStoredContent
        }
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            guard original.count <= maximumImageBytes else { throw LoadAttachmentContextAgentToolError.invalidStoredContent }
            return (original, originalMIMEType)
        }
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        guard original.count > maximumImageBytes || max(width, height) > maximumImagePixelSize else {
            return (original, originalMIMEType)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumImagePixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw LoadAttachmentContextAgentToolError.invalidStoredContent
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw LoadAttachmentContextAgentToolError.invalidStoredContent
        }
        CGImageDestinationAddImage(destination, thumbnail, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination), output.length <= maximumImageBytes else {
            throw LoadAttachmentContextAgentToolError.invalidStoredContent
        }
        return (output as Data, "image/jpeg")
    }
}
