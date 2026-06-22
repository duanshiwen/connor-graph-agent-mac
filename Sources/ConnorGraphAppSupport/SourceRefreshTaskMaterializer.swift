import Foundation
import ConnorGraphCore

public struct SourceRefreshTaskMaterializer: Sendable {
    public static let sourceInstanceIDParameter = "sourceInstanceID"
    public static let sourceKindParameter = "sourceKind"

    public var taskRepository: AppTaskManagementRepository
    public var rssSourceRepository: any RSSSourceRepository

    public init(taskRepository: AppTaskManagementRepository, rssSourceRepository: any RSSSourceRepository) {
        self.taskRepository = taskRepository
        self.rssSourceRepository = rssSourceRepository
    }

    @discardableResult
    public func reconcileRSSSourceRefreshTasks(now: Date = Date()) async throws -> [ConnorTaskDefinition] {
        _ = try taskRepository.loadOrCreateDefault(now: now)
        let sources = try await rssSourceRepository.listSources()
        var tasks = try taskRepository.loadTasks(includeDeleted: true)
        var tasksByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        var desiredIDs = Set<String>()

        for source in sources {
            let taskID = Self.rssRefreshTaskID(sourceID: source.id)
            desiredIDs.insert(taskID)
            let desired = Self.makeRSSRefreshTask(source: source, id: taskID, now: now)
            var next = tasksByID[taskID] ?? desired
            next.origin = .system
            next.name = desired.name
            next.trigger = desired.trigger
            next.target = desired.target
            next.metadata = desired.metadata
            if next.lifecycle.status == .deleted || next.lifecycle.status == .stopped {
                next.lifecycle.status = .active
                next.lifecycle.lastErrorMessage = nil
            }
            next.updatedAt = tasksByID[taskID] == nil ? desired.updatedAt : now
            if tasksByID[taskID] == nil {
                next.createdAt = desired.createdAt
            }
            if tasksByID[taskID] != next {
                try taskRepository.saveTask(next)
                tasksByID[taskID] = next
            }
        }

        tasks = try taskRepository.loadTasks(includeDeleted: true)
        for task in tasks where Self.isRSSSourceInstanceRefreshTask(task) && !desiredIDs.contains(task.id) {
            try taskRepository.purgeTaskDefinition(id: task.id, reason: "RSS source no longer exists.")
        }

        for task in try taskRepository.loadTasks(includeDeleted: true) where Self.isRSSGlobalRefreshTask(task) {
            try taskRepository.purgeTaskDefinition(id: task.id, reason: "RSS refresh tasks are materialized per source instance.")
        }

        return try taskRepository.loadTasks(includeDeleted: true)
    }

    public static func rssRefreshTaskID(sourceID: RSSSourceID) -> String {
        let raw = sourceID.rawValue.lowercased()
        let sanitized = raw
            .map { character -> Character in
                if character.isASCII && (character.isLetter || character.isNumber || character == "." || character == "-") { return character }
                return "-"
            }
        let collapsed = String(sanitized)
            .replacingOccurrences(of: #"[-.]{2,}"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
        let slug = collapsed.isEmpty ? String(RSSHash.sha256(sourceID.rawValue).prefix(12)) : collapsed
        let candidate = "system.rss.source.\(slug).refresh"
        if candidate.count <= 128 { return candidate }
        return "system.rss.source.\(RSSHash.sha256(sourceID.rawValue).prefix(16)).refresh"
    }

    public static func makeRSSRefreshTask(source: RSSSource, id: String? = nil, now: Date = Date()) -> ConnorTaskDefinition {
        let taskID = id ?? rssRefreshTaskID(sourceID: source.id)
        let intervalSeconds = TimeInterval(max(source.fetchPolicy.intervalMinutes, 1) * 60)
        return ConnorTaskDefinition(
            id: taskID,
            name: "检查 RSS：\(source.displayName)",
            origin: .system,
            trigger: ConnorTaskTrigger(kind: .scheduled, intervalSeconds: intervalSeconds, recurrence: .interval),
            target: ConnorTaskTarget(
                targetKind: "source.runtime",
                targetID: "rss",
                operationName: "refresh",
                parameters: [
                    sourceKindParameter: "rss",
                    sourceInstanceIDParameter: source.id.rawValue
                ]
            ),
            lifecycle: ConnorTaskLifecycle(status: .active),
            metadata: ConnorTaskMetadata(
                rationale: "Materialized from RSS source fetch policy.",
                tags: ["system", "protected", "rss", "source-instance"],
                scope: .global,
                isRecoverable: false,
                recoveryPolicy: .none,
                isProtectedSystemTask: true,
                userEditableFields: [.name, .tags]
            ),
            createdAt: now,
            updatedAt: now
        )
    }

    public static func isRSSSourceInstanceRefreshTask(_ task: ConnorTaskDefinition) -> Bool {
        task.origin == .system
        && task.target.targetKind == "source.runtime"
        && task.target.targetID == "rss"
        && task.target.operationName == "refresh"
        && task.target.parameters[sourceInstanceIDParameter]?.isEmpty == false
    }

    public static func isRSSGlobalRefreshTask(_ task: ConnorTaskDefinition) -> Bool {
        task.origin == .system
        && task.target.targetKind == "source.runtime"
        && task.target.targetID == "rss"
        && task.target.operationName == "refresh"
        && (task.target.parameters[sourceInstanceIDParameter]?.isEmpty ?? true)
    }

}

public struct MailRefreshTaskMaterializer: Sendable {
    public static let sourceInstanceIDParameter = SourceRefreshTaskMaterializer.sourceInstanceIDParameter
    public static let sourceKindParameter = SourceRefreshTaskMaterializer.sourceKindParameter

    public var taskRepository: AppTaskManagementRepository
    public var mailSourceRepository: any MailSourceRepository

    public init(taskRepository: AppTaskManagementRepository, mailSourceRepository: any MailSourceRepository) {
        self.taskRepository = taskRepository
        self.mailSourceRepository = mailSourceRepository
    }

    @discardableResult
    public func reconcileMailAccountRefreshTasks(now: Date = Date()) async throws -> [ConnorTaskDefinition] {
        _ = try taskRepository.loadOrCreateDefault(now: now)
        let accounts = try await mailSourceRepository.listAccounts()
        var tasks = try taskRepository.loadTasks(includeDeleted: true)
        var tasksByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        var desiredIDs = Set<String>()

        for account in accounts {
            let taskID = Self.mailRefreshTaskID(accountID: account.id)
            desiredIDs.insert(taskID)
            let desired = Self.makeMailRefreshTask(account: account, id: taskID, now: now)
            var next = tasksByID[taskID] ?? desired
            next.origin = .system
            next.name = desired.name
            next.trigger = desired.trigger
            next.target = desired.target
            next.metadata = desired.metadata
            if next.lifecycle.status == .deleted || next.lifecycle.status == .stopped {
                next.lifecycle.status = .active
                next.lifecycle.lastErrorMessage = nil
            }
            next.updatedAt = tasksByID[taskID] == nil ? desired.updatedAt : now
            if tasksByID[taskID] == nil {
                next.createdAt = desired.createdAt
            }
            if tasksByID[taskID] != next {
                try taskRepository.saveTask(next)
                tasksByID[taskID] = next
            }
        }

        tasks = try taskRepository.loadTasks(includeDeleted: true)
        for task in tasks where Self.isMailAccountRefreshTask(task) && !desiredIDs.contains(task.id) {
            try taskRepository.purgeTaskDefinition(id: task.id, reason: "Mail account no longer exists.")
        }

        for task in try taskRepository.loadTasks(includeDeleted: true) where Self.isMailGlobalRefreshTask(task) {
            try taskRepository.purgeTaskDefinition(id: task.id, reason: "Mail refresh tasks are materialized per account.")
        }

        return try taskRepository.loadTasks(includeDeleted: true)
    }

    public static func mailRefreshTaskID(accountID: MailAccountID) -> String {
        let raw = accountID.rawValue.lowercased()
        let sanitized = raw
            .map { character -> Character in
                if character.isASCII && (character.isLetter || character.isNumber || character == "." || character == "-") { return character }
                return "-"
            }
        let collapsed = String(sanitized)
            .replacingOccurrences(of: #"[-.]{2,}"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
        let slug = collapsed.isEmpty ? String(RSSHash.sha256(accountID.rawValue).prefix(12)) : collapsed
        let candidate = "system.mail.account.\(slug).refresh"
        if candidate.count <= 128 { return candidate }
        return "system.mail.account.\(RSSHash.sha256(accountID.rawValue).prefix(16)).refresh"
    }

    public static func makeMailRefreshTask(account: MailAccount, id: String? = nil, now: Date = Date()) -> ConnorTaskDefinition {
        let taskID = id ?? mailRefreshTaskID(accountID: account.id)
        return ConnorTaskDefinition(
            id: taskID,
            name: "检查邮件：\(account.displayName)",
            origin: .system,
            trigger: ConnorTaskTrigger(kind: .scheduled, intervalSeconds: 600, recurrence: .interval),
            target: ConnorTaskTarget(
                targetKind: "source.runtime",
                targetID: "mail",
                operationName: "refresh",
                parameters: [
                    sourceKindParameter: "mail",
                    sourceInstanceIDParameter: account.id.rawValue
                ]
            ),
            lifecycle: ConnorTaskLifecycle(status: .active),
            metadata: ConnorTaskMetadata(
                rationale: "Materialized from configured mail account.",
                tags: ["system", "protected", "mail", "source-instance"],
                scope: .global,
                isRecoverable: false,
                recoveryPolicy: .none,
                isProtectedSystemTask: true,
                userEditableFields: [.name, .tags]
            ),
            createdAt: now,
            updatedAt: now
        )
    }

    public static func isMailAccountRefreshTask(_ task: ConnorTaskDefinition) -> Bool {
        task.origin == .system
        && task.target.targetKind == "source.runtime"
        && task.target.targetID == "mail"
        && task.target.operationName == "refresh"
        && task.target.parameters[sourceInstanceIDParameter]?.isEmpty == false
    }

    public static func isMailGlobalRefreshTask(_ task: ConnorTaskDefinition) -> Bool {
        task.origin == .system
        && task.target.targetKind == "source.runtime"
        && task.target.targetID == "mail"
        && task.target.operationName == "refresh"
        && (task.target.parameters[sourceInstanceIDParameter]?.isEmpty ?? true)
    }
}

public struct CalendarRefreshTaskMaterializer: Sendable {
    public static let sourceInstanceIDParameter = SourceRefreshTaskMaterializer.sourceInstanceIDParameter
    public static let sourceKindParameter = SourceRefreshTaskMaterializer.sourceKindParameter

    public var taskRepository: AppTaskManagementRepository
    public var calendarSourceRepository: any CalendarSourceRepository

    public init(taskRepository: AppTaskManagementRepository, calendarSourceRepository: any CalendarSourceRepository) {
        self.taskRepository = taskRepository
        self.calendarSourceRepository = calendarSourceRepository
    }

    @discardableResult
    public func reconcileCalendarAccountRefreshTasks(now: Date = Date()) async throws -> [ConnorTaskDefinition] {
        _ = try taskRepository.loadOrCreateDefault(now: now)
        let accounts = try await calendarSourceRepository.listAccounts()
        var tasks = try taskRepository.loadTasks(includeDeleted: true)
        var tasksByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        var desiredIDs = Set<String>()

        for account in accounts {
            let taskID = Self.calendarRefreshTaskID(accountID: account.id)
            desiredIDs.insert(taskID)
            let desired = Self.makeCalendarRefreshTask(account: account, id: taskID, now: now)
            var next = tasksByID[taskID] ?? desired
            next.origin = .system
            next.name = desired.name
            next.trigger = desired.trigger
            next.target = desired.target
            next.metadata = desired.metadata
            if next.lifecycle.status == .deleted || next.lifecycle.status == .stopped {
                next.lifecycle.status = .active
                next.lifecycle.lastErrorMessage = nil
            }
            next.updatedAt = tasksByID[taskID] == nil ? desired.updatedAt : now
            if tasksByID[taskID] == nil {
                next.createdAt = desired.createdAt
            }
            if tasksByID[taskID] != next {
                try taskRepository.saveTask(next)
                tasksByID[taskID] = next
            }
        }

        tasks = try taskRepository.loadTasks(includeDeleted: true)
        for task in tasks where Self.isCalendarAccountRefreshTask(task) && !desiredIDs.contains(task.id) {
            try taskRepository.purgeTaskDefinition(id: task.id, reason: "Calendar account no longer exists.")
        }

        for task in try taskRepository.loadTasks(includeDeleted: true) where Self.isCalendarGlobalRefreshTask(task) {
            try taskRepository.purgeTaskDefinition(id: task.id, reason: "Calendar refresh tasks are materialized per account.")
        }

        return try taskRepository.loadTasks(includeDeleted: true)
    }

    public static func calendarRefreshTaskID(accountID: CalendarAccountID) -> String {
        let raw = accountID.rawValue.lowercased()
        let sanitized = raw
            .map { character -> Character in
                if character.isASCII && (character.isLetter || character.isNumber || character == "." || character == "-") { return character }
                return "-"
            }
        let collapsed = String(sanitized)
            .replacingOccurrences(of: #"[-.]{2,}"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
        let slug = collapsed.isEmpty ? String(RSSHash.sha256(accountID.rawValue).prefix(12)) : collapsed
        let candidate = "system.calendar.account.\(slug).refresh"
        if candidate.count <= 128 { return candidate }
        return "system.calendar.account.\(RSSHash.sha256(accountID.rawValue).prefix(16)).refresh"
    }

    public static func makeCalendarRefreshTask(account: CalendarAccount, id: String? = nil, now: Date = Date()) -> ConnorTaskDefinition {
        let taskID = id ?? calendarRefreshTaskID(accountID: account.id)
        return ConnorTaskDefinition(
            id: taskID,
            name: "检查日历：\(account.displayName)",
            origin: .system,
            trigger: ConnorTaskTrigger(kind: .scheduled, intervalSeconds: 600, recurrence: .interval),
            target: ConnorTaskTarget(
                targetKind: "source.runtime",
                targetID: "calendar",
                operationName: "refresh",
                parameters: [
                    sourceKindParameter: "calendar",
                    sourceInstanceIDParameter: account.id.rawValue
                ]
            ),
            lifecycle: ConnorTaskLifecycle(status: .active),
            metadata: ConnorTaskMetadata(
                rationale: "Materialized from configured calendar account.",
                tags: ["system", "protected", "calendar", "source-instance"],
                scope: .global,
                isRecoverable: false,
                recoveryPolicy: .none,
                isProtectedSystemTask: true,
                userEditableFields: [.name, .tags]
            ),
            createdAt: now,
            updatedAt: now
        )
    }

    public static func isCalendarAccountRefreshTask(_ task: ConnorTaskDefinition) -> Bool {
        task.origin == .system
        && task.target.targetKind == "source.runtime"
        && task.target.targetID == "calendar"
        && task.target.operationName == "refresh"
        && task.target.parameters[sourceInstanceIDParameter]?.isEmpty == false
    }

    public static func isCalendarGlobalRefreshTask(_ task: ConnorTaskDefinition) -> Bool {
        task.origin == .system
        && task.target.targetKind == "source.runtime"
        && task.target.targetID == "calendar"
        && task.target.operationName == "refresh"
        && (task.target.parameters[sourceInstanceIDParameter]?.isEmpty ?? true)
    }
}
