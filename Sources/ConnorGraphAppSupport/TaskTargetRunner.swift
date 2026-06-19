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
    public typealias RefreshHandler = @Sendable (_ runID: String?) async throws -> String
    public typealias SessionMessageHandler = @Sendable (_ request: TaskSessionMessageRequest) async throws -> String

    public var mailRefresher: RefreshHandler
    public var calendarRefresher: RefreshHandler
    public var rssRefresher: RefreshHandler
    public var sessionMessenger: SessionMessageHandler

    public init(
        mailRefresher: @escaping RefreshHandler,
        calendarRefresher: @escaping RefreshHandler,
        rssRefresher: @escaping RefreshHandler,
        sessionMessenger: @escaping SessionMessageHandler
    ) {
        self.mailRefresher = mailRefresher
        self.calendarRefresher = calendarRefresher
        self.rssRefresher = rssRefresher
        self.sessionMessenger = sessionMessenger
    }

    public func run(task: ConnorTaskDefinition, runID: String? = nil, eventPayload: [String: String] = [:]) async throws -> TaskTargetRunResult {
        if task.target.targetKind == "source.runtime", task.target.operationName == "refresh" {
            let summary: String
            switch task.target.targetID {
            case "mail": summary = try await mailRefresher(runID)
            case "calendar": summary = try await calendarRefresher(runID)
            case "rss": summary = try await rssRefresher(runID)
            default: throw TaskTargetRunnerError.unsupportedTarget(targetDescription(task))
            }
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
}

public extension TaskTargetRunner {
    static func appRuntime(
        mailRefresh: @escaping RefreshHandler,
        calendarRefresh: @escaping RefreshHandler,
        rssRefresh: @escaping RefreshHandler,
        sessionMessage: @escaping SessionMessageHandler
    ) -> TaskTargetRunner {
        TaskTargetRunner(mailRefresher: mailRefresh, calendarRefresher: calendarRefresh, rssRefresher: rssRefresh, sessionMessenger: sessionMessage)
    }
}
