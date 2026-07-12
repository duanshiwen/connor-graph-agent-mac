import Foundation
import ConnorGraphAgent
import ConnorGraphCore

public enum GeneratedMediaIngestionError: Error, Sendable, Equatable {
    case unsupportedMIMEType(String)
    case byteCountMismatch
    case fileTooLarge(Int64)
    case invalidSignature
}

public struct GeneratedMediaIngestionService: Sendable {
    public var store: AppSessionAttachmentStore
    public var maxImageBytes: Int64
    public var maxAudioBytes: Int64

    public init(store: AppSessionAttachmentStore, maxImageBytes: Int64 = 20_000_000, maxAudioBytes: Int64 = 50_000_000) {
        self.store = store
        self.maxImageBytes = maxImageBytes
        self.maxAudioBytes = maxAudioBytes
    }

    public func ingest(
        artifact: AgentGeneratedMediaArtifact,
        sessionID: String,
        now: Date = Date()
    ) throws -> AgentAttachmentManifest {
        defer { try? FileManager.default.removeItem(at: artifact.temporaryFileURL) }
        let actualBytes = try AppSessionAttachmentStore.byteCount(forItemAt: artifact.temporaryFileURL)
        guard actualBytes == artifact.byteCount else { throw GeneratedMediaIngestionError.byteCountMismatch }

        let targetExtension: String
        let limit: Int64
        switch artifact.mimeType.lowercased() {
        case "image/png": targetExtension = "png"; limit = maxImageBytes
        case "image/jpeg": targetExtension = "jpg"; limit = maxImageBytes
        case "image/webp": targetExtension = "webp"; limit = maxImageBytes
        case "audio/wav": targetExtension = "wav"; limit = maxAudioBytes
        case "audio/mpeg": targetExtension = "mp3"; limit = maxAudioBytes
        case "audio/mp4": targetExtension = "m4a"; limit = maxAudioBytes
        case "audio/aac": targetExtension = "aac"; limit = maxAudioBytes
        default: throw GeneratedMediaIngestionError.unsupportedMIMEType(artifact.mimeType)
        }
        guard actualBytes <= limit else { throw GeneratedMediaIngestionError.fileTooLarge(limit) }

        let stagedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("generated-\(UUID().uuidString).\(targetExtension)")
        defer { try? FileManager.default.removeItem(at: stagedURL) }
        try FileManager.default.copyItem(at: artifact.temporaryFileURL, to: stagedURL)
        do {
            return try store.importFile(
                at: stagedURL,
                sessionID: sessionID,
                now: now,
                origin: .modelGenerated,
                generationMetadata: artifact.generationMetadata
            )
        } catch let error as AppSessionAttachmentImportError {
            if case .rejected(_, .invalidMediaContainer) = error {
                throw GeneratedMediaIngestionError.invalidSignature
            }
            throw error
        }
    }
}
