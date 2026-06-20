import Foundation
import ConnorGraphCore

public struct SourceRefreshTaskMaterializer: Sendable {
    public static let legacyGlobalRSSTaskID = "system.rss.check-every-30-minutes"
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
        for task in tasks where Self.isRSSSourceInstanceRefreshTask(task) && !desiredIDs.contains(task.id) && task.lifecycle.status != .stopped && task.lifecycle.status != .deleted {
            var stopped = task
            stopped.lifecycle.status = .stopped
            stopped.lifecycle.lastErrorMessage = "RSS source no longer exists; source-instance refresh task stopped by reconcile."
            stopped.metadata.tags = Self.mergedTags(stopped.metadata.tags, ["deprecated", "orphaned-source"])
            stopped.updatedAt = now
            try taskRepository.saveTask(stopped)
        }

        if var legacy = try taskRepository.loadTask(id: Self.legacyGlobalRSSTaskID), legacy.lifecycle.status != .stopped && legacy.lifecycle.status != .deleted {
            legacy.lifecycle.status = .stopped
            legacy.lifecycle.lastErrorMessage = "Replaced by RSS source-instance refresh tasks."
            legacy.metadata.tags = Self.mergedTags(legacy.metadata.tags, ["deprecated", "source-type-refresh"])
            legacy.updatedAt = now
            try taskRepository.saveTask(legacy)
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

    private static func mergedTags(_ existing: [String], _ additions: [String]) -> [String] {
        var seen = Set<String>()
        var merged: [String] = []
        for tag in existing + additions where !seen.contains(tag) {
            seen.insert(tag)
            merged.append(tag)
        }
        return merged
    }
}
