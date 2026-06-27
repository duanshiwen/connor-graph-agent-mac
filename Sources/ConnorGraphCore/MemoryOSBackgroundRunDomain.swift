import Foundation

public enum MemoryOSBackgroundRunStatus: String, Codable, Sendable, Equatable, CaseIterable {
    case running
    case succeeded
    case failed
}

public enum MemoryOSBackgroundMessageRole: String, Codable, Sendable, Equatable, CaseIterable {
    case system
    case user
    case assistant
    case tool
}

public enum MemoryOSBackgroundToolCallStatus: String, Codable, Sendable, Equatable, CaseIterable {
    case running
    case succeeded
    case failed
}

public struct MemoryOSBackgroundRunRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var queueItemID: String?
    public var kind: String
    public var source: String
    public var status: MemoryOSBackgroundRunStatus
    public var startedAt: Date
    public var finishedAt: Date?
    public var modelID: String?
    public var iterationCount: Int
    public var toolCallCount: Int
    public var statelessBatch: Bool
    public var errorCode: String?
    public var errorMessage: String?
    public var metadata: [String: String]

    public init(
        id: String = UUID().uuidString,
        queueItemID: String? = nil,
        kind: String,
        source: String,
        status: MemoryOSBackgroundRunStatus = .running,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        modelID: String? = nil,
        iterationCount: Int = 0,
        toolCallCount: Int = 0,
        statelessBatch: Bool = true,
        errorCode: String? = nil,
        errorMessage: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.queueItemID = queueItemID
        self.kind = kind
        self.source = source
        self.status = status
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.modelID = modelID
        self.iterationCount = iterationCount
        self.toolCallCount = toolCallCount
        self.statelessBatch = statelessBatch
        self.errorCode = errorCode
        self.errorMessage = errorMessage
        self.metadata = metadata
    }
}

public struct MemoryOSBackgroundMessageRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var runID: String
    public var sequence: Int
    public var role: MemoryOSBackgroundMessageRole
    public var content: String
    public var toolCallID: String?
    public var toolName: String?
    public var metadata: [String: String]

    public init(
        id: String = UUID().uuidString,
        runID: String,
        sequence: Int,
        role: MemoryOSBackgroundMessageRole,
        content: String,
        toolCallID: String? = nil,
        toolName: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.runID = runID
        self.sequence = sequence
        self.role = role
        self.content = content
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.metadata = metadata
    }
}

public struct MemoryOSBackgroundToolCallRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var runID: String
    public var iteration: Int
    public var toolName: String
    public var argumentsJSON: String
    public var resultJSON: String?
    public var status: MemoryOSBackgroundToolCallStatus
    public var startedAt: Date
    public var finishedAt: Date?
    public var errorMessage: String?
    public var metadata: [String: String]

    public init(
        id: String = UUID().uuidString,
        runID: String,
        iteration: Int,
        toolName: String,
        argumentsJSON: String,
        resultJSON: String? = nil,
        status: MemoryOSBackgroundToolCallStatus = .running,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        errorMessage: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.runID = runID
        self.iteration = iteration
        self.toolName = toolName
        self.argumentsJSON = argumentsJSON
        self.resultJSON = resultJSON
        self.status = status
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.errorMessage = errorMessage
        self.metadata = metadata
    }
}
