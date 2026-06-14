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

public enum AgentAttachmentDerivativeKind: String, Codable, Sendable, Equatable {
    case extractedMarkdown
    case structuredJSON
    case pagesJSONL
    case mediaTranscript
    case preview
    case extractionReport
}

public enum AgentAttachmentExtractionEngine: String, Codable, Sendable, Equatable {
    case builtinText
    case markItDown
    case docling
    case providerNative
    case manual
    case unavailable
}

public enum AgentAttachmentProvider: String, Codable, Sendable, Equatable, CaseIterable {
    case openAI
    case claude
    case gemini
}

public enum AgentAttachmentRemoteFileStatus: String, Codable, Sendable, Equatable {
    case notUploaded
    case uploadPending
    case uploaded
    case uploadFailed
    case purgePending
    case purged
    case purgeFailed
    case expired
}

public enum AgentAttachmentAuditEventKind: String, Codable, Sendable, Equatable {
    case imported
    case extracted
    case providerUploadRequested
    case providerUploaded
    case providerUploadFailed
    case providerPurgeRequested
    case providerPurged
    case providerPurgeFailed
    case indexed
    case evidenceCandidateCreated
    case inspectorAction
}

public struct AgentAttachmentDerivativeRef: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var kind: AgentAttachmentDerivativeKind
    public var relativePath: String
    public var byteCount: Int64
    public var sha256: String?
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        kind: AgentAttachmentDerivativeKind,
        relativePath: String,
        byteCount: Int64,
        sha256: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.relativePath = relativePath
        self.byteCount = byteCount
        self.sha256 = sha256
        self.createdAt = createdAt
    }
}

public struct AgentAttachmentExtractionReport: Codable, Sendable, Equatable {
    public var attachmentID: String
    public var engine: AgentAttachmentExtractionEngine
    public var status: AgentAttachmentExtractionStatus
    public var capabilitiesUsed: [String]
    public var warnings: [String]
    public var errors: [String]
    public var derivativeRefs: [AgentAttachmentDerivativeRef]
    public var startedAt: Date
    public var completedAt: Date?

    public init(
        attachmentID: String,
        engine: AgentAttachmentExtractionEngine,
        status: AgentAttachmentExtractionStatus,
        capabilitiesUsed: [String] = [],
        warnings: [String] = [],
        errors: [String] = [],
        derivativeRefs: [AgentAttachmentDerivativeRef] = [],
        startedAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.attachmentID = attachmentID
        self.engine = engine
        self.status = status
        self.capabilitiesUsed = capabilitiesUsed
        self.warnings = warnings
        self.errors = errors
        self.derivativeRefs = derivativeRefs
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}

public struct AgentAttachmentRemoteFileRef: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var provider: AgentAttachmentProvider
    public var attachmentID: String
    public var remoteFileID: String?
    public var remoteURI: String?
    public var status: AgentAttachmentRemoteFileStatus
    public var uploadedAt: Date?
    public var expiresAt: Date?
    public var purgedAt: Date?
    public var retentionSummary: String
    public var zdrEligible: Bool?
    public var providerMetadata: [String: String]

    public init(
        id: String = UUID().uuidString,
        provider: AgentAttachmentProvider,
        attachmentID: String,
        remoteFileID: String? = nil,
        remoteURI: String? = nil,
        status: AgentAttachmentRemoteFileStatus = .notUploaded,
        uploadedAt: Date? = nil,
        expiresAt: Date? = nil,
        purgedAt: Date? = nil,
        retentionSummary: String,
        zdrEligible: Bool? = nil,
        providerMetadata: [String: String] = [:]
    ) {
        self.id = id
        self.provider = provider
        self.attachmentID = attachmentID
        self.remoteFileID = remoteFileID
        self.remoteURI = remoteURI
        self.status = status
        self.uploadedAt = uploadedAt
        self.expiresAt = expiresAt
        self.purgedAt = purgedAt
        self.retentionSummary = retentionSummary
        self.zdrEligible = zdrEligible
        self.providerMetadata = providerMetadata
    }
}

public struct AgentAttachmentAuditEvent: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var sessionID: String
    public var attachmentID: String
    public var kind: AgentAttachmentAuditEventKind
    public var summary: String
    public var metadata: [String: String]
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        sessionID: String,
        attachmentID: String,
        kind: AgentAttachmentAuditEventKind,
        summary: String,
        metadata: [String: String] = [:],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.attachmentID = attachmentID
        self.kind = kind
        self.summary = summary
        self.metadata = metadata
        self.createdAt = createdAt
    }
}

public struct AgentAttachmentEvidenceCandidate: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var sessionID: String
    public var messageID: String?
    public var attachmentID: String
    public var displayName: String
    public var sha256: String
    public var manifestRelativePath: String
    public var derivativeRelativePaths: [String]
    public var extractor: AgentAttachmentExtractionEngine
    public var summary: String
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        sessionID: String,
        messageID: String? = nil,
        attachmentID: String,
        displayName: String,
        sha256: String,
        manifestRelativePath: String,
        derivativeRelativePaths: [String] = [],
        extractor: AgentAttachmentExtractionEngine,
        summary: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.messageID = messageID
        self.attachmentID = attachmentID
        self.displayName = displayName
        self.sha256 = sha256
        self.manifestRelativePath = manifestRelativePath
        self.derivativeRelativePaths = derivativeRelativePaths
        self.extractor = extractor
        self.summary = summary
        self.createdAt = createdAt
    }
}

public struct AgentAttachmentSearchResult: Codable, Sendable, Equatable, Identifiable {
    public var id: String { attachmentID }
    public var attachmentID: String
    public var displayName: String
    public var snippet: String
    public var score: Double
    public var manifestRelativePath: String

    public init(attachmentID: String, displayName: String, snippet: String, score: Double, manifestRelativePath: String) {
        self.attachmentID = attachmentID
        self.displayName = displayName
        self.snippet = snippet
        self.score = score
        self.manifestRelativePath = manifestRelativePath
    }
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
    public var derivativeRefs: [AgentAttachmentDerivativeRef]
    public var extractionReports: [AgentAttachmentExtractionReport]
    public var remoteFileRefs: [AgentAttachmentRemoteFileRef]
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
        derivativeRefs: [AgentAttachmentDerivativeRef] = [],
        extractionReports: [AgentAttachmentExtractionReport] = [],
        remoteFileRefs: [AgentAttachmentRemoteFileRef] = [],
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
        self.derivativeRefs = derivativeRefs
        self.extractionReports = extractionReports
        self.remoteFileRefs = remoteFileRefs
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

    private enum CodingKeys: String, CodingKey {
        case id, displayName, originalFilename, normalizedFilename, kind, mimeType, fileExtension, byteCount, sha256
        case lifecycleStatus, extractionStatus, storedRelativePath, manifestRelativePath, extractedTextRelativePath, previewText
        case derivativeRefs, extractionReports, remoteFileRefs, createdAt, updatedAt, sourceDisplayPath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        originalFilename = try container.decode(String.self, forKey: .originalFilename)
        normalizedFilename = try container.decode(String.self, forKey: .normalizedFilename)
        kind = try container.decode(AgentAttachmentKind.self, forKey: .kind)
        mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
        fileExtension = try container.decodeIfPresent(String.self, forKey: .fileExtension)
        byteCount = try container.decode(Int64.self, forKey: .byteCount)
        sha256 = try container.decode(String.self, forKey: .sha256)
        lifecycleStatus = try container.decode(AgentAttachmentLifecycleStatus.self, forKey: .lifecycleStatus)
        extractionStatus = try container.decode(AgentAttachmentExtractionStatus.self, forKey: .extractionStatus)
        storedRelativePath = try container.decode(String.self, forKey: .storedRelativePath)
        manifestRelativePath = try container.decode(String.self, forKey: .manifestRelativePath)
        extractedTextRelativePath = try container.decodeIfPresent(String.self, forKey: .extractedTextRelativePath)
        previewText = try container.decodeIfPresent(String.self, forKey: .previewText)
        derivativeRefs = try container.decodeIfPresent([AgentAttachmentDerivativeRef].self, forKey: .derivativeRefs) ?? []
        extractionReports = try container.decodeIfPresent([AgentAttachmentExtractionReport].self, forKey: .extractionReports) ?? []
        remoteFileRefs = try container.decodeIfPresent([AgentAttachmentRemoteFileRef].self, forKey: .remoteFileRefs) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        sourceDisplayPath = try container.decodeIfPresent(String.self, forKey: .sourceDisplayPath)
    }
}
