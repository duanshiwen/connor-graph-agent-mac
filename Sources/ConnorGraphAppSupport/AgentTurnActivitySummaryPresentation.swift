import Foundation

public enum AgentTurnActivitySummaryState: String, Sendable, Equatable {
    case running
    case completed
    case failed
    case cancelled
    case waitingForPermission
}

public struct AgentTurnActivityToolSummary: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    public var requestedCount: Int
    public var runningCount: Int
    public var successCount: Int
    public var failureCount: Int

    public init(name: String, requestedCount: Int = 0, runningCount: Int = 0, successCount: Int = 0, failureCount: Int = 0) {
        self.name = name
        self.requestedCount = requestedCount
        self.runningCount = runningCount
        self.successCount = successCount
        self.failureCount = failureCount
    }

    public var totalCount: Int {
        requestedCount + runningCount + successCount + failureCount
    }

    public var compactCountText: String {
        let count = max(totalCount, 1)
        return count > 1 ? "\(name) × \(count)" : name
    }
}

public struct AgentTurnActivitySummaryPresentation: Sendable, Equatable {
    public var state: AgentTurnActivitySummaryState
    public var turnNumber: Int
    public var title: String
    public var statusText: String
    public var subtitle: String
    public var compactToolText: String
    public var toolNames: [String]
    public var toolSummaries: [AgentTurnActivityToolSummary]
    public var toolCallCount: Int
    public var toolSuccessCount: Int
    public var toolFailureCount: Int
    public var hasPermissionRequest: Bool
    public var primaryErrorMessage: String?
    public var eventCount: Int

    public init(
        state: AgentTurnActivitySummaryState,
        turnNumber: Int,
        title: String,
        statusText: String,
        subtitle: String,
        compactToolText: String,
        toolNames: [String],
        toolSummaries: [AgentTurnActivityToolSummary],
        toolCallCount: Int,
        toolSuccessCount: Int,
        toolFailureCount: Int,
        hasPermissionRequest: Bool,
        primaryErrorMessage: String?,
        eventCount: Int
    ) {
        self.state = state
        self.turnNumber = turnNumber
        self.title = title
        self.statusText = statusText
        self.subtitle = subtitle
        self.compactToolText = compactToolText
        self.toolNames = toolNames
        self.toolSummaries = toolSummaries
        self.toolCallCount = toolCallCount
        self.toolSuccessCount = toolSuccessCount
        self.toolFailureCount = toolFailureCount
        self.hasPermissionRequest = hasPermissionRequest
        self.primaryErrorMessage = primaryErrorMessage
        self.eventCount = eventCount
    }
}

public struct AgentTurnActivitySummaryBuilder: Sendable {
    public init() {}

    public func summary(process: AgentChatTurnProcessPresentation, events: [AgentEventPresentation]) -> AgentTurnActivitySummaryPresentation {
        let toolSummaries = toolSummaries(from: events)
        let toolNames = toolSummaries.map(\.name)
        let toolCallCount = toolSummaries.reduce(0) { $0 + $1.requestedCount }
        let toolSuccessCount = toolSummaries.reduce(0) { $0 + $1.successCount }
        let toolFailureCount = toolSummaries.reduce(0) { $0 + $1.failureCount }
        let hasPermissionRequest = events.contains { $0.kind == "permissionRequested" }
        let primaryErrorMessage = events.first(where: { $0.severity == .error })?.detail.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let state = state(for: process, events: events, hasPermissionRequest: hasPermissionRequest)
        let statusText = statusText(for: state)
        let compactToolText = compactToolText(for: toolNames)
        let title = "第 \(process.turnNumber) 轮 · \(statusText)"
        let subtitle = subtitle(
            state: state,
            compactToolText: compactToolText,
            firstFailedTool: toolSummaries.first(where: { $0.failureCount > 0 })?.name,
            primaryErrorMessage: primaryErrorMessage,
            eventCount: events.count
        )

        return AgentTurnActivitySummaryPresentation(
            state: state,
            turnNumber: process.turnNumber,
            title: title,
            statusText: statusText,
            subtitle: subtitle,
            compactToolText: compactToolText,
            toolNames: toolNames,
            toolSummaries: toolSummaries,
            toolCallCount: toolCallCount,
            toolSuccessCount: toolSuccessCount,
            toolFailureCount: toolFailureCount,
            hasPermissionRequest: hasPermissionRequest,
            primaryErrorMessage: primaryErrorMessage,
            eventCount: events.count
        )
    }

    private func state(for process: AgentChatTurnProcessPresentation, events: [AgentEventPresentation], hasPermissionRequest: Bool) -> AgentTurnActivitySummaryState {
        // A failed tool call is recoverable: the agent loop may retry, choose another path,
        // or continue producing a final answer. Only an explicit run-level failure should mark
        // the whole turn as failed. This prevents an in-progress turn from showing “已失败”
        // just because one tool invocation failed along the way.
        if events.contains(where: { $0.kind == "runFailed" }) {
            return .failed
        }
        if hasPermissionRequest && !events.contains(where: { $0.kind == "permissionResolved" && $0.severity == .success }) {
            return .waitingForPermission
        }
        if process.state == .cancelled || events.contains(where: { $0.title.localizedCaseInsensitiveContains("cancelled") }) {
            return .cancelled
        }
        if process.state == .running {
            return .running
        }
        return .completed
    }

    private func statusText(for state: AgentTurnActivitySummaryState) -> String {
        switch state {
        case .running: return "正在处理"
        case .completed: return "已完成"
        case .failed: return "已失败"
        case .cancelled: return "已取消"
        case .waitingForPermission: return "等待确认"
        }
    }

    private func subtitle(
        state: AgentTurnActivitySummaryState,
        compactToolText: String,
        firstFailedTool: String?,
        primaryErrorMessage: String?,
        eventCount: Int
    ) -> String {
        var parts: [String] = []
        switch state {
        case .running:
            let runningToolText = compactToolText == "未调用工具" ? compactToolText : compactToolText.replacingOccurrences(of: "使用 ", with: "正在使用 ")
            parts.append(runningToolText)
        case .failed:
            if let firstFailedTool, let primaryErrorMessage {
                parts.append("\(firstFailedTool) 失败：\(primaryErrorMessage)")
            } else if let primaryErrorMessage {
                parts.append("失败：\(primaryErrorMessage)")
            }
            parts.append(compactToolText)
        case .waitingForPermission:
            parts.append("等待权限确认")
            parts.append(compactToolText)
        case .cancelled:
            parts.append("运行已取消")
            parts.append(compactToolText)
        case .completed:
            parts.append(compactToolText)
        }
        parts.append("\(eventCount) 个底层事件")
        return parts.joined(separator: " · ")
    }

    private func compactToolText(for toolNames: [String]) -> String {
        guard !toolNames.isEmpty else { return "未调用工具" }
        if toolNames.count <= 3 {
            return "使用 \(toolNames.joined(separator: "、"))"
        }
        return "使用 \(toolNames.prefix(3).joined(separator: "、")) 等 \(toolNames.count) 个工具"
    }

    private func toolSummaries(from events: [AgentEventPresentation]) -> [AgentTurnActivityToolSummary] {
        var orderedNames: [String] = []
        var summaries: [String: AgentTurnActivityToolSummary] = [:]

        for event in events {
            guard let parsed = parseToolEvent(event) else { continue }
            if summaries[parsed.name] == nil {
                orderedNames.append(parsed.name)
                summaries[parsed.name] = AgentTurnActivityToolSummary(name: parsed.name)
            }
            var summary = summaries[parsed.name] ?? AgentTurnActivityToolSummary(name: parsed.name)
            switch parsed.phase {
            case .requested: summary.requestedCount += 1
            case .running: summary.runningCount += 1
            case .finished: summary.successCount += 1
            case .failed: summary.failureCount += 1
            }
            summaries[parsed.name] = summary
        }

        return orderedNames.compactMap { summaries[$0] }
    }

    private enum ToolPhase {
        case requested
        case running
        case finished
        case failed
    }

    private func parseToolEvent(_ event: AgentEventPresentation) -> (name: String, phase: ToolPhase)? {
        if let activity = event.toolActivity {
            let name = activity.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            return (name, phase(from: activity.phase))
        }

        let mappings: [(prefix: String, phase: ToolPhase)] = [
            ("Tool requested: ", .requested),
            ("Tool running: ", .running),
            ("Tool finished: ", .finished),
            ("Tool failed: ", .failed),
            ("Tool approved: ", .requested)
        ]
        for mapping in mappings where event.title.hasPrefix(mapping.prefix) {
            let name = String(event.title.dropFirst(mapping.prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            return (name, mapping.phase)
        }
        return nil
    }

    private func phase(from activityPhase: AgentToolActivityPhase) -> ToolPhase {
        switch activityPhase {
        case .requested: .requested
        case .approved: .requested
        case .running: .running
        case .finished: .finished
        case .failed: .failed
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
