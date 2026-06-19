import Foundation

public enum ConnorTaskOrigin: String, Codable, Sendable, Equatable, CaseIterable {
    case system
    case user
    case ai
}

public enum ConnorTaskTriggerKind: String, Codable, Sendable, Equatable, CaseIterable {
    case scheduled
    case eventTriggered
}

public struct ConnorTaskTrigger: Codable, Sendable, Equatable {
    public var kind: ConnorTaskTriggerKind
    public var intervalSeconds: TimeInterval?
    public var eventName: String?
    public var eventFilter: [String: String]
    public var timezoneIdentifier: String?

    public init(
        kind: ConnorTaskTriggerKind,
        intervalSeconds: TimeInterval? = nil,
        eventName: String? = nil,
        eventFilter: [String: String] = [:],
        timezoneIdentifier: String? = nil
    ) {
        self.kind = kind
        self.intervalSeconds = intervalSeconds
        self.eventName = eventName
        self.eventFilter = eventFilter
        self.timezoneIdentifier = timezoneIdentifier
    }
}

public struct ConnorTaskTarget: Codable, Sendable, Equatable {
    public var targetKind: String
    public var targetID: String
    public var operationName: String
    public var parameters: [String: String]

    public init(targetKind: String, targetID: String, operationName: String, parameters: [String: String] = [:]) {
        self.targetKind = targetKind
        self.targetID = targetID
        self.operationName = operationName
        self.parameters = parameters
    }
}

public enum ConnorTaskLifecycleStatus: String, Codable, Sendable, Equatable, CaseIterable {
    case active
    case stopped
    case running
    case succeeded
    case failed
    case deleted
}

public struct ConnorTaskLifecycle: Codable, Sendable, Equatable {
    public var status: ConnorTaskLifecycleStatus
    public var nextRunAt: Date?
    public var lastRunAt: Date?
    public var lastFinishedAt: Date?
    public var failureCount: Int
    public var lastErrorMessage: String?

    public init(
        status: ConnorTaskLifecycleStatus,
        nextRunAt: Date? = nil,
        lastRunAt: Date? = nil,
        lastFinishedAt: Date? = nil,
        failureCount: Int = 0,
        lastErrorMessage: String? = nil
    ) {
        self.status = status
        self.nextRunAt = nextRunAt
        self.lastRunAt = lastRunAt
        self.lastFinishedAt = lastFinishedAt
        self.failureCount = failureCount
        self.lastErrorMessage = lastErrorMessage
    }
}

public enum ConnorTaskEditableField: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case name
    case trigger
    case target
    case tags
    case rationale
}

public struct ConnorTaskMetadata: Codable, Sendable, Equatable {
    public var createdBySessionID: String?
    public var createdByDisplayName: String?
    public var rationale: String?
    public var tags: [String]
    public var isProtectedSystemTask: Bool
    public var userEditableFields: Set<ConnorTaskEditableField>

    public init(
        createdBySessionID: String? = nil,
        createdByDisplayName: String? = nil,
        rationale: String? = nil,
        tags: [String] = [],
        isProtectedSystemTask: Bool = false,
        userEditableFields: Set<ConnorTaskEditableField> = Set(ConnorTaskEditableField.allCases)
    ) {
        self.createdBySessionID = createdBySessionID
        self.createdByDisplayName = createdByDisplayName
        self.rationale = rationale
        self.tags = tags
        self.isProtectedSystemTask = isProtectedSystemTask
        self.userEditableFields = userEditableFields
    }

    public static let protectedSystem = ConnorTaskMetadata(
        tags: ["system", "protected"],
        isProtectedSystemTask: true,
        userEditableFields: [.name, .tags]
    )
}

public struct ConnorTaskDefinition: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var origin: ConnorTaskOrigin
    public var trigger: ConnorTaskTrigger
    public var target: ConnorTaskTarget
    public var lifecycle: ConnorTaskLifecycle
    public var metadata: ConnorTaskMetadata
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        name: String,
        origin: ConnorTaskOrigin,
        trigger: ConnorTaskTrigger,
        target: ConnorTaskTarget,
        lifecycle: ConnorTaskLifecycle,
        metadata: ConnorTaskMetadata,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.origin = origin
        self.trigger = trigger
        self.target = target
        self.lifecycle = lifecycle
        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public static func systemDefaults(now: Date = Date()) -> [ConnorTaskDefinition] {
        [
            ConnorTaskDefinition(
                id: "system.mail.check-every-10-minutes",
                name: "检查邮件",
                origin: .system,
                trigger: ConnorTaskTrigger(kind: .scheduled, intervalSeconds: 600),
                target: ConnorTaskTarget(targetKind: "source.runtime", targetID: "mail", operationName: "check"),
                lifecycle: ConnorTaskLifecycle(status: .active),
                metadata: .protectedSystem,
                createdAt: now,
                updatedAt: now
            ),
            ConnorTaskDefinition(
                id: "system.calendar.check-every-10-minutes",
                name: "检查日历",
                origin: .system,
                trigger: ConnorTaskTrigger(kind: .scheduled, intervalSeconds: 600),
                target: ConnorTaskTarget(targetKind: "source.runtime", targetID: "calendar", operationName: "check"),
                lifecycle: ConnorTaskLifecycle(status: .active),
                metadata: .protectedSystem,
                createdAt: now,
                updatedAt: now
            ),
            ConnorTaskDefinition(
                id: "system.rss.check-every-30-minutes",
                name: "检查 RSS",
                origin: .system,
                trigger: ConnorTaskTrigger(kind: .scheduled, intervalSeconds: 1_800),
                target: ConnorTaskTarget(targetKind: "source.runtime", targetID: "rss", operationName: "check"),
                lifecycle: ConnorTaskLifecycle(status: .active),
                metadata: .protectedSystem,
                createdAt: now,
                updatedAt: now
            )
        ]
    }
}

public enum ConnorTaskRunStatus: String, Codable, Sendable, Equatable, CaseIterable {
    case queued
    case running
    case succeeded
    case failed
    case cancelled
}

public struct ConnorTaskRunRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var taskID: String
    public var status: ConnorTaskRunStatus
    public var startedAt: Date
    public var finishedAt: Date?
    public var outputSummary: String
    public var errorMessage: String?
    public var externalRunID: String?

    public init(
        id: String = UUID().uuidString,
        taskID: String,
        status: ConnorTaskRunStatus,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        outputSummary: String = "",
        errorMessage: String? = nil,
        externalRunID: String? = nil
    ) {
        self.id = id
        self.taskID = taskID
        self.status = status
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.outputSummary = outputSummary
        self.errorMessage = errorMessage
        self.externalRunID = externalRunID
    }
}
