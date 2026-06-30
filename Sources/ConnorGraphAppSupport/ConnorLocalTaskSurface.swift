import Foundation
import ConnorGraphCore

public enum ConnorLocalTaskRouteID: String, Codable, Sendable, Equatable, Hashable, Identifiable, CaseIterable {
    case readiness
    case tasks
    case taskDetail
    case taskCreate
    case taskUpdate
    case taskStop
    case taskRestore
    case taskDelete
    case taskRuns
    case taskRunAppend
    case sessionTasks
    case sessionRecoverableTasks
    case sessionTaskStop
    case sessionTaskRestore

    public var id: String { rawValue }
}

public struct ConnorLocalTaskEndpointPresentation: Codable, Sendable, Equatable, Identifiable {
    public var id: ConnorLocalTaskRouteID
    public var method: ConnorLocalAPIMethod
    public var path: String
    public var summary: String
    public var riskLevel: ConnorLocalAPIRiskLevel
    public var authMode: ConnorLocalAPIAuthMode
    public var requiresReview: Bool
    public var cliEquivalent: String

    public init(
        id: ConnorLocalTaskRouteID,
        method: ConnorLocalAPIMethod,
        path: String,
        summary: String,
        riskLevel: ConnorLocalAPIRiskLevel = .readOnly,
        authMode: ConnorLocalAPIAuthMode = .localProcess,
        requiresReview: Bool = false,
        cliEquivalent: String
    ) {
        self.id = id
        self.method = method
        self.path = path
        self.summary = summary
        self.riskLevel = riskLevel
        self.authMode = authMode
        self.requiresReview = requiresReview
        self.cliEquivalent = cliEquivalent
    }
}

public enum ConnorTaskCLICommandID: String, Codable, Sendable, Equatable, Hashable, Identifiable, CaseIterable {
    case commands
    case readiness
    case taskList
    case taskShow
    case taskStop
    case taskRestore
    case taskDelete
    case taskPurge
    case taskRename
    case taskRuns
    case sessionTaskList
    case sessionTaskRecoverable
    case sessionTaskStop
    case sessionTaskRestore

    public var id: String { rawValue }
}

public struct ConnorTaskCLICommandPresentation: Codable, Sendable, Equatable, Identifiable {
    public var id: ConnorTaskCLICommandID
    public var name: String
    public var usage: String
    public var summary: String
    public var riskLevel: ConnorLocalAPIRiskLevel
    public var requiresReview: Bool
    public var examples: [String]
    public var outputFormat: String
    public var apiRoute: ConnorLocalTaskRouteID?

    public init(
        id: ConnorTaskCLICommandID,
        name: String,
        usage: String,
        summary: String,
        riskLevel: ConnorLocalAPIRiskLevel = .readOnly,
        requiresReview: Bool = false,
        examples: [String] = [],
        outputFormat: String = "json",
        apiRoute: ConnorLocalTaskRouteID? = nil
    ) {
        self.id = id
        self.name = name
        self.usage = usage
        self.summary = summary
        self.riskLevel = riskLevel
        self.requiresReview = requiresReview
        self.examples = examples
        self.outputFormat = outputFormat
        self.apiRoute = apiRoute
    }
}

public struct ConnorLocalTaskSurfacePresentation: Codable, Sendable, Equatable {
    public var endpoints: [ConnorLocalTaskEndpointPresentation]
    public var cliCommands: [ConnorTaskCLICommandPresentation]
    public var supportedTriggerKinds: [ConnorTaskTriggerKind]
    public var lifecycleReady: Bool
    public var runHistoryReady: Bool
    public var localOnly: Bool

    public init(
        endpoints: [ConnorLocalTaskEndpointPresentation] = ConnorLocalTaskSurfaceCatalog.defaultEndpoints,
        cliCommands: [ConnorTaskCLICommandPresentation] = ConnorLocalTaskSurfaceCatalog.defaultCommands,
        supportedTriggerKinds: [ConnorTaskTriggerKind] = ConnorTaskTriggerKind.allCases,
        lifecycleReady: Bool = true,
        runHistoryReady: Bool = true,
        localOnly: Bool = true
    ) {
        self.endpoints = endpoints
        self.cliCommands = cliCommands
        self.supportedTriggerKinds = supportedTriggerKinds
        self.lifecycleReady = lifecycleReady
        self.runHistoryReady = runHistoryReady
        self.localOnly = localOnly
    }

    public static let `default` = ConnorLocalTaskSurfacePresentation()
}

public struct ConnorLocalTaskSurfaceReadiness: Codable, Sendable, Equatable {
    public var surface: String
    public var status: String
    public var endpointCount: Int
    public var cliCommandCount: Int
    public var triggerKinds: [String]
    public var lifecycleReady: Bool
    public var runHistoryReady: Bool
    public var reviewGateReady: Bool?
    public var manualTaskSupported: Bool
    public var localOnly: Bool

    public init(presentation: ConnorLocalTaskSurfacePresentation = .default) {
        self.surface = "local-api-cli-task"
        self.status = "ready"
        self.endpointCount = presentation.endpoints.count
        self.cliCommandCount = presentation.cliCommands.count
        self.triggerKinds = presentation.supportedTriggerKinds.map(\.rawValue)
        self.lifecycleReady = presentation.lifecycleReady
        self.runHistoryReady = presentation.runHistoryReady
        self.reviewGateReady = nil
        self.manualTaskSupported = false
        self.localOnly = presentation.localOnly
    }

    public static let `default` = ConnorLocalTaskSurfaceReadiness()
}

public enum ConnorLocalTaskSurfaceCatalog {
    public static let defaultEndpoints: [ConnorLocalTaskEndpointPresentation] = [
        .init(id: .readiness, method: .get, path: "/v1/readiness", summary: "Return Connor readiness.", cliEquivalent: "connor readiness"),
        .init(id: .tasks, method: .get, path: "/v1/tasks", summary: "List abstract Connor tasks.", cliEquivalent: "connor tasks list"),
        .init(id: .taskDetail, method: .get, path: "/v1/tasks/{id}", summary: "Show one abstract task.", cliEquivalent: "connor tasks show <task-id>"),
        .init(id: .taskCreate, method: .post, path: "/v1/tasks", summary: "Create a user or AI task definition.", riskLevel: .stateChanging, cliEquivalent: "connor tasks create"),
        .init(id: .taskUpdate, method: .post, path: "/v1/tasks/{id}", summary: "Update a task definition.", riskLevel: .stateChanging, cliEquivalent: "connor tasks update <task-id>"),
        .init(id: .taskStop, method: .post, path: "/v1/tasks/{id}/stop", summary: "Stop a task lifecycle.", riskLevel: .stateChanging, cliEquivalent: "connor tasks stop <task-id>"),
        .init(id: .taskRestore, method: .post, path: "/v1/tasks/{id}/restore", summary: "Restore a stopped task lifecycle.", riskLevel: .stateChanging, cliEquivalent: "connor tasks restore <task-id>"),
        .init(id: .taskDelete, method: .post, path: "/v1/tasks/{id}", summary: "Soft-delete a user or AI task.", riskLevel: .stateChanging, cliEquivalent: "connor tasks delete <task-id>"),
        .init(id: .taskRuns, method: .get, path: "/v1/tasks/{id}/runs", summary: "List task run history.", cliEquivalent: "connor tasks runs <task-id>"),
        .init(id: .taskRunAppend, method: .post, path: "/v1/tasks/{id}/runs", summary: "Append an external runtime run record.", riskLevel: .stateChanging, cliEquivalent: "external runtime callback"),
        .init(id: .sessionTasks, method: .get, path: "/v1/sessions/{sessionID}/tasks", summary: "List session-scoped background tasks through the task stack.", cliEquivalent: "connor tasks session list <session-id>"),
        .init(id: .sessionRecoverableTasks, method: .get, path: "/v1/sessions/{sessionID}/tasks/recoverable", summary: "List recoverable session-scoped background tasks.", cliEquivalent: "connor tasks session recoverable <session-id>"),
        .init(id: .sessionTaskStop, method: .post, path: "/v1/sessions/{sessionID}/tasks/{taskID}/stop", summary: "Stop a session-scoped background task intent.", riskLevel: .stateChanging, cliEquivalent: "connor tasks session stop <session-id> <task-id>"),
        .init(id: .sessionTaskRestore, method: .post, path: "/v1/sessions/{sessionID}/tasks/{taskID}/restore", summary: "Restore a session-scoped background task intent without running its runtime.", riskLevel: .stateChanging, cliEquivalent: "connor tasks session restore <session-id> <task-id>")
    ]

    public static let defaultCommands: [ConnorTaskCLICommandPresentation] = [
        .init(id: .commands, name: "commands", usage: "connor commands", summary: "List available Connor CLI commands.", examples: ["connor commands"], apiRoute: .readiness),
        .init(id: .readiness, name: "readiness", usage: "connor readiness", summary: "Inspect local task surface readiness.", examples: ["connor readiness"], apiRoute: .readiness),
        .init(id: .taskList, name: "tasks list", usage: "connor tasks list", summary: "List abstract tasks.", examples: ["connor tasks list"], apiRoute: .tasks),
        .init(id: .taskShow, name: "tasks show", usage: "connor tasks show <task-id>", summary: "Show one abstract task.", examples: ["connor tasks show system.calendar.account.calendar-account-macos-eventkit.refresh"], apiRoute: .taskDetail),
        .init(id: .taskStop, name: "tasks stop", usage: "connor tasks stop <task-id>", summary: "Stop a task.", riskLevel: .stateChanging, examples: ["connor tasks stop system.calendar.account.calendar-account-macos-eventkit.refresh"], apiRoute: .taskStop),
        .init(id: .taskRestore, name: "tasks restore", usage: "connor tasks restore <task-id>", summary: "Restore a stopped task.", riskLevel: .stateChanging, examples: ["connor tasks restore system.calendar.account.calendar-account-macos-eventkit.refresh"], apiRoute: .taskRestore),
        .init(id: .taskDelete, name: "tasks delete", usage: "connor tasks delete <task-id>", summary: "Soft-delete a user or AI task.", riskLevel: .stateChanging, examples: ["connor tasks delete ai.summary-task"], apiRoute: .taskDelete),
        .init(id: .taskPurge, name: "tasks purge", usage: "connor tasks purge <task-id>", summary: "Permanently remove a task (including protected system tasks).", riskLevel: .stateChanging, examples: ["connor tasks purge system.memory-os.plan-l1-to-knowledge"]),
        .init(id: .taskRename, name: "tasks rename", usage: "connor tasks rename <task-id> <new-name>", summary: "Rename a task.", riskLevel: .stateChanging, examples: ["connor tasks rename system.memory-os.plan-l1-to-knowledge \"Memory OS: L1 Event Processing\""], apiRoute: .taskRuns),
        .init(id: .taskRuns, name: "tasks runs", usage: "connor tasks runs <task-id>", summary: "List task runs.", examples: ["connor tasks runs system.calendar.account.calendar-account-macos-eventkit.refresh"], apiRoute: .taskRuns),
        .init(id: .sessionTaskList, name: "tasks session list", usage: "connor tasks session list <session-id>", summary: "List session-scoped background tasks.", examples: ["connor tasks session list session-1"], apiRoute: .sessionTasks),
        .init(id: .sessionTaskRecoverable, name: "tasks session recoverable", usage: "connor tasks session recoverable <session-id>", summary: "List recoverable session-scoped background tasks.", examples: ["connor tasks session recoverable session-1"], apiRoute: .sessionRecoverableTasks),
        .init(id: .sessionTaskStop, name: "tasks session stop", usage: "connor tasks session stop <session-id> <task-id>", summary: "Stop a session-scoped background task intent.", riskLevel: .stateChanging, examples: ["connor tasks session stop session-1 session.session-1.background.task-1"], apiRoute: .sessionTaskStop),
        .init(id: .sessionTaskRestore, name: "tasks session restore", usage: "connor tasks session restore <session-id> <task-id>", summary: "Restore a session-scoped background task intent.", riskLevel: .stateChanging, examples: ["connor tasks session restore session-1 session.session-1.background.task-1"], apiRoute: .sessionTaskRestore)
    ]
}
