import Foundation

public enum AgentAttachmentKind: String, Codable, Sendable, Equatable {
    case text
    case code
    case markdown
    case json
    case csv
    case image
    case pdf
    case document
    case spreadsheet
    case archive
    case html
    case audio
    case video
    case unknown
}

public enum AgentAttachmentLifecycleStatus: String, Codable, Sendable, Equatable {
    case draft
    case importing
    case imported
    case stored
    case ready
    case failed
    case deleted
}

public enum AgentAttachmentExtractionStatus: String, Codable, Sendable, Equatable {
    case pending
    case extracted
    case unsupported
    case failed
    case skippedOversize
}

public struct AgentMessageAttachmentRef: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var displayName: String
    public var kind: AgentAttachmentKind
    public var byteCount: Int64
    public var lifecycleStatus: AgentAttachmentLifecycleStatus
    public var extractionStatus: AgentAttachmentExtractionStatus
    public var manifestRelativePath: String
    public var previewText: String?

    public init(
        id: String,
        displayName: String,
        kind: AgentAttachmentKind,
        byteCount: Int64,
        lifecycleStatus: AgentAttachmentLifecycleStatus,
        extractionStatus: AgentAttachmentExtractionStatus,
        manifestRelativePath: String,
        previewText: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.byteCount = byteCount
        self.lifecycleStatus = lifecycleStatus
        self.extractionStatus = extractionStatus
        self.manifestRelativePath = manifestRelativePath
        self.previewText = previewText
    }
}

public struct AgentAttachmentManifest: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var displayName: String
    public var originalFilename: String
    public var normalizedFilename: String
    public var kind: AgentAttachmentKind
    public var mimeType: String?
    public var fileExtension: String?
    public var byteCount: Int64
    public var sha256: String
    public var lifecycleStatus: AgentAttachmentLifecycleStatus
    public var extractionStatus: AgentAttachmentExtractionStatus
    public var storedRelativePath: String
    public var manifestRelativePath: String
    public var extractedTextRelativePath: String?
    public var previewText: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var sourceDisplayPath: String?

    public init(
        id: String,
        displayName: String,
        originalFilename: String,
        normalizedFilename: String,
        kind: AgentAttachmentKind,
        mimeType: String? = nil,
        fileExtension: String? = nil,
        byteCount: Int64,
        sha256: String,
        lifecycleStatus: AgentAttachmentLifecycleStatus,
        extractionStatus: AgentAttachmentExtractionStatus,
        storedRelativePath: String,
        manifestRelativePath: String,
        extractedTextRelativePath: String? = nil,
        previewText: String? = nil,
        createdAt: Date,
        updatedAt: Date,
        sourceDisplayPath: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.originalFilename = originalFilename
        self.normalizedFilename = normalizedFilename
        self.kind = kind
        self.mimeType = mimeType
        self.fileExtension = fileExtension
        self.byteCount = byteCount
        self.sha256 = sha256
        self.lifecycleStatus = lifecycleStatus
        self.extractionStatus = extractionStatus
        self.storedRelativePath = storedRelativePath
        self.manifestRelativePath = manifestRelativePath
        self.extractedTextRelativePath = extractedTextRelativePath
        self.previewText = previewText
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sourceDisplayPath = sourceDisplayPath
    }

    public var messageRef: AgentMessageAttachmentRef {
        AgentMessageAttachmentRef(
            id: id,
            displayName: displayName,
            kind: kind,
            byteCount: byteCount,
            lifecycleStatus: lifecycleStatus,
            extractionStatus: extractionStatus,
            manifestRelativePath: manifestRelativePath,
            previewText: previewText
        )
    }
}
