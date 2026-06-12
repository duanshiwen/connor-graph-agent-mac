import Foundation

public enum ClaudeSDKSidecarRuntimeStatus: String, Codable, Sendable, Equatable {
    case idle
    case starting
    case running
    case ready
    case permissionPending
    case failed
    case cancelled
}

public struct ClaudeSDKSidecarRuntimeRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String { connorSessionID }
    public var connorSessionID: String
    public var groupID: String
    public var sdkSessionID: String?
    public var lastRunID: String?
    public var status: ClaudeSDKSidecarRuntimeStatus
    public var pendingApprovalRequestID: String?
    public var lastError: String?
    public var protocolVersion: Int
    public var sdkCWD: String?
    public var sdkSessionStoreHint: String?
    public var forkedFromSDKSessionID: String?
    public var lastHeartbeatAt: Date?
    public var lastDiagnosticMessage: String?
    public var failureCode: ClaudeSDKSidecarFailureCode?
    public var recoverability: ClaudeSDKSidecarRecoverability?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        connorSessionID: String,
        groupID: String,
        sdkSessionID: String? = nil,
        lastRunID: String? = nil,
        status: ClaudeSDKSidecarRuntimeStatus = .idle,
        pendingApprovalRequestID: String? = nil,
        lastError: String? = nil,
        protocolVersion: Int = 2,
        sdkCWD: String? = nil,
        sdkSessionStoreHint: String? = nil,
        forkedFromSDKSessionID: String? = nil,
        lastHeartbeatAt: Date? = nil,
        lastDiagnosticMessage: String? = nil,
        failureCode: ClaudeSDKSidecarFailureCode? = nil,
        recoverability: ClaudeSDKSidecarRecoverability? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.connorSessionID = connorSessionID
        self.groupID = groupID
        self.sdkSessionID = sdkSessionID
        self.lastRunID = lastRunID
        self.status = status
        self.pendingApprovalRequestID = pendingApprovalRequestID
        self.lastError = lastError
        self.protocolVersion = protocolVersion
        self.sdkCWD = sdkCWD
        self.sdkSessionStoreHint = sdkSessionStoreHint
        self.forkedFromSDKSessionID = forkedFromSDKSessionID
        self.lastHeartbeatAt = lastHeartbeatAt
        self.lastDiagnosticMessage = lastDiagnosticMessage
        self.failureCode = failureCode
        self.recoverability = recoverability
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum ClaudeSDKSidecarRuntimeHealth: String, Codable, Sendable, Equatable {
    case healthy
    case starting
    case waitingForApproval
    case failed
    case cancelled
    case unknown
}

public struct ClaudeSDKSidecarRuntimeDiagnostics: Codable, Sendable, Equatable {
    public var record: ClaudeSDKSidecarRuntimeRecord
    public var health: ClaudeSDKSidecarRuntimeHealth
    public var message: String

    public init(record: ClaudeSDKSidecarRuntimeRecord) {
        self.record = record
        switch record.status {
        case .ready, .running:
            self.health = record.sdkSessionID == nil ? .unknown : .healthy
        case .starting:
            self.health = .starting
        case .permissionPending:
            self.health = .waitingForApproval
        case .failed:
            self.health = .failed
        case .cancelled:
            self.health = .cancelled
        case .idle:
            self.health = .unknown
        }
        self.message = Self.message(for: record, health: health)
    }

    private static func message(for record: ClaudeSDKSidecarRuntimeRecord, health: ClaudeSDKSidecarRuntimeHealth) -> String {
        switch health {
        case .healthy:
            return "Claude SDK sidecar session is ready for Connor resume."
        case .starting:
            return "Claude SDK sidecar session is starting."
        case .waitingForApproval:
            return "Claude SDK sidecar is waiting for Connor approval: \(record.pendingApprovalRequestID ?? "unknown")."
        case .failed:
            let code = record.failureCode?.rawValue ?? "unknown"
            let recoverability = record.recoverability?.rawValue ?? "unknown"
            return record.lastError ?? "Claude SDK sidecar runtime failed (code: \(code), recoverability: \(recoverability))."
        case .cancelled:
            return "Claude SDK sidecar runtime was cancelled."
        case .unknown:
            return "Claude SDK sidecar runtime status is unknown."
        }
    }
}

public struct AppClaudeSDKSidecarRuntimeStore: @unchecked Sendable {
    public var configDirectory: URL
    public var fileManager: FileManager
    public var filename: String

    public init(
        configDirectory: URL,
        fileManager: FileManager = .default,
        filename: String = "claude-sdk-sidecar-runtime.json"
    ) {
        self.configDirectory = configDirectory
        self.fileManager = fileManager
        self.filename = filename
    }

    public var fileURL: URL { configDirectory.appendingPathComponent(filename) }

    public func load(connorSessionID: String) throws -> ClaudeSDKSidecarRuntimeRecord? {
        try loadAll()[connorSessionID]
    }

    public func save(_ record: ClaudeSDKSidecarRuntimeRecord) throws {
        try fileManager.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        var all = try loadAll()
        var updated = record
        let existingCreatedAt = all[record.connorSessionID]?.createdAt
        updated.createdAt = existingCreatedAt ?? record.createdAt
        updated.updatedAt = Date()
        all[record.connorSessionID] = updated
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(all).write(to: fileURL, options: .atomic)
    }

    public func loadDiagnostics() throws -> [ClaudeSDKSidecarRuntimeDiagnostics] {
        try loadAll().values
            .sorted { $0.updatedAt > $1.updatedAt }
            .map(ClaudeSDKSidecarRuntimeDiagnostics.init(record:))
    }

    private func loadAll() throws -> [String: ClaudeSDKSidecarRuntimeRecord] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([String: ClaudeSDKSidecarRuntimeRecord].self, from: Data(contentsOf: fileURL))
    }
}
