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

public enum ConnorTaskScope: String, Codable, Sendable, Equatable, CaseIterable {
    case global
    case session
}

public enum ConnorTaskRecoveryPolicy: String, Codable, Sendable, Equatable, CaseIterable {
    case none
    case restoreIfInterrupted
    case restoreIfQueuedOrRunning
}

public enum ConnorTaskRecurrence: String, Codable, Sendable, Equatable, CaseIterable {
    case once
    case daily
    case weekly
    case monthly
    case interval
}

public enum ConnorTaskEventName {
    public static let sessionStatusChanged = "session.status.changed"
    public static let mediaTranscriptionRequested = "media.transcription.requested"
}

public struct ConnorTaskTrigger: Codable, Sendable, Equatable {
    public var kind: ConnorTaskTriggerKind
    public var intervalSeconds: TimeInterval?
    public var runAt: Date?
    public var recurrence: ConnorTaskRecurrence?
    public var eventName: String?
    public var eventFilter: [String: String]
    public var timezoneIdentifier: String?

    public init(
        kind: ConnorTaskTriggerKind,
        intervalSeconds: TimeInterval? = nil,
        runAt: Date? = nil,
        recurrence: ConnorTaskRecurrence? = nil,
        eventName: String? = nil,
        eventFilter: [String: String] = [:],
        timezoneIdentifier: String? = nil
    ) {
        self.kind = kind
        self.intervalSeconds = intervalSeconds
        self.runAt = runAt
        self.recurrence = recurrence ?? (intervalSeconds == nil ? nil : .interval)
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

    public static func sourceRuntimeRefresh(sourceID: String) -> ConnorTaskTarget {
        ConnorTaskTarget(targetKind: "source.runtime", targetID: sourceID, operationName: "refresh")
    }

    public static func sendMessageToSession(sessionID: String = "", message: String) -> ConnorTaskTarget {
        ConnorTaskTarget(targetKind: "session.ai", targetID: sessionID, operationName: "sendMessage", parameters: ["message": message])
    }

    public static func createSessionAndSendMessage(message: String, title: String = "") -> ConnorTaskTarget {
        var parameters = ["message": message]
        if !title.isEmpty { parameters["title"] = title }
        return ConnorTaskTarget(targetKind: "session.ai", targetID: "new", operationName: "createSessionAndSendMessage", parameters: parameters)
    }

    public static func mediaTranscriptionRun(jobID: String, ownerSessionID: String) -> ConnorTaskTarget {
        ConnorTaskTarget(
            targetKind: "media.transcription",
            targetID: jobID,
            operationName: "run",
            parameters: [
                "jobID": jobID,
                "ownerSessionID": ownerSessionID
            ]
        )
    }
}

public enum ConnorTaskValidationError: Error, Sendable, Equatable, CustomStringConvertible {
    case systemTaskTemplateRequired(String)
    case unsupportedUserCreatableTarget(String)
    case unsupportedUserCreatableTrigger(String)
    case missingRequiredParameter(String)

    public var description: String {
        switch self {
        case .systemTaskTemplateRequired(let id): "systemTaskTemplateRequired: \(id)"
        case .unsupportedUserCreatableTarget(let target): "unsupportedUserCreatableTarget: \(target)"
        case .unsupportedUserCreatableTrigger(let trigger): "unsupportedUserCreatableTrigger: \(trigger)"
        case .missingRequiredParameter(let parameter): "missingRequiredParameter: \(parameter)"
        }
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
    private enum CodingKeys: String, CodingKey {
        case createdBySessionID
        case createdByDisplayName
        case rationale
        case tags
        case scope
        case ownerSessionID
        case isRecoverable
        case recoveryPolicy
        case isProtectedSystemTask
        case userEditableFields
    }

    public var createdBySessionID: String?
    public var createdByDisplayName: String?
    public var rationale: String?
    public var tags: [String]
    public var scope: ConnorTaskScope
    public var ownerSessionID: String?
    public var isRecoverable: Bool
    public var recoveryPolicy: ConnorTaskRecoveryPolicy
    public var isProtectedSystemTask: Bool
    public var userEditableFields: Set<ConnorTaskEditableField>

    public init(
        createdBySessionID: String? = nil,
        createdByDisplayName: String? = nil,
        rationale: String? = nil,
        tags: [String] = [],
        scope: ConnorTaskScope = .global,
        ownerSessionID: String? = nil,
        isRecoverable: Bool = false,
        recoveryPolicy: ConnorTaskRecoveryPolicy = .none,
        isProtectedSystemTask: Bool = false,
        userEditableFields: Set<ConnorTaskEditableField> = Set(ConnorTaskEditableField.allCases)
    ) {
        self.createdBySessionID = createdBySessionID
        self.createdByDisplayName = createdByDisplayName
        self.rationale = rationale
        self.tags = tags
        self.scope = scope
        self.ownerSessionID = ownerSessionID
        self.isRecoverable = isRecoverable
        self.recoveryPolicy = recoveryPolicy
        self.isProtectedSystemTask = isProtectedSystemTask
        self.userEditableFields = userEditableFields
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.createdBySessionID = try container.decodeIfPresent(String.self, forKey: .createdBySessionID)
        self.createdByDisplayName = try container.decodeIfPresent(String.self, forKey: .createdByDisplayName)
        self.rationale = try container.decodeIfPresent(String.self, forKey: .rationale)
        self.tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        self.scope = try container.decodeIfPresent(ConnorTaskScope.self, forKey: .scope) ?? .global
        self.ownerSessionID = try container.decodeIfPresent(String.self, forKey: .ownerSessionID)
        self.isRecoverable = try container.decodeIfPresent(Bool.self, forKey: .isRecoverable) ?? false
        self.recoveryPolicy = try container.decodeIfPresent(ConnorTaskRecoveryPolicy.self, forKey: .recoveryPolicy) ?? .none
        self.isProtectedSystemTask = try container.decodeIfPresent(Bool.self, forKey: .isProtectedSystemTask) ?? false
        self.userEditableFields = try container.decodeIfPresent(Set<ConnorTaskEditableField>.self, forKey: .userEditableFields) ?? Set(ConnorTaskEditableField.allCases)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(createdBySessionID, forKey: .createdBySessionID)
        try container.encodeIfPresent(createdByDisplayName, forKey: .createdByDisplayName)
        try container.encodeIfPresent(rationale, forKey: .rationale)
        try container.encode(tags, forKey: .tags)
        try container.encode(scope, forKey: .scope)
        try container.encodeIfPresent(ownerSessionID, forKey: .ownerSessionID)
        try container.encode(isRecoverable, forKey: .isRecoverable)
        try container.encode(recoveryPolicy, forKey: .recoveryPolicy)
        try container.encode(isProtectedSystemTask, forKey: .isProtectedSystemTask)
        try container.encode(userEditableFields, forKey: .userEditableFields)
    }

    public static let protectedSystem = ConnorTaskMetadata(
        tags: ["system", "protected"],
        scope: .global,
        isRecoverable: false,
        recoveryPolicy: .none,
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
                trigger: ConnorTaskTrigger(kind: .scheduled, intervalSeconds: 600, recurrence: .interval),
                target: .sourceRuntimeRefresh(sourceID: "mail"),
                lifecycle: ConnorTaskLifecycle(status: .active),
                metadata: .protectedSystem,
                createdAt: now,
                updatedAt: now
            ),
            ConnorTaskDefinition(
                id: "system.calendar.check-every-10-minutes",
                name: "检查日历",
                origin: .system,
                trigger: ConnorTaskTrigger(kind: .scheduled, intervalSeconds: 600, recurrence: .interval),
                target: .sourceRuntimeRefresh(sourceID: "calendar"),
                lifecycle: ConnorTaskLifecycle(status: .active),
                metadata: .protectedSystem,
                createdAt: now,
                updatedAt: now
            ),
            ConnorTaskDefinition(
                id: "system.rss.check-every-30-minutes",
                name: "检查 RSS",
                origin: .system,
                trigger: ConnorTaskTrigger(kind: .scheduled, intervalSeconds: 1_800, recurrence: .interval),
                target: .sourceRuntimeRefresh(sourceID: "rss"),
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

public extension ConnorTaskDefinition {
    func validateUserCreatableTemplate() throws {
        guard origin == .user || origin == .ai else {
            throw ConnorTaskValidationError.unsupportedUserCreatableTarget(origin.rawValue)
        }
        switch trigger.kind {
        case .scheduled:
            guard target.targetKind == "session.ai", target.targetID == "new", target.operationName == "createSessionAndSendMessage" else {
                throw ConnorTaskValidationError.unsupportedUserCreatableTarget("\(target.targetKind):\(target.targetID).\(target.operationName)")
            }
            guard target.parameters["message"]?.isEmpty == false else {
                throw ConnorTaskValidationError.missingRequiredParameter("message")
            }
            let recurrence = trigger.recurrence ?? (trigger.intervalSeconds == nil ? .once : .interval)
            guard [.once, .daily, .weekly, .monthly].contains(recurrence) else {
                throw ConnorTaskValidationError.unsupportedUserCreatableTrigger(recurrence.rawValue)
            }
        case .eventTriggered:
            guard trigger.eventName == ConnorTaskEventName.sessionStatusChanged else {
                throw ConnorTaskValidationError.unsupportedUserCreatableTrigger(trigger.eventName ?? "")
            }
            guard trigger.eventFilter["toStatus"]?.isEmpty == false else {
                throw ConnorTaskValidationError.missingRequiredParameter("toStatus")
            }
            guard target.targetKind == "session.ai", target.operationName == "sendMessage" else {
                throw ConnorTaskValidationError.unsupportedUserCreatableTarget("\(target.targetKind):\(target.targetID).\(target.operationName)")
            }
            guard target.parameters["message"]?.isEmpty == false else {
                throw ConnorTaskValidationError.missingRequiredParameter("message")
            }
        }
    }

    func validateSystemTaskTemplate() throws {
        guard origin == .system else { return }
        guard target.targetKind == "source.runtime", target.operationName == "refresh", ["mail", "calendar", "rss"].contains(target.targetID) else {
            throw ConnorTaskValidationError.systemTaskTemplateRequired(id)
        }
    }
}
