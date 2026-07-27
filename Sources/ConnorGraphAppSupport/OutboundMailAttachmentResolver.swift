import Foundation
import ConnorGraphCore

public protocol OutboundMailAttachmentResolving: Sendable {
    func resolve(ids: [MailAttachmentID], sessionID: String?) async throws -> [OutboundMailAttachment]
}

public struct AppSessionOutboundMailAttachmentResolver: OutboundMailAttachmentResolving, Sendable {
    public var store: AppSessionAttachmentStore
    public var maximumAttachmentBytes: Int64
    public var maximumTotalBytes: Int64

    public init(
        store: AppSessionAttachmentStore,
        maximumAttachmentBytes: Int64 = 25_000_000,
        maximumTotalBytes: Int64 = 50_000_000
    ) {
        self.store = store
        self.maximumAttachmentBytes = maximumAttachmentBytes
        self.maximumTotalBytes = maximumTotalBytes
    }

    public func resolve(ids: [MailAttachmentID], sessionID: String?) async throws -> [OutboundMailAttachment] {
        guard !ids.isEmpty else { return [] }
        guard let sessionID = sessionID?.trimmingCharacters(in: .whitespacesAndNewlines), !sessionID.isEmpty else {
            throw MailRuntimeError.attachmentSessionRequired
        }

        let sessionRoot = store.paths.sessionArtifactDirectories(sessionID: sessionID).root.standardizedFileURL
        var totalBytes: Int64 = 0
        var attachments: [OutboundMailAttachment] = []
        attachments.reserveCapacity(ids.count)

        for id in ids {
            guard !id.rawValue.isEmpty,
                  !id.rawValue.contains("/"),
                  !id.rawValue.contains("\\"),
                  !id.rawValue.contains("..") else {
                throw MailRuntimeError.invalidAttachment(id.rawValue)
            }
            let manifest: AgentAttachmentManifest
            do {
                manifest = try store.loadManifest(sessionID: sessionID, attachmentID: id.rawValue)
            } catch {
                throw MailRuntimeError.attachmentNotFound(id.rawValue)
            }
            guard manifest.id == id.rawValue, manifest.lifecycleStatus == .ready else {
                throw MailRuntimeError.attachmentNotReady(id.rawValue)
            }
            guard manifest.byteCount >= 0, manifest.byteCount <= maximumAttachmentBytes else {
                throw MailRuntimeError.attachmentTooLarge(id: id.rawValue, maximumBytes: maximumAttachmentBytes)
            }
            totalBytes += manifest.byteCount
            guard totalBytes <= maximumTotalBytes else {
                throw MailRuntimeError.attachmentsTooLarge(maximumBytes: maximumTotalBytes)
            }

            let fileURL = sessionRoot.appendingPathComponent(manifest.storedRelativePath).standardizedFileURL
            let sessionPrefix = sessionRoot.path.hasSuffix("/") ? sessionRoot.path : sessionRoot.path + "/"
            guard fileURL.path.hasPrefix(sessionPrefix) else {
                throw MailRuntimeError.invalidAttachment(id.rawValue)
            }
            let values: URLResourceValues
            do {
                values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            } catch {
                throw MailRuntimeError.attachmentNotFound(id.rawValue)
            }
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw MailRuntimeError.invalidAttachment(id.rawValue)
            }
            let actualByteCount = Int64(values.fileSize ?? 0)
            guard actualByteCount == manifest.byteCount, actualByteCount <= maximumAttachmentBytes else {
                throw MailRuntimeError.attachmentChanged(id.rawValue)
            }

            let data: Data
            do {
                data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            } catch {
                throw MailRuntimeError.invalidAttachment(id.rawValue)
            }
            guard AppSessionAttachmentStore.sha256Hex(data) == manifest.sha256 else {
                throw MailRuntimeError.attachmentChanged(id.rawValue)
            }
            attachments.append(OutboundMailAttachment(
                id: id,
                filename: manifest.displayName,
                mimeType: manifest.mimeType ?? "application/octet-stream",
                data: data,
                contentHash: manifest.sha256
            ))
        }
        return attachments
    }
}
