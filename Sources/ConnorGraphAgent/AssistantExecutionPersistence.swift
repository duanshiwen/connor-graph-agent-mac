import Foundation
import ConnorGraphCore

public struct AssistantApprovalCheckpoint: Codable, Sendable, Equatable, Identifiable {
    public var id: String { request.id }
    public var envelope: AssistantRunEnvelope
    public var stage: AssistantRunStage
    public var call: AgentToolCall
    public var request: AgentPermissionRequest
    public var status: AgentPendingApprovalStatus
    public var effectKey: String
    public var updatedAt: Date

    public init(
        envelope: AssistantRunEnvelope,
        stage: AssistantRunStage = .waitingForApproval,
        call: AgentToolCall,
        request: AgentPermissionRequest,
        status: AgentPendingApprovalStatus = .pending,
        effectKey: String,
        updatedAt: Date = Date()
    ) {
        self.envelope = envelope
        self.stage = stage
        self.call = call
        self.request = request
        self.status = status
        self.effectKey = effectKey
        self.updatedAt = updatedAt
    }
}

public protocol AssistantRunCheckpointStore: Sendable {
    func save(_ checkpoint: AssistantApprovalCheckpoint) async throws
    func resolve(requestID: String, status: AgentPendingApprovalStatus) async throws
    func remove(requestID: String) async throws
    func pending() async throws -> [AssistantApprovalCheckpoint]
}

public actor InMemoryAssistantRunCheckpointStore: AssistantRunCheckpointStore {
    private var checkpoints: [String: AssistantApprovalCheckpoint] = [:]

    public init() {}

    public func save(_ checkpoint: AssistantApprovalCheckpoint) {
        checkpoints[checkpoint.request.id] = checkpoint
    }

    public func resolve(requestID: String, status: AgentPendingApprovalStatus) {
        guard var checkpoint = checkpoints[requestID] else { return }
        checkpoint.status = status
        checkpoint.updatedAt = Date()
        checkpoints[requestID] = checkpoint
    }

    public func remove(requestID: String) {
        checkpoints.removeValue(forKey: requestID)
    }

    public func pending() -> [AssistantApprovalCheckpoint] {
        checkpoints.values.filter { $0.status == .pending }.sorted { $0.updatedAt < $1.updatedAt }
    }
}

public actor FileAssistantRunCheckpointStore: AssistantRunCheckpointStore {
    private let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func save(_ checkpoint: AssistantApprovalCheckpoint) throws {
        var all = try load()
        all[checkpoint.request.id] = checkpoint
        try persist(all)
    }

    public func resolve(requestID: String, status: AgentPendingApprovalStatus) throws {
        var all = try load()
        guard var checkpoint = all[requestID] else { return }
        checkpoint.status = status
        checkpoint.updatedAt = Date()
        all[requestID] = checkpoint
        try persist(all)
    }

    public func remove(requestID: String) throws {
        var all = try load()
        all.removeValue(forKey: requestID)
        try persist(all)
    }

    public func pending() throws -> [AssistantApprovalCheckpoint] {
        try load().values.filter { $0.status == .pending }.sorted { $0.updatedAt < $1.updatedAt }
    }

    private func load() throws -> [String: AssistantApprovalCheckpoint] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [:] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([String: AssistantApprovalCheckpoint].self, from: data)
    }

    private func persist(_ value: [String: AssistantApprovalCheckpoint]) throws {
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(value)
        try data.write(to: fileURL, options: .atomic)
    }
}

public protocol AssistantEffectLedger: Sendable {
    func contains(_ key: String) async throws -> Bool
    func record(_ key: String) async throws
}

public actor InMemoryAssistantEffectLedger: AssistantEffectLedger {
    private var keys = Set<String>()

    public init() {}

    public func contains(_ key: String) -> Bool { keys.contains(key) }
    public func record(_ key: String) { keys.insert(key) }
}

public actor FileAssistantEffectLedger: AssistantEffectLedger {
    private let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func contains(_ key: String) throws -> Bool { try load().contains(key) }

    public func record(_ key: String) throws {
        var keys = try load()
        keys.insert(key)
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(keys).write(to: fileURL, options: .atomic)
    }

    private func load() throws -> Set<String> {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        return try JSONDecoder().decode(Set<String>.self, from: Data(contentsOf: fileURL))
    }
}

public enum AssistantEffectIdentity {
    public static func key(runID: String, call: AgentToolCall) -> String {
        let normalizedArguments: String
        if let data = call.argumentsJSON.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data),
           JSONSerialization.isValidJSONObject(object),
           let normalized = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
           let value = String(data: normalized, encoding: .utf8) {
            normalizedArguments = value
        } else {
            normalizedArguments = call.argumentsJSON
        }
        return "\(runID):\(call.name):\(fnv1a64(normalizedArguments))"
    }

    private static func fnv1a64(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

public extension AgentPermissionCapability {
    var assistantHasExternalSideEffect: Bool {
        switch self {
        case .readGraph, .readSession, .modelCall, .readBrowserPage,
             .readWorkspaceFile, .listWorkspaceFiles, .searchWorkspaceFiles,
             .computeScientific, .runReadOnlyShellCommand, .readMail, .readMailBody,
             .readContacts, .readCalendar, .readRSS, .readRSSContent, .exportRSSOPML:
            return false
        default:
            return true
        }
    }
}
