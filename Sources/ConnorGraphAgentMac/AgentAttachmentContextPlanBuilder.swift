import Foundation
import ConnorGraphAgent
import ConnorGraphAppSupport

struct AgentAttachmentContextPlanBuilder: Sendable {
    var storagePaths: AppStoragePaths?
    var perAttachmentCharacterLimit: Int = 20_000
    var totalCharacterLimit: Int = 60_000

    func build(sessionID: String, attachments: [AgentMessageAttachmentRef]) -> AttachmentContextPlan {
        guard !attachments.isEmpty, let storagePaths else { return AttachmentContextPlan() }
        let store = AppSessionAttachmentStore(paths: storagePaths)
        var inlineBlocks: [AttachmentInlineBlock] = []
        var imageBlocks: [AttachmentImageBlock] = []
        var omissions: [AttachmentOmission] = []
        var remainingBudget = totalCharacterLimit
        for attachment in attachments {
            guard remainingBudget > 0 else {
                omissions.append(AttachmentOmission(attachmentID: attachment.id, displayName: attachment.displayName, reason: "Total attachment prompt budget exhausted."))
                continue
            }
            do {
                let manifest = try store.loadManifest(sessionID: sessionID, attachmentID: attachment.id)
                if manifest.kind == .image {
                    let imageURL = storagePaths.sessionArtifactDirectories(sessionID: sessionID).root.appendingPathComponent(manifest.storedRelativePath)
                    let data = try Data(contentsOf: imageURL)
                    let mimeType = manifest.mimeType ?? "image/png"
                    let dataURL = "data:\(mimeType);base64,\(data.base64EncodedString())"
                    imageBlocks.append(AttachmentImageBlock(
                        attachmentID: manifest.id,
                        displayName: manifest.displayName,
                        mimeType: mimeType,
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
                let limit = min(perAttachmentCharacterLimit, remainingBudget)
                let isTruncated = content.count > limit
                let inlineContent = isTruncated ? String(content.prefix(limit)) : content
                remainingBudget -= inlineContent.count
                inlineBlocks.append(AttachmentInlineBlock(
                    attachmentID: manifest.id,
                    displayName: manifest.displayName,
                    kind: manifest.kind,
                    content: inlineContent,
                    sourceRelativePath: relativePath,
                    isTruncated: isTruncated
                ))
            } catch {
                omissions.append(AttachmentOmission(attachmentID: attachment.id, displayName: attachment.displayName, reason: "Failed to read extracted text: \(error)"))
            }
        }
        let estimatedTokens = max(1, inlineBlocks.reduce(0) { $0 + $1.content.count } / 4 + imageBlocks.count * 85)
        return AttachmentContextPlan(inlineBlocks: inlineBlocks, omittedAttachments: omissions, imageBlocks: imageBlocks, estimatedTokens: estimatedTokens)
    }

    static func attachmentOmissionReason(for manifest: AgentAttachmentManifest) -> String {
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
