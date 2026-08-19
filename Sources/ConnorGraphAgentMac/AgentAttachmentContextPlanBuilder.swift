import Foundation
import ImageIO
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore
import UniformTypeIdentifiers

struct AgentAttachmentContextPlanBuilder: Sendable {
    var storagePaths: AppStoragePaths?
    var totalCharacterLimit: Int = Int(AttachmentImportPolicy.defaultTotalAcceptedCharacters)
    var maximumImageContextPixelSize: Int = 2_048
    var maximumImageContextBytes: Int = 4_000_000

    /// 已提取文本附件的内容字符数；尚未提取或读取失败返回 nil。
    static func extractedContentCharacterCount(
        store: AppSessionAttachmentStore,
        sessionID: String,
        attachmentID: String
    ) -> Int? {
        guard let manifest = try? store.loadManifest(sessionID: sessionID, attachmentID: attachmentID),
              manifest.extractionStatus == .extracted,
              let relativePath = manifest.extractedTextRelativePath
        else { return nil }
        let url = store.paths.sessionArtifactDirectories(sessionID: sessionID)
            .root
            .appendingPathComponent(relativePath)
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return content.count
    }

    static func conversationAttachments(
        messages: [AgentMessage],
        currentAttachments: [AgentMessageAttachmentRef],
        explicitlyRehydratedAttachments: [AgentMessageAttachmentRef] = []
    ) -> [AgentMessageAttachmentRef] {
        var seenIDs = Set<String>()
        return (messages.flatMap(\.attachments) + currentAttachments + explicitlyRehydratedAttachments).filter {
            seenIDs.insert($0.id).inserted
        }
    }

    static func historicalAssistantMediaAttachmentIDs(messages: [AgentMessage]) -> Set<String> {
        Set(messages.flatMap { message -> [String] in
            guard message.role == .assistant else { return [] }
            return message.attachments.compactMap { attachment in
                switch attachment.kind {
                case .image, .audio, .video:
                    attachment.id
                default:
                    nil
                }
            }
        })
    }

    func build(
        sessionID: String,
        attachments: [AgentMessageAttachmentRef],
        preservingAttachmentIDs: Set<String> = [],
        deferredMediaAttachmentIDs: Set<String> = []
    ) -> AttachmentContextPlan {
        guard !attachments.isEmpty, let storagePaths else { return AttachmentContextPlan() }
        let store = AppSessionAttachmentStore(paths: storagePaths)
        let supersededAttachmentIDs = Set(attachments.compactMap { attachment -> String? in
            guard let manifest = try? store.loadManifest(sessionID: sessionID, attachmentID: attachment.id)
            else { return nil }
            return manifest.generationMetadata?.parameters[AgentAttachmentGenerationMetadata.sourceAttachmentIDParameterKey]
        })
        var inlineBlocks: [AttachmentInlineBlock] = []
        var imageBlocks: [AttachmentImageBlock] = []
        var omissions: [AttachmentOmission] = []
        var remainingBudget = totalCharacterLimit
        for attachment in attachments {
            if supersededAttachmentIDs.contains(attachment.id),
               !preservingAttachmentIDs.contains(attachment.id) {
                continue
            }
            guard remainingBudget > 0 else {
                omissions.append(AttachmentOmission(attachmentID: attachment.id, displayName: attachment.displayName, reason: "Total attachment prompt budget exhausted."))
                continue
            }
            do {
                let manifest = try store.loadManifest(sessionID: sessionID, attachmentID: attachment.id)
                if deferredMediaAttachmentIDs.contains(attachment.id),
                   !preservingAttachmentIDs.contains(attachment.id) {
                    inlineBlocks.append(mediaCatalogBlock(for: manifest))
                    continue
                }
                if manifest.kind == .image {
                    let imageURL = storagePaths.sessionArtifactDirectories(sessionID: sessionID).root.appendingPathComponent(manifest.storedRelativePath)
                    let data = try Data(contentsOf: imageURL)
                    guard AppSessionAttachmentStore.sha256Hex(data) == manifest.sha256 else {
                        omissions.append(AttachmentOmission(
                            attachmentID: attachment.id,
                            displayName: attachment.displayName,
                            reason: "Stored image content failed integrity verification."
                        ))
                        continue
                    }
                    guard let payload = contextImagePayload(
                        sourceURL: imageURL,
                        originalData: data,
                        originalMIMEType: manifest.mimeType ?? "image/png"
                    ) else {
                        omissions.append(AttachmentOmission(
                            attachmentID: attachment.id,
                            displayName: attachment.displayName,
                            reason: "Image is too large to prepare safely for model context. The original remains stored locally."
                        ))
                        continue
                    }
                    let dataURL = "data:\(payload.mimeType);base64,\(payload.data.base64EncodedString())"
                    imageBlocks.append(AttachmentImageBlock(
                        attachmentID: manifest.id,
                        displayName: manifest.displayName,
                        mimeType: payload.mimeType,
                        dataURL: dataURL,
                        sourceRelativePath: manifest.storedRelativePath
                    ))
                    continue
                }
                guard let relativePath = manifest.extractedTextRelativePath else {
                    omissions.append(AttachmentOmission(
                        attachmentID: attachment.id,
                        displayName: attachment.displayName,
                        reason: Self.attachmentOmissionReason(for: manifest)
                    ))
                    continue
                }
                let url = storagePaths.sessionArtifactDirectories(sessionID: sessionID).root.appendingPathComponent(relativePath)
                let content = try String(contentsOf: url, encoding: .utf8)
                // 附件要么完整纳入，要么明确拒绝：绝不截断后“半读”。
                guard content.count <= remainingBudget else {
                    omissions.append(AttachmentOmission(
                        attachmentID: manifest.id,
                        displayName: manifest.displayName,
                        reason: "Total attachment prompt budget (\(totalCharacterLimit) characters) exhausted; remove earlier attachments to include this one in full."
                    ))
                    continue
                }
                remainingBudget -= content.count
                inlineBlocks.append(AttachmentInlineBlock(
                    attachmentID: manifest.id,
                    displayName: manifest.displayName,
                    kind: manifest.kind,
                    content: content,
                    sourceRelativePath: relativePath,
                    isTruncated: false
                ))
            } catch {
                omissions.append(AttachmentOmission(attachmentID: attachment.id, displayName: attachment.displayName, reason: "Failed to read extracted text: \(error)"))
            }
        }
        let estimatedTokens = max(1,
            inlineBlocks.reduce(0) { $0 + $1.content.count } / 4
                + imageBlocks.reduce(0) {
                    $0 + AgentVisionTokenEstimator().estimateImageTokenCount(dataURL: $1.dataURL)
                }
        )
        return AttachmentContextPlan(inlineBlocks: inlineBlocks, omittedAttachments: omissions, imageBlocks: imageBlocks, estimatedTokens: estimatedTokens)
    }

    private func mediaCatalogBlock(for manifest: AgentAttachmentManifest) -> AttachmentInlineBlock {
        var details = [
            "Historical media attachment available on demand.",
            "ID: \(manifest.id)",
            "Name: \(manifest.displayName)",
            "Kind: \(manifest.kind.rawValue)",
            "Bytes: \(manifest.byteCount)"
        ]
        if let width = manifest.mediaMetadata?.pixelWidth, let height = manifest.mediaMetadata?.pixelHeight {
            details.append("Dimensions: \(width)x\(height)")
        }
        if let duration = manifest.mediaMetadata?.durationSeconds {
            details.append(String(format: "Duration: %.1f seconds", duration))
        }
        details.append("Call load_attachment_context with this exact ID only when the current task needs the media content.")
        return AttachmentInlineBlock(
            attachmentID: manifest.id,
            displayName: manifest.displayName,
            kind: manifest.kind,
            content: details.joined(separator: "\n"),
            sourceRelativePath: nil
        )
    }

    private func contextImagePayload(
        sourceURL: URL,
        originalData: Data,
        originalMIMEType: String
    ) -> (data: Data, mimeType: String)? {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            return originalData.count <= maximumImageContextBytes ? (originalData, originalMIMEType) : nil
        }
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        guard originalData.count > maximumImageContextBytes || max(width, height) > maximumImageContextPixelSize else {
            return (originalData, originalMIMEType)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumImageContextPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, thumbnail, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination), output.length <= maximumImageContextBytes else { return nil }
        return (output as Data, "image/jpeg")
    }

    static func attachmentOmissionReason(for manifest: AgentAttachmentManifest) -> String {
        switch manifest.kind {
        case .audio:
            let duration = manifest.mediaMetadata?.durationSeconds.map { String(format: "%.1f seconds", $0) } ?? "unknown duration"
            return "Audio is preserved locally (\(duration)) but is not sent as Base64 unless the selected provider exposes native audio input. A transcript derivative can be included when available."
        case .video:
            let duration = manifest.mediaMetadata?.durationSeconds.map { String(format: "%.1f seconds", $0) } ?? "unknown duration"
            return "Video is preserved locally (\(duration)) but is not sent as Base64 unless the selected provider exposes native video input. Transcript and key-frame derivatives can be included when available."
        default:
            break
        }
        switch manifest.extractionStatus {
        case .pending:
            return "Text extraction is still pending; this attachment is saved locally but its contents are not included in this prompt yet."
        case .unsupported:
            return "Text extraction is unsupported or no extractor is currently available; the original file is saved locally but its contents are not included in this prompt."
        case .failed:
            let details = manifest.extractionReports.last?.errors.joined(separator: " ") ?? "unknown error"
            return "Text extraction failed (\(details)); the original file is saved locally but its contents are not included in this prompt."
        case .skippedOversize:
            return "Text extraction was skipped because the attachment is too large; the original file is saved locally but its contents are not included in this prompt."
        case .extracted:
            return "No extracted text file is available even though extraction is marked complete."
        }
    }
}
