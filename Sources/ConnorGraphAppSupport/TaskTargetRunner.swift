import Foundation
import ConnorGraphCore

public struct TaskSessionMessageRequest: Sendable, Equatable {
    public var sessionID: String?
    public var title: String?
    public var message: String
    public var createNewSession: Bool
    public var runID: String?

    public init(sessionID: String? = nil, title: String? = nil, message: String, createNewSession: Bool, runID: String? = nil) {
        self.sessionID = sessionID
        self.title = title
        self.message = message
        self.createNewSession = createNewSession
        self.runID = runID
    }
}

public struct TaskTargetRunResult: Sendable, Equatable {
    public var summary: String

    public init(summary: String) {
        self.summary = summary
    }
}

public struct MemoryOSPipelineTaskRequest: Sendable, Equatable {
    public var operationName: String
    public var runID: String?

    public init(operationName: String, runID: String? = nil) {
        self.operationName = operationName
        self.runID = runID
    }
}

public struct SourceRefreshTaskRequest: Sendable, Equatable {
    public var sourceKind: String
    public var sourceInstanceID: String?
    public var runID: String?

    public init(sourceKind: String, sourceInstanceID: String? = nil, runID: String? = nil) {
        self.sourceKind = sourceKind
        self.sourceInstanceID = sourceInstanceID
        self.runID = runID
    }
}

public enum TaskTargetRunnerError: Error, Sendable, Equatable, CustomStringConvertible {
    case unsupportedTarget(String)
    case missingMessage(String)
    case missingSessionID(String)

    public var description: String {
        switch self {
        case .unsupportedTarget(let value): "unsupportedTarget: \(value)"
        case .missingMessage(let taskID): "missingMessage: \(taskID)"
        case .missingSessionID(let taskID): "missingSessionID: \(taskID)"
        }
    }
}

public struct TaskTargetRunner: Sendable {
    public typealias RefreshHandler = @Sendable (_ request: SourceRefreshTaskRequest) async throws -> String
    public typealias SessionMessageHandler = @Sendable (_ request: TaskSessionMessageRequest) async throws -> String
    public typealias MemoryOSPipelineHandler = @Sendable (_ request: MemoryOSPipelineTaskRequest) async throws -> String

    public var calendarRefresher: RefreshHandler
    public var rssRefresher: RefreshHandler
    public var sessionMessenger: SessionMessageHandler
    public var memoryOSPipelineRunner: MemoryOSPipelineHandler?

    public init(
        calendarRefresher: @escaping RefreshHandler,
        rssRefresher: @escaping RefreshHandler,
        sessionMessenger: @escaping SessionMessageHandler,
        memoryOSPipelineRunner: MemoryOSPipelineHandler? = nil
    ) {
        self.calendarRefresher = calendarRefresher
        self.rssRefresher = rssRefresher
        self.sessionMessenger = sessionMessenger
        self.memoryOSPipelineRunner = memoryOSPipelineRunner
    }


    public func run(task: ConnorTaskDefinition, runID: String? = nil, eventPayload: [String: String] = [:]) async throws -> TaskTargetRunResult {
        if task.target.targetKind == "source.runtime", task.target.operationName == "refresh" {
            let request = SourceRefreshTaskRequest(
                sourceKind: task.target.targetID,
                sourceInstanceID: sourceInstanceID(from: task.target.parameters),
                runID: runID
            )
            let summary: String
            switch task.target.targetID {
            case "calendar": summary = try await calendarRefresher(request)
            case "rss": summary = try await rssRefresher(request)
            default: throw TaskTargetRunnerError.unsupportedTarget(targetDescription(task))
            }
            return TaskTargetRunResult(summary: summary)
        }

        if task.target.targetKind == "memory_os.pipeline" {
            guard let memoryOSPipelineRunner else { throw TaskTargetRunnerError.unsupportedTarget(targetDescription(task)) }
            let summary = try await memoryOSPipelineRunner(MemoryOSPipelineTaskRequest(operationName: task.target.operationName, runID: runID))
            return TaskTargetRunResult(summary: summary)
        }

        if task.target.targetKind == "session.ai", task.target.operationName == "sendMessage" {
            guard let message = task.target.parameters["message"], !message.isEmpty else { throw TaskTargetRunnerError.missingMessage(task.id) }
            let sessionID = task.target.targetID.isEmpty ? eventPayload["sessionID"] : task.target.targetID
            guard let sessionID, !sessionID.isEmpty else { throw TaskTargetRunnerError.missingSessionID(task.id) }
            let summary = try await sessionMessenger(TaskSessionMessageRequest(sessionID: sessionID, message: message, createNewSession: false, runID: runID))
            return TaskTargetRunResult(summary: summary)
        }

        if task.target.targetKind == "session.ai", task.target.operationName == "createSessionAndSendMessage" {
            guard let message = task.target.parameters["message"], !message.isEmpty else { throw TaskTargetRunnerError.missingMessage(task.id) }
            let summary = try await sessionMessenger(TaskSessionMessageRequest(title: task.target.parameters["title"], message: message, createNewSession: true, runID: runID))
            return TaskTargetRunResult(summary: summary)
        }

        throw TaskTargetRunnerError.unsupportedTarget(targetDescription(task))
    }

    private func targetDescription(_ task: ConnorTaskDefinition) -> String {
        "\(task.target.targetKind):\(task.target.targetID).\(task.target.operationName)"
    }

    private func sourceInstanceID(from parameters: [String: String]) -> String? {
        ["sourceInstanceID", "sourceID", "accountID", "calendarAccountID"]
            .compactMap { parameters[$0]?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

public extension TaskTargetRunner {
    static func appRuntime(
        calendarRefresh: @escaping RefreshHandler,
        rssRefresh: @escaping RefreshHandler,
        sessionMessage: @escaping SessionMessageHandler,
        memoryOSPipeline: MemoryOSPipelineHandler? = nil
    ) -> TaskTargetRunner {
        TaskTargetRunner(calendarRefresher: calendarRefresh, rssRefresher: rssRefresh, sessionMessenger: sessionMessage, memoryOSPipelineRunner: memoryOSPipeline)
    }

}
