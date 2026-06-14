import Foundation
import ConnorGraphCore

public struct AttachmentProviderCapability: Sendable, Equatable {
    public var provider: AgentAttachmentProvider
    public var supportedKinds: Set<AgentAttachmentKind>
    public var maxFileBytes: Int64
    public var supportsDelete: Bool
    public var retentionSummary: String
    public var zdrEligible: Bool?

    public init(provider: AgentAttachmentProvider, supportedKinds: Set<AgentAttachmentKind>, maxFileBytes: Int64, supportsDelete: Bool, retentionSummary: String, zdrEligible: Bool?) {
        self.provider = provider
        self.supportedKinds = supportedKinds
        self.maxFileBytes = maxFileBytes
        self.supportsDelete = supportsDelete
        self.retentionSummary = retentionSummary
        self.zdrEligible = zdrEligible
    }

    public func supports(_ manifest: AgentAttachmentManifest) -> Bool {
        supportedKinds.contains(manifest.kind) && manifest.byteCount <= maxFileBytes
    }
}

public struct AttachmentProviderRoutingDecision: Sendable, Equatable {
    public enum Mode: Sendable, Equatable { case inlineLocal, providerNative, rejected }
    public var mode: Mode
    public var provider: AgentAttachmentProvider?
    public var reason: String

    public init(mode: Mode, provider: AgentAttachmentProvider? = nil, reason: String) {
        self.mode = mode
        self.provider = provider
        self.reason = reason
    }
}

public struct AttachmentProviderRoutingPolicy: Sendable {
    public var capabilities: [AgentAttachmentProvider: AttachmentProviderCapability]

    public init(capabilities: [AgentAttachmentProvider: AttachmentProviderCapability] = Self.defaultCapabilities) {
        self.capabilities = capabilities
    }

    public func decide(manifest: AgentAttachmentManifest, preferredProvider: AgentAttachmentProvider?, allowRemoteUpload: Bool) -> AttachmentProviderRoutingDecision {
        guard allowRemoteUpload else {
            return AttachmentProviderRoutingDecision(mode: .inlineLocal, reason: "Remote provider upload disabled; using local extracted context")
        }
        let candidates = preferredProvider.map { [$0] } ?? [.openAI, .gemini, .claude]
        for provider in candidates {
            guard let capability = capabilities[provider] else { continue }
            if capability.supports(manifest) {
                return AttachmentProviderRoutingDecision(mode: .providerNative, provider: provider, reason: "\(provider.rawValue) supports \(manifest.kind.rawValue) within file limit")
            }
        }
        return AttachmentProviderRoutingDecision(mode: .inlineLocal, reason: "No provider-native file route supports this attachment; using local extracted context")
    }

    public static let defaultCapabilities: [AgentAttachmentProvider: AttachmentProviderCapability] = [
        .openAI: AttachmentProviderCapability(
            provider: .openAI,
            supportedKinds: [.pdf, .text, .markdown, .json, .csv, .html, .code, .document, .spreadsheet],
            maxFileBytes: 50_000_000,
            supportsDelete: true,
            retentionSummary: "OpenAI Files API lifecycle governed by uploaded file purpose and explicit delete where supported",
            zdrEligible: nil
        ),
        .claude: AttachmentProviderCapability(
            provider: .claude,
            supportedKinds: [.pdf, .text, .image],
            maxFileBytes: 50_000_000,
            supportsDelete: true,
            retentionSummary: "Claude Files API beta retains uploaded files until explicit deletion; not ZDR eligible",
            zdrEligible: false
        ),
        .gemini: AttachmentProviderCapability(
            provider: .gemini,
            supportedKinds: [.pdf, .text, .markdown, .json, .csv, .html, .code, .document, .spreadsheet, .image, .audio, .video],
            maxFileBytes: 2_000_000_000,
            supportsDelete: true,
            retentionSummary: "Gemini Files API files expire after 48 hours or can be manually deleted; project storage limit applies",
            zdrEligible: nil
        )
    ]
}

public struct AttachmentProviderUploadRequest: Sendable, Equatable {
    public var manifest: AgentAttachmentManifest
    public var fileURL: URL
    public var mimeType: String?

    public init(manifest: AgentAttachmentManifest, fileURL: URL, mimeType: String? = nil) {
        self.manifest = manifest
        self.fileURL = fileURL
        self.mimeType = mimeType
    }
}

public protocol AttachmentProviderFileAdapter: Sendable {
    var provider: AgentAttachmentProvider { get }
    var capability: AttachmentProviderCapability { get }
    func buildUploadDescription(_ request: AttachmentProviderUploadRequest) -> [String: String]
    func buildPromptReference(remoteRef: AgentAttachmentRemoteFileRef, manifest: AgentAttachmentManifest) -> [String: String]
    func makeUploadedRef(attachmentID: String, remoteID: String, remoteURI: String?, now: Date) -> AgentAttachmentRemoteFileRef
    func makePurgedRef(_ ref: AgentAttachmentRemoteFileRef, now: Date) -> AgentAttachmentRemoteFileRef
}

public struct OpenAIAttachmentFileAdapter: AttachmentProviderFileAdapter {
    public var provider: AgentAttachmentProvider { .openAI }
    public var capability: AttachmentProviderCapability { AttachmentProviderRoutingPolicy.defaultCapabilities[.openAI]! }
    public init() {}
    public func buildUploadDescription(_ request: AttachmentProviderUploadRequest) -> [String: String] {
        ["endpoint": "/v1/files", "purpose": "user_data", "filename": request.manifest.normalizedFilename, "mimeType": request.mimeType ?? request.manifest.mimeType ?? "application/octet-stream"]
    }
    public func buildPromptReference(remoteRef: AgentAttachmentRemoteFileRef, manifest: AgentAttachmentManifest) -> [String: String] {
        ["api": "responses", "type": "input_file", "file_id": remoteRef.remoteFileID ?? "", "filename": manifest.displayName]
    }
    public func makeUploadedRef(attachmentID: String, remoteID: String, remoteURI: String?, now: Date) -> AgentAttachmentRemoteFileRef {
        AgentAttachmentRemoteFileRef(provider: .openAI, attachmentID: attachmentID, remoteFileID: remoteID, remoteURI: remoteURI, status: .uploaded, uploadedAt: now, retentionSummary: capability.retentionSummary, zdrEligible: capability.zdrEligible)
    }
    public func makePurgedRef(_ ref: AgentAttachmentRemoteFileRef, now: Date) -> AgentAttachmentRemoteFileRef {
        var copy = ref; copy.status = .purged; copy.purgedAt = now; return copy
    }
}

public struct ClaudeAttachmentFileAdapter: AttachmentProviderFileAdapter {
    public var provider: AgentAttachmentProvider { .claude }
    public var capability: AttachmentProviderCapability { AttachmentProviderRoutingPolicy.defaultCapabilities[.claude]! }
    public init() {}
    public func buildUploadDescription(_ request: AttachmentProviderUploadRequest) -> [String: String] {
        ["endpoint": "/v1/files", "beta": "files-api-2025-04-14", "filename": request.manifest.normalizedFilename, "mimeType": request.mimeType ?? request.manifest.mimeType ?? "application/octet-stream"]
    }
    public func buildPromptReference(remoteRef: AgentAttachmentRemoteFileRef, manifest: AgentAttachmentManifest) -> [String: String] {
        let type = manifest.kind == .image ? "image" : "document"
        return ["api": "messages", "contentBlockType": type, "sourceType": "file", "file_id": remoteRef.remoteFileID ?? "", "zdrEligible": "false"]
    }
    public func makeUploadedRef(attachmentID: String, remoteID: String, remoteURI: String?, now: Date) -> AgentAttachmentRemoteFileRef {
        AgentAttachmentRemoteFileRef(provider: .claude, attachmentID: attachmentID, remoteFileID: remoteID, remoteURI: remoteURI, status: .uploaded, uploadedAt: now, retentionSummary: capability.retentionSummary, zdrEligible: false, providerMetadata: ["beta": "files-api-2025-04-14"])
    }
    public func makePurgedRef(_ ref: AgentAttachmentRemoteFileRef, now: Date) -> AgentAttachmentRemoteFileRef {
        var copy = ref; copy.status = .purged; copy.purgedAt = now; return copy
    }
}

public struct GeminiAttachmentFileAdapter: AttachmentProviderFileAdapter {
    public var provider: AgentAttachmentProvider { .gemini }
    public var capability: AttachmentProviderCapability { AttachmentProviderRoutingPolicy.defaultCapabilities[.gemini]! }
    public init() {}
    public func buildUploadDescription(_ request: AttachmentProviderUploadRequest) -> [String: String] {
        ["endpoint": "/upload/v1beta/files", "protocol": "resumable", "filename": request.manifest.normalizedFilename, "mimeType": request.mimeType ?? request.manifest.mimeType ?? "application/octet-stream"]
    }
    public func buildPromptReference(remoteRef: AgentAttachmentRemoteFileRef, manifest: AgentAttachmentManifest) -> [String: String] {
        ["api": "generateContent", "part": "file_data", "file_uri": remoteRef.remoteURI ?? "", "mime_type": manifest.mimeType ?? "application/octet-stream"]
    }
    public func makeUploadedRef(attachmentID: String, remoteID: String, remoteURI: String?, now: Date) -> AgentAttachmentRemoteFileRef {
        AgentAttachmentRemoteFileRef(provider: .gemini, attachmentID: attachmentID, remoteFileID: remoteID, remoteURI: remoteURI, status: .uploaded, uploadedAt: now, expiresAt: now.addingTimeInterval(48 * 60 * 60), retentionSummary: capability.retentionSummary, zdrEligible: capability.zdrEligible)
    }
    public func makePurgedRef(_ ref: AgentAttachmentRemoteFileRef, now: Date) -> AgentAttachmentRemoteFileRef {
        var copy = ref; copy.status = .purged; copy.purgedAt = now; return copy
    }
}
