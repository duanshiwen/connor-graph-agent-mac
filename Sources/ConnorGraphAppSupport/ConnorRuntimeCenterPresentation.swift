import Foundation
import ConnorGraphAgent
import ConnorGraphCore

public enum ConnorRuntimeMetricID: String, Codable, Sendable, Equatable, Hashable, Identifiable {
    case activeSessions
    case pendingApprovals
    case memoryReviews
    case automationTriggers
    case commercialReadiness
    case nativeUIHealth

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
    case nextBestActions
    case runTimeline
    case reviewQueue
    case graphMemory
    case automation
    case commercialReadiness

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
    public var nextBestActions: [ConnorRuntimeCenterItem]

    public init(hero: ConnorRuntimeCenterHero, metricTiles: [ConnorRuntimeMetricTile], sections: [ConnorRuntimeCenterSection], nextBestActions: [ConnorRuntimeCenterItem] = []) {
        self.hero = hero
        self.metricTiles = metricTiles
        self.sections = sections
        self.nextBestActions = nextBestActions
    }

    public static func build(
        sessions: [AgentSession],
        events: [AgentEventPresentation],
        pendingApprovals: [AgentPendingApproval],
        automationTriggers: [ProductOSAutomationTriggerRecord],
        graphMemoryDashboard: GraphMemoryDashboard?,
        commercialReadinessDashboard: CommercialReadinessDashboard? = nil,
        now: Date = Date()
    ) -> ConnorRuntimeCenterPresentation {
        let activeSessions = sessions.filter { !$0.isArchived && $0.status != .done }
        let featured = activeSessions.sorted { $0.updatedAt > $1.updatedAt }.first ?? sessions.sorted { $0.updatedAt > $1.updatedAt }.first
        let memoryReviews = (graphMemoryDashboard?.summary.pendingCandidateCount ?? 0) + (graphMemoryDashboard?.summary.openHoldCount ?? 0)

        let readinessBlockedCount = commercialReadinessDashboard?.blockedCount ?? 0
        let hero = ConnorRuntimeCenterHero(
            title: "Connor Runtime Center",
            subtitle: featured.map { "Active focus: \($0.title) · \($0.messages.count) messages" } ?? "Native Agent OS commercial control surface",
            statusText: readinessBlockedCount == 0 ? "ready" : "needs_review",
            updatedText: featured.map { relativeTime(from: $0.updatedAt, to: now) } ?? "—"
        )

        var metrics = [
            ConnorRuntimeMetricTile(id: .activeSessions, title: "Active sessions", value: "\(activeSessions.count)", subtitle: "running workspaces", severity: activeSessions.isEmpty ? .info : .success, target: .agentChat),
            ConnorRuntimeMetricTile(id: .pendingApprovals, title: "Pending approvals", value: "\(pendingApprovals.count)", subtitle: "human review gates", severity: pendingApprovals.isEmpty ? .success : .warning, target: .approvals),
            ConnorRuntimeMetricTile(id: .memoryReviews, title: "Memory reviews", value: "\(memoryReviews)", subtitle: "candidates + holds", severity: memoryReviews == 0 ? .success : .warning, target: .graphMemory),
            ConnorRuntimeMetricTile(id: .automationTriggers, title: "Automation triggers", value: "\(automationTriggers.count)", subtitle: "recent governed actions", severity: automationTriggers.contains { $0.requiresReview } ? .warning : .info, target: .automation)
        ]
        metrics.append(ConnorRuntimeMetricTile(
            id: .nativeUIHealth,
            title: "Native UI",
            value: "ready",
            subtitle: "shell · commands · settings",
            severity: .success,
            target: .home
        ))
        if let commercialReadinessDashboard {
            metrics.append(ConnorRuntimeMetricTile(
                id: .commercialReadiness,
                title: "Commercial readiness",
                value: "\(commercialReadinessDashboard.readyCount)/\(commercialReadinessDashboard.cards.count)",
                subtitle: commercialReadinessDashboard.overallStatus == .ready ? "all phases ready" : "blocked phases require review",
                severity: commercialReadinessDashboard.overallStatus == .ready ? .success : .warning,
                target: .productOS
            ))
        }

        let timelineItems = events.map { event in
            ConnorRuntimeCenterItem(
                id: event.id,
                title: event.title,
                subtitle: event.kind,
                detail: event.detail,
                severity: event.severity,
                target: .agentChat
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

        let nextBestActions = buildNextBestActions(
            pendingApprovals: pendingApprovals,
            memoryReviews: memoryReviews,
            automationTriggers: automationTriggers,
            commercialReadinessDashboard: commercialReadinessDashboard
        )

        var sections = [
            ConnorRuntimeCenterSection(id: .nextBestActions, title: "Next Best Actions", subtitle: "Recommended commercial operations", items: nextBestActions, target: nextBestActions.first?.target),
            ConnorRuntimeCenterSection(id: .runTimeline, title: "Run Timeline", subtitle: "Latest agent events", items: timelineItems, target: .agentChat),
            ConnorRuntimeCenterSection(id: .reviewQueue, title: "Review Queue", subtitle: "Permissions and human gates", items: approvalItems, target: .approvals),
            ConnorRuntimeCenterSection(id: .graphMemory, title: "Graph Memory Core", subtitle: "Context, feedback, review", items: memoryItems, target: .graphMemory),
            ConnorRuntimeCenterSection(id: .automation, title: "Automation", subtitle: "Governed triggers", items: automationItems, target: .automation)
        ]
        if let commercialReadinessDashboard {
            sections.append(ConnorRuntimeCenterSection(
                id: .commercialReadiness,
                title: "Commercial Readiness",
                subtitle: commercialReadinessDashboard.summary,
                items: commercialReadinessDashboard.cards.map { card in
                    ConnorRuntimeCenterItem(
                        id: card.id,
                        title: card.title,
                        subtitle: card.status.rawValue,
                        detail: card.evidence,
                        severity: card.status == .ready ? .success : .warning,
                        target: card.target
                    )
                },
                target: .productOS
            ))
        }

        return ConnorRuntimeCenterPresentation(
            hero: hero,
            metricTiles: metrics,
            sections: sections,
            nextBestActions: nextBestActions
        )
    }

    private static func buildNextBestActions(
        pendingApprovals: [AgentPendingApproval],
        memoryReviews: Int,
        automationTriggers: [ProductOSAutomationTriggerRecord],
        commercialReadinessDashboard: CommercialReadinessDashboard?
    ) -> [ConnorRuntimeCenterItem] {
        var actions: [ConnorRuntimeCenterItem] = []
        if !pendingApprovals.isEmpty {
            actions.append(ConnorRuntimeCenterItem(id: "next.approvals", title: "Review pending approvals", subtitle: "\(pendingApprovals.count) human gates", detail: "Resolve permission requests before continuing autonomous work.", severity: .warning, target: .approvals))
        }
        if memoryReviews > 0 {
            actions.append(ConnorRuntimeCenterItem(id: "next.memory", title: "Process graph memory reviews", subtitle: "\(memoryReviews) candidates or holds", detail: "Promote, hold, or reject memory candidates through Connor governance.", severity: .warning, target: .graphMemory))
        }
        if automationTriggers.contains(where: { $0.requiresReview }) {
            actions.append(ConnorRuntimeCenterItem(id: "next.automation", title: "Inspect automation review triggers", subtitle: "Governed automation", detail: "Review automation triggers that requested human confirmation.", severity: .warning, target: .automation))
        }
        if let commercialReadinessDashboard, commercialReadinessDashboard.blockedCount > 0 {
            actions.append(ConnorRuntimeCenterItem(id: "next.readiness", title: "Fix commercial readiness blockers", subtitle: "\(commercialReadinessDashboard.blockedCount) blocked phases", detail: commercialReadinessDashboard.summary, severity: .warning, target: .productOS))
        }
        if actions.isEmpty {
            actions.append(ConnorRuntimeCenterItem(id: "next.session", title: "Start or continue a session", subtitle: "Commercial runtime ready", detail: "Open Sessions to continue graph-memory-native agent work.", severity: .success, target: .agentChat))
        }
        return actions
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
