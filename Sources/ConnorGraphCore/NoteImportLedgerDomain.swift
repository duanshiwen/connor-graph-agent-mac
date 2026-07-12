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
    public var pauseRequestedAt: Date?
    public var cancelRequestedAt: Date?
    public var lastHeartbeatAt: Date?
    public var resumedAt: Date?
    public var schedulerVersion: String?

    public init(id: String = UUID().uuidString, sourceID: String, status: NoteImportJobStatus = .created, options: NoteImportOptions = .init(), discoveredCount: Int = 0, importedCount: Int = 0, duplicateCount: Int = 0, failedCount: Int = 0, createdAt: Date = Date(), updatedAt: Date = Date(), startedAt: Date? = nil, completedAt: Date? = nil, errorCode: NoteImportErrorCode? = nil, errorMessage: String? = nil, pauseRequestedAt: Date? = nil, cancelRequestedAt: Date? = nil, lastHeartbeatAt: Date? = nil, resumedAt: Date? = nil, schedulerVersion: String? = nil) {
        self.id = id; self.sourceID = sourceID; self.status = status; self.options = options; self.discoveredCount = discoveredCount; self.importedCount = importedCount; self.duplicateCount = duplicateCount; self.failedCount = failedCount; self.createdAt = createdAt; self.updatedAt = updatedAt; self.startedAt = startedAt; self.completedAt = completedAt; self.errorCode = errorCode; self.errorMessage = errorMessage; self.pauseRequestedAt = pauseRequestedAt; self.cancelRequestedAt = cancelRequestedAt; self.lastHeartbeatAt = lastHeartbeatAt; self.resumedAt = resumedAt; self.schedulerVersion = schedulerVersion
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
    public var nextRetryAt: Date?
    public var lastAttemptAt: Date?
    public var leaseOwner: String?
    public var leaseExpiresAt: Date?
    public var sourceRevision: String?
    public var errorCode: NoteImportErrorCode?
    public var errorMessage: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var metadata: [String: String]

    public init(id: String = UUID().uuidString, jobID: String, sourceID: String, sourceIdentity: String, externalID: String? = nil, relativePath: String? = nil, title: String, status: NoteImportItemStatus = .discovered, sessionID: String? = nil, rawByteHash: String, normalizedTextHash: String, sourceEncoding: String? = nil, encodingConfidence: Double? = nil, decoderVersion: String? = nil, attemptCount: Int = 0, nextRetryAt: Date? = nil, lastAttemptAt: Date? = nil, leaseOwner: String? = nil, leaseExpiresAt: Date? = nil, sourceRevision: String? = nil, errorCode: NoteImportErrorCode? = nil, errorMessage: String? = nil, createdAt: Date = Date(), updatedAt: Date = Date(), metadata: [String: String] = [:]) {
        self.id = id; self.jobID = jobID; self.sourceID = sourceID; self.sourceIdentity = sourceIdentity; self.externalID = externalID; self.relativePath = relativePath; self.title = title; self.status = status; self.sessionID = sessionID; self.rawByteHash = rawByteHash; self.normalizedTextHash = normalizedTextHash; self.sourceEncoding = sourceEncoding; self.encodingConfidence = encodingConfidence; self.decoderVersion = decoderVersion; self.attemptCount = attemptCount; self.nextRetryAt = nextRetryAt; self.lastAttemptAt = lastAttemptAt; self.leaseOwner = leaseOwner; self.leaseExpiresAt = leaseExpiresAt; self.sourceRevision = sourceRevision; self.errorCode = errorCode; self.errorMessage = errorMessage; self.createdAt = createdAt; self.updatedAt = updatedAt; self.metadata = metadata
    }
}
