import Foundation

public struct NoteImportSourceRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var kind: NoteImportSourceKind
    public var displayName: String
    public var locationBookmark: Data?
    public var createdAt: Date
    public var metadata: [String: String]

    public init(id: String = UUID().uuidString, kind: NoteImportSourceKind, displayName: String, locationBookmark: Data? = nil, createdAt: Date = Date(), metadata: [String: String] = [:]) {
        self.id = id; self.kind = kind; self.displayName = displayName; self.locationBookmark = locationBookmark; self.createdAt = createdAt; self.metadata = metadata
    }
}

public struct NoteImportJobRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var sourceID: String
    public var status: NoteImportJobStatus
    public var options: NoteImportOptions
    public var discoveredCount: Int
    public var importedCount: Int
    public var duplicateCount: Int
    public var failedCount: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var startedAt: Date?
    public var completedAt: Date?
    public var errorCode: NoteImportErrorCode?
    public var errorMessage: String?

    public init(id: String = UUID().uuidString, sourceID: String, status: NoteImportJobStatus = .created, options: NoteImportOptions = .init(), discoveredCount: Int = 0, importedCount: Int = 0, duplicateCount: Int = 0, failedCount: Int = 0, createdAt: Date = Date(), updatedAt: Date = Date(), startedAt: Date? = nil, completedAt: Date? = nil, errorCode: NoteImportErrorCode? = nil, errorMessage: String? = nil) {
        self.id = id; self.sourceID = sourceID; self.status = status; self.options = options; self.discoveredCount = discoveredCount; self.importedCount = importedCount; self.duplicateCount = duplicateCount; self.failedCount = failedCount; self.createdAt = createdAt; self.updatedAt = updatedAt; self.startedAt = startedAt; self.completedAt = completedAt; self.errorCode = errorCode; self.errorMessage = errorMessage
    }
}

public struct NoteImportItemRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var jobID: String
    public var sourceID: String
    public var sourceIdentity: String
    public var externalID: String?
    public var relativePath: String?
    public var title: String
    public var status: NoteImportItemStatus
    public var sessionID: String?
    public var rawByteHash: String
    public var normalizedTextHash: String
    public var sourceEncoding: String?
    public var encodingConfidence: Double?
    public var decoderVersion: String?
    public var attemptCount: Int
    public var errorCode: NoteImportErrorCode?
    public var errorMessage: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var metadata: [String: String]

    public init(id: String = UUID().uuidString, jobID: String, sourceID: String, sourceIdentity: String, externalID: String? = nil, relativePath: String? = nil, title: String, status: NoteImportItemStatus = .discovered, sessionID: String? = nil, rawByteHash: String, normalizedTextHash: String, sourceEncoding: String? = nil, encodingConfidence: Double? = nil, decoderVersion: String? = nil, attemptCount: Int = 0, errorCode: NoteImportErrorCode? = nil, errorMessage: String? = nil, createdAt: Date = Date(), updatedAt: Date = Date(), metadata: [String: String] = [:]) {
        self.id = id; self.jobID = jobID; self.sourceID = sourceID; self.sourceIdentity = sourceIdentity; self.externalID = externalID; self.relativePath = relativePath; self.title = title; self.status = status; self.sessionID = sessionID; self.rawByteHash = rawByteHash; self.normalizedTextHash = normalizedTextHash; self.sourceEncoding = sourceEncoding; self.encodingConfidence = encodingConfidence; self.decoderVersion = decoderVersion; self.attemptCount = attemptCount; self.errorCode = errorCode; self.errorMessage = errorMessage; self.createdAt = createdAt; self.updatedAt = updatedAt; self.metadata = metadata
    }
}
