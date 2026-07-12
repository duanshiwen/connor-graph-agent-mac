import Foundation

public enum NoteImportSourceKind: String, Codable, Sendable, CaseIterable, Hashable {
    case markdownFolder = "markdown_folder"
    case obsidianVault = "obsidian_vault"
    case notionExport = "notion_export"
    case evernoteENEX = "evernote_enex"
}

public enum NoteImportJobStatus: String, Codable, Sendable, CaseIterable, Hashable {
    case created
    case scanning
    case awaitingReview = "awaiting_review"
    case ready
    case importing
    case processing
    case paused
    case cancelling
    case cancelled
    case completedWithIssues = "completed_with_issues"
    case completed
    case failed

    public var isTerminal: Bool {
        switch self {
        case .cancelled, .completedWithIssues, .completed, .failed: true
        default: false
        }
    }
}

public enum NoteImportItemStatus: String, Codable, Sendable, CaseIterable, Hashable {
    case discovered
    case validating
    case needsEncodingReview = "needs_encoding_review"
    case ready
    case duplicateUnchanged = "duplicate_unchanged"
    case duplicateChanged = "duplicate_changed"
    case creatingSession = "creating_session"
    case imported
    case queuedForLLM = "queued_for_llm"
    case runningLLM = "running_llm"
    case completed
    case parseFailed = "parse_failed"
    case sessionFailed = "session_failed"
    case attachmentFailed = "attachment_failed"
    case llmFailed = "llm_failed"
    case cancelled

    public var isTerminal: Bool {
        switch self {
        case .duplicateUnchanged, .completed, .parseFailed, .sessionFailed, .attachmentFailed, .llmFailed, .cancelled: true
        default: false
        }
    }
}

public enum NoteImportErrorCode: String, Codable, Sendable, CaseIterable, Hashable, Error {
    case sourceAccessDenied = "source_access_denied"
    case sourceUnavailable = "source_unavailable"
    case unsafePath = "unsafe_path"
    case archiveLimitExceeded = "archive_limit_exceeded"
    case unsupportedFormat = "unsupported_format"
    case binaryFile = "binary_file"
    case decodingAmbiguous = "decoding_ambiguous"
    case decodingFailed = "decoding_failed"
    case lossyDecodingRequiresApproval = "lossy_decoding_requires_approval"
    case parseFailed = "parse_failed"
    case attachmentMissing = "attachment_missing"
    case attachmentHashMismatch = "attachment_hash_mismatch"
    case insufficientDiskSpace = "insufficient_disk_space"
    case duplicateIdentity = "duplicate_identity"
    case sessionCreationFailed = "session_creation_failed"
    case llmUnavailable = "llm_unavailable"
    case llmRateLimited = "llm_rate_limited"
    case llmContextExceeded = "llm_context_exceeded"
    case cancelled
    case internalInvariantViolation = "internal_invariant_violation"
}

public enum NoteImportDuplicatePolicy: String, Codable, Sendable, CaseIterable, Hashable {
    case skipUnchanged = "skip_unchanged"
    case appendUpdate = "append_update"
    case createCopy = "create_copy"
}

public enum NoteImportLLMMode: String, Codable, Sendable, CaseIterable, Hashable {
    case disabled
    case automatic
}

public struct NoteImportOptions: Codable, Sendable, Equatable {
    public var recursivelyScan: Bool
    public var importAttachments: Bool
    public var preserveHierarchy: Bool
    public var duplicatePolicy: NoteImportDuplicatePolicy
    public var llmMode: NoteImportLLMMode
    public var llmConcurrency: Int
    public var allowNetworkReadTools: Bool
    public var allowLossyDecoding: Bool
    public var defaultEncodingName: String?
    public var ignoredPathPatterns: [String]

    public init(
        recursivelyScan: Bool = true,
        importAttachments: Bool = true,
        preserveHierarchy: Bool = true,
        duplicatePolicy: NoteImportDuplicatePolicy = .skipUnchanged,
        llmMode: NoteImportLLMMode = .automatic,
        llmConcurrency: Int = 1,
        allowNetworkReadTools: Bool = false,
        allowLossyDecoding: Bool = false,
        defaultEncodingName: String? = nil,
        ignoredPathPatterns: [String] = []
    ) {
        self.recursivelyScan = recursivelyScan
        self.importAttachments = importAttachments
        self.preserveHierarchy = preserveHierarchy
        self.duplicatePolicy = duplicatePolicy
        self.llmMode = llmMode
        self.llmConcurrency = min(max(llmConcurrency, 1), 3)
        self.allowNetworkReadTools = allowNetworkReadTools
        self.allowLossyDecoding = allowLossyDecoding
        self.defaultEncodingName = defaultEncodingName
        self.ignoredPathPatterns = ignoredPathPatterns
    }
}

public struct NoteImportDiagnostic: Codable, Sendable, Equatable, Identifiable {
    public enum Severity: String, Codable, Sendable, CaseIterable, Hashable {
        case info
        case warning
        case error
    }

    public var id: String
    public var code: NoteImportErrorCode?
    public var severity: Severity
    public var message: String
    public var metadata: [String: String]

    public init(id: String = UUID().uuidString, code: NoteImportErrorCode? = nil, severity: Severity, message: String, metadata: [String: String] = [:]) {
        self.id = id
        self.code = code
        self.severity = severity
        self.message = message
        self.metadata = metadata
    }
}

public struct ImportedNoteAttachment: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var sourcePath: String?
    public var displayName: String
    public var mimeType: String?
    public var byteCount: Int64?
    public var contentHash: String?
    public var metadata: [String: String]

    public init(id: String = UUID().uuidString, sourcePath: String? = nil, displayName: String, mimeType: String? = nil, byteCount: Int64? = nil, contentHash: String? = nil, metadata: [String: String] = [:]) {
        self.id = id
        self.sourcePath = sourcePath
        self.displayName = displayName
        self.mimeType = mimeType
        self.byteCount = byteCount
        self.contentHash = contentHash
        self.metadata = metadata
    }
}

public struct ImportedNoteLink: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable, Hashable {
        case internalNote = "internal_note"
        case attachment
        case externalURL = "external_url"
        case unresolved
    }

    public var id: String
    public var kind: Kind
    public var rawTarget: String
    public var resolvedSourceIdentity: String?
    public var metadata: [String: String]

    public init(id: String = UUID().uuidString, kind: Kind, rawTarget: String, resolvedSourceIdentity: String? = nil, metadata: [String: String] = [:]) {
        self.id = id
        self.kind = kind
        self.rawTarget = rawTarget
        self.resolvedSourceIdentity = resolvedSourceIdentity
        self.metadata = metadata
    }
}

public struct ImportedNote: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var sourceKind: NoteImportSourceKind
    public var sourceIdentity: String
    public var externalID: String?
    public var sourcePath: String?
    public var relativePath: String?
    public var title: String
    public var markdownContent: String
    public var createdAt: Date?
    public var updatedAt: Date?
    public var tags: [String]
    public var hierarchy: [String]
    public var links: [ImportedNoteLink]
    public var attachments: [ImportedNoteAttachment]
    public var sourceMetadata: [String: String]
    public var rawByteHash: String
    public var normalizedTextHash: String
    public var diagnostics: [NoteImportDiagnostic]

    public init(
        id: String = UUID().uuidString,
        sourceKind: NoteImportSourceKind,
        sourceIdentity: String,
        externalID: String? = nil,
        sourcePath: String? = nil,
        relativePath: String? = nil,
        title: String,
        markdownContent: String,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        tags: [String] = [],
        hierarchy: [String] = [],
        links: [ImportedNoteLink] = [],
        attachments: [ImportedNoteAttachment] = [],
        sourceMetadata: [String: String] = [:],
        rawByteHash: String,
        normalizedTextHash: String,
        diagnostics: [NoteImportDiagnostic] = []
    ) {
        self.id = id
        self.sourceKind = sourceKind
        self.sourceIdentity = sourceIdentity
        self.externalID = externalID
        self.sourcePath = sourcePath
        self.relativePath = relativePath
        self.title = title
        self.markdownContent = markdownContent
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tags = tags
        self.hierarchy = hierarchy
        self.links = links
        self.attachments = attachments
        self.sourceMetadata = sourceMetadata
        self.rawByteHash = rawByteHash
        self.normalizedTextHash = normalizedTextHash
        self.diagnostics = diagnostics
    }
}

public struct NoteImportScanRequest: Sendable, Equatable {
    public var sourceID: String
    public var sourceURL: URL
    public var kind: NoteImportSourceKind
    public var options: NoteImportOptions

    public init(sourceID: String, sourceURL: URL, kind: NoteImportSourceKind, options: NoteImportOptions) {
        self.sourceID = sourceID
        self.sourceURL = sourceURL
        self.kind = kind
        self.options = options
    }
}

public protocol NoteImportSourceAdapter: Sendable {
    var sourceKind: NoteImportSourceKind { get }
    func scan(_ request: NoteImportScanRequest) -> AsyncThrowingStream<ImportedNote, Error>
}

public struct HeadlessNoteSessionRunRequest: Sendable, Equatable {
    public var sessionID: String
    public var prompt: String
    public var displayPrompt: String?
    public var attachmentIDs: [String]
    public var allowNetworkReadTools: Bool

    public init(sessionID: String, prompt: String, displayPrompt: String? = nil, attachmentIDs: [String] = [], allowNetworkReadTools: Bool = false) {
        self.sessionID = sessionID
        self.prompt = prompt
        self.displayPrompt = displayPrompt
        self.attachmentIDs = attachmentIDs
        self.allowNetworkReadTools = allowNetworkReadTools
    }
}

public struct HeadlessNoteSessionRunResult: Sendable, Equatable {
    public var sessionID: String
    public var runID: String?
    public var responseText: String?

    public init(sessionID: String, runID: String? = nil, responseText: String? = nil) {
        self.sessionID = sessionID
        self.runID = runID
        self.responseText = responseText
    }
}

public protocol HeadlessNoteSessionRunning: Sendable {
    func run(_ request: HeadlessNoteSessionRunRequest) async throws -> HeadlessNoteSessionRunResult
    func cancel(sessionID: String) async
}

public enum NoteImportStateTransitionError: Error, Sendable, Equatable {
    case invalidJobTransition(from: NoteImportJobStatus, to: NoteImportJobStatus)
    case invalidItemTransition(from: NoteImportItemStatus, to: NoteImportItemStatus)
}

public struct NoteImportStateMachine: Sendable {
    public init() {}

    public func validate(jobFrom source: NoteImportJobStatus, to target: NoteImportJobStatus) throws {
        guard Self.jobTransitions[source, default: []].contains(target) else {
            throw NoteImportStateTransitionError.invalidJobTransition(from: source, to: target)
        }
    }

    public func validate(itemFrom source: NoteImportItemStatus, to target: NoteImportItemStatus) throws {
        guard Self.itemTransitions[source, default: []].contains(target) else {
            throw NoteImportStateTransitionError.invalidItemTransition(from: source, to: target)
        }
    }

    private static let jobTransitions: [NoteImportJobStatus: Set<NoteImportJobStatus>] = [
        .created: [.scanning, .cancelled, .failed],
        .scanning: [.awaitingReview, .paused, .cancelling, .failed],
        .awaitingReview: [.ready, .scanning, .cancelled, .failed],
        .ready: [.importing, .cancelled, .failed],
        .importing: [.processing, .paused, .cancelling, .completedWithIssues, .completed, .failed],
        .processing: [.paused, .cancelling, .completedWithIssues, .completed, .failed],
        .paused: [.scanning, .importing, .processing, .cancelling, .cancelled, .failed],
        .cancelling: [.cancelled, .completedWithIssues, .failed]
    ]

    private static let itemTransitions: [NoteImportItemStatus: Set<NoteImportItemStatus>] = [
        .discovered: [.validating, .cancelled],
        .validating: [.needsEncodingReview, .ready, .duplicateUnchanged, .duplicateChanged, .parseFailed, .cancelled],
        .needsEncodingReview: [.validating, .ready, .parseFailed, .cancelled],
        .ready: [.creatingSession, .cancelled],
        .duplicateChanged: [.creatingSession, .cancelled],
        .creatingSession: [.imported, .sessionFailed, .cancelled],
        .imported: [.queuedForLLM, .completed, .attachmentFailed, .cancelled],
        .queuedForLLM: [.runningLLM, .cancelled],
        .runningLLM: [.completed, .llmFailed, .cancelled],
        .llmFailed: [.queuedForLLM, .cancelled],
        .attachmentFailed: [.imported, .cancelled],
        .parseFailed: [.validating, .cancelled]
    ]
}
