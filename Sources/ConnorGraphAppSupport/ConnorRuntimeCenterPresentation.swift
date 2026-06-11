import Foundation
import ConnorGraphAgent
import ConnorGraphCore

public enum ConnorRuntimeMetricID: String, Codable, Sendable, Equatable, Hashable, Identifiable {
    case activeSessions
    case pendingApprovals
    case memoryReviews
    case automationTriggers

    public var id: String { rawValue }
}

public struct ConnorRuntimeMetricTile: Codable, Sendable, Equatable, Identifiable {
    public var id: ConnorRuntimeMetricID
    public var title: String
    public var value: String
    public var subtitle: String
    public var severity: AgentEventPresentationSeverity
    public var target: ConnorNativeShellItem?

    public init(id: ConnorRuntimeMetricID, title: String, value: String, subtitle: String, severity: AgentEventPresentationSeverity, target: ConnorNativeShellItem? = nil) {
        self.id = id
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.severity = severity
        self.target = target
    }
}

public enum ConnorRuntimeSectionID: String, Codable, Sendable, Equatable, Hashable, Identifiable {
    case runTimeline
    case reviewQueue
    case graphMemory
    case automation

    public var id: String { rawValue }
}

public struct ConnorRuntimeCenterHero: Codable, Sendable, Equatable {
    public var title: String
    public var subtitle: String
    public var statusText: String
    public var updatedText: String

    public init(title: String, subtitle: String, statusText: String, updatedText: String) {
        self.title = title
        self.subtitle = subtitle
        self.statusText = statusText
        self.updatedText = updatedText
    }
}

public struct ConnorRuntimeCenterItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var detail: String
    public var severity: AgentEventPresentationSeverity
    public var target: ConnorNativeShellItem?

    public init(
        id: String,
        title: String,
        subtitle: String,
        detail: String,
        severity: AgentEventPresentationSeverity,
        target: ConnorNativeShellItem? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
        self.severity = severity
        self.target = target
    }
}

public struct ConnorRuntimeCenterSection: Codable, Sendable, Equatable, Identifiable {
    public var id: ConnorRuntimeSectionID
    public var title: String
    public var subtitle: String
    public var items: [ConnorRuntimeCenterItem]
    public var target: ConnorNativeShellItem?

    public init(id: ConnorRuntimeSectionID, title: String, subtitle: String, items: [ConnorRuntimeCenterItem], target: ConnorNativeShellItem? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.items = items
        self.target = target
    }
}

public struct ConnorRuntimeCenterPresentation: Codable, Sendable, Equatable {
    public var hero: ConnorRuntimeCenterHero
    public var metricTiles: [ConnorRuntimeMetricTile]
    public var sections: [ConnorRuntimeCenterSection]

    public init(hero: ConnorRuntimeCenterHero, metricTiles: [ConnorRuntimeMetricTile], sections: [ConnorRuntimeCenterSection]) {
        self.hero = hero
        self.metricTiles = metricTiles
        self.sections = sections
    }

    public static func build(
        sessions: [AgentSession],
        events: [AgentEventPresentation],
        pendingApprovals: [AgentPendingApproval],
        automationTriggers: [ProductOSAutomationTriggerRecord],
        graphMemoryDashboard: GraphMemoryDashboard?,
        now: Date = Date()
    ) -> ConnorRuntimeCenterPresentation {
        let activeSessions = sessions.filter { !$0.isArchived && $0.status != .done }
        let featured = activeSessions.sorted { $0.updatedAt > $1.updatedAt }.first ?? sessions.sorted { $0.updatedAt > $1.updatedAt }.first
        let memoryReviews = (graphMemoryDashboard?.summary.pendingCandidateCount ?? 0) + (graphMemoryDashboard?.summary.openHoldCount ?? 0)

        let hero = ConnorRuntimeCenterHero(
            title: featured?.title ?? "Connor Runtime Center",
            subtitle: featured.map { "Session \($0.id) · \($0.messages.count) messages" } ?? "No active session",
            statusText: featured?.status.rawValue ?? "idle",
            updatedText: featured.map { relativeTime(from: $0.updatedAt, to: now) } ?? "—"
        )

        let metrics = [
            ConnorRuntimeMetricTile(id: .activeSessions, title: "Active sessions", value: "\(activeSessions.count)", subtitle: "running workspaces", severity: activeSessions.isEmpty ? .info : .success, target: .agentChat),
            ConnorRuntimeMetricTile(id: .pendingApprovals, title: "Pending approvals", value: "\(pendingApprovals.count)", subtitle: "human review gates", severity: pendingApprovals.isEmpty ? .success : .warning, target: .approvals),
            ConnorRuntimeMetricTile(id: .memoryReviews, title: "Memory reviews", value: "\(memoryReviews)", subtitle: "candidates + holds", severity: memoryReviews == 0 ? .success : .warning, target: .graphMemory),
            ConnorRuntimeMetricTile(id: .automationTriggers, title: "Automation triggers", value: "\(automationTriggers.count)", subtitle: "recent governed actions", severity: automationTriggers.contains { $0.requiresReview } ? .warning : .info, target: .automation)
        ]

        let timelineItems = events.map { event in
            ConnorRuntimeCenterItem(
                id: event.id,
                title: event.title,
                subtitle: event.kind,
                detail: event.detail,
                severity: event.severity,
                target: .runtimeCenter
            )
        }
        let approvalItems = pendingApprovals.map { approval in
            ConnorRuntimeCenterItem(
                id: approval.id,
                title: "Permission: \(approval.capability.rawValue)",
                subtitle: approval.toolName ?? approval.requestID,
                detail: "Run \(approval.runID) · Session \(approval.sessionID)",
                severity: .warning,
                target: .approvals
            )
        }
        let memoryItems = (graphMemoryDashboard?.cards ?? []).map { card in
            ConnorRuntimeCenterItem(
                id: card.id,
                title: card.title,
                subtitle: "\(card.kind.rawValue) · \(card.severity.rawValue)",
                detail: card.detail,
                severity: eventSeverity(for: card.severity),
                target: .graphMemory
            )
        }
        let automationItems = automationTriggers.map { trigger in
            ConnorRuntimeCenterItem(
                id: trigger.id,
                title: trigger.ruleName,
                subtitle: trigger.trigger.rawValue,
                detail: trigger.actionSummaries.joined(separator: " · "),
                severity: trigger.requiresReview ? .warning : .info,
                target: .automation
            )
        }

        return ConnorRuntimeCenterPresentation(
            hero: hero,
            metricTiles: metrics,
            sections: [
                ConnorRuntimeCenterSection(id: .runTimeline, title: "Run Timeline", subtitle: "Latest agent events", items: timelineItems, target: .runtimeCenter),
                ConnorRuntimeCenterSection(id: .reviewQueue, title: "Review Queue", subtitle: "Permissions and human gates", items: approvalItems, target: .approvals),
                ConnorRuntimeCenterSection(id: .graphMemory, title: "Graph Memory", subtitle: "Review center", items: memoryItems, target: .graphMemory),
                ConnorRuntimeCenterSection(id: .automation, title: "Automation", subtitle: "Governed triggers", items: automationItems, target: .automation)
            ]
        )
    }

    private static func eventSeverity(for severity: GraphMemoryProductSeverity) -> AgentEventPresentationSeverity {
        switch severity {
        case .info: .info
        case .success: .success
        case .needsReview, .warning: .warning
        case .error: .error
        }
    }

    private static func relativeTime(from date: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }
}
