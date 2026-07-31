import SwiftUI
import ConnorGraphAgent
import ConnorGraphAppSupport

enum AgentTurnActivityEventResolver {
    static func events(
        initialEvents: [AgentEventPresentation]?,
        loadedEvents: [AgentEventPresentation]?
    ) -> [AgentEventPresentation]? {
        initialEvents ?? loadedEvents
    }
}

private struct AgentTurnActivityEventLoadKey: Hashable {
    var isExpanded: Bool
    var processID: String
    var processState: AgentChatTurnProcessState
    var eventCount: Int
    var lastEventID: String?
}

private struct AgentTurnActivitySummaryLoadKey: Hashable {
    var processID: String
    var processState: AgentChatTurnProcessState
    var eventCount: Int
    var lastEventID: String?
}

struct AgentActivityHeaderDisclosurePresentation: Equatable {
    var showsChevron: Bool
    var systemImage: String

    init(isExpanded: Bool, isHovering: Bool) {
        showsChevron = isExpanded || isHovering
        systemImage = isExpanded ? "chevron.down" : "chevron.right"
    }
}

struct AgentActivityHeaderTextPresentation: Equatable {
    var text: String

    init(statusText: String, toolNames: [String]) {
        if statusText == "正在压缩上下文" {
            text = statusText
            return
        }
        let visibleToolNames = toolNames.filter { !Self.routineToolNames.contains($0) }
        guard !visibleToolNames.isEmpty else {
            text = statusText
            return
        }
        let operationText: String
        if visibleToolNames.count <= 3 {
            operationText = visibleToolNames.joined(separator: "、")
        } else {
            operationText = "\(visibleToolNames.prefix(3).joined(separator: "、"))等"
        }
        text = "\(statusText) · \(operationText)"
    }

    private static let routineToolNames: Set<String> = [
        "获取当前时间",
        "查询近期记忆",
        "搜索短期记忆",
        "查询长期记忆",
        "搜索长期记忆",
        "读取用户偏好",
        "获取用户偏好",
        "搜索笔记"
    ]
}

fileprivate struct AgentTurnActivityPreparedTool: Sendable, Identifiable {
    var id: String { invocation.id }
    var invocation: AgentToolInvocationPresentation
    var activity: AgentToolActivityPresentation
}

private struct AgentTurnActivityDetailPresentation: Sendable {
    var summary: AgentTurnActivitySummaryPresentation
    var tools: [AgentTurnActivityPreparedTool]
}

private enum AgentTurnActivityDetailBuilder {
    nonisolated static func build(
        process: AgentChatTurnProcessPresentation,
        events: [AgentEventPresentation]
    ) -> AgentTurnActivityDetailPresentation? {
        guard !Task.isCancelled else { return nil }
        let summary = AgentTurnActivitySummaryBuilder().summary(process: process, events: events)
        guard !Task.isCancelled else { return nil }
        let invocations = AgentToolInvocationAssembler().invocations(from: events)
        guard !Task.isCancelled else { return nil }
        var tools: [AgentTurnActivityPreparedTool] = []
        tools.reserveCapacity(invocations.count)
        for invocation in invocations {
            guard !Task.isCancelled else { return nil }
            tools.append(AgentTurnActivityPreparedTool(
                invocation: invocation,
                activity: AgentToolActivityPresentation(
                    id: invocation.id,
                    callID: invocation.callID,
                    phase: invocation.phase,
                    rawToolName: invocation.toolName,
                    semanticKind: invocation.semanticKind,
                    title: invocation.title,
                    subtitle: invocation.subtitle,
                    target: invocation.target,
                    detail: invocation.errorText ?? invocation.outputText,
                    icon: invocation.icon,
                    severity: invocation.severity,
                    argumentsJSON: invocation.argumentsJSON,
                    resultJSON: invocation.resultJSON
                )
            ))
        }
        return AgentTurnActivityDetailPresentation(summary: summary, tools: tools)
    }
}

struct AgentChatTurnProcessRow: View {
    var process: AgentChatTurnProcessPresentation
    var isAssistantContinuation = false
    var initialEvents: [AgentEventPresentation]?
    var loadEvents: () async -> [AgentEventPresentation]
    var onOpenToolInvocation: (AgentToolInvocationPresentation) -> Void = { _ in }
    @State private var isExpanded: Bool = false
    @State private var preparedDetail: AgentTurnActivityDetailPresentation?
    @State private var preparedDetailProcessID: String?
    @State private var preparedSummary: AgentTurnActivitySummaryPresentation?
    @State private var preparedSummaryProcessID: String?
    @State private var startedAt: Date = Date()
    @State private var isHoveringHeader = false

    var body: some View {
        let currentDetail = preparedDetailProcessID == process.id ? preparedDetail : nil
        let preparedProcessSummary = currentDetail?.summary
            ?? (preparedSummaryProcessID == process.id ? preparedSummary : nil)
        let summary = preparedProcessSummary
            ?? fallbackSummary
        let isLoadingSummary = initialEvents == nil && preparedProcessSummary == nil
        return HStack(alignment: .top, spacing: AgentChatLayout.spaceS) {
            VStack(alignment: .leading, spacing: 2) {
                Button(action: { isExpanded.toggle() }) {
                    activityHeader(summary, isLoadingSummary: isLoadingSummary)
                }
                .buttonStyle(.plain)
                .onHover { isHovering in
                    withAnimation(.easeOut(duration: 0.12)) {
                        isHoveringHeader = isHovering
                    }
                }

                if isExpanded {
                    Group {
                        if let preparedDetail = currentDetail {
                            AgentTurnActivitySummaryDetailView(
                                summary: preparedDetail.summary,
                                tools: preparedDetail.tools,
                                isRunning: process.state == .running && preparedDetail.summary.state != .waitingForPermission,
                                startedAt: startedAt,
                                onOpenToolInvocation: onOpenToolInvocation
                            )
                        } else {
                            AgentTurnActivityDetailLoadingView()
                        }
                    }
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: AgentTurnActivityEventLoadKey(
            isExpanded: isExpanded,
            processID: process.id,
            processState: process.state,
            eventCount: initialEvents?.count ?? 0,
            lastEventID: initialEvents?.last?.id
        )) {
            guard isExpanded else { return }
            let events: [AgentEventPresentation]
            if let initialEvents {
                events = initialEvents
            } else {
                events = await loadEvents()
            }
            guard !Task.isCancelled else { return }
            do {
                try await Task.sleep(for: .milliseconds(40))
            } catch {
                return
            }
            let preparationTask = Task.detached(priority: .userInitiated) {
                AgentTurnActivityDetailBuilder.build(process: process, events: events)
            }
            let detail = await withTaskCancellationHandler {
                await preparationTask.value
            } onCancel: {
                preparationTask.cancel()
            }
            guard !Task.isCancelled, let detail else { return }
            preparedDetail = detail
            preparedDetailProcessID = process.id
            preparedSummary = detail.summary
            preparedSummaryProcessID = process.id
        }
        .task(id: AgentTurnActivitySummaryLoadKey(
            processID: process.id,
            processState: process.state,
            eventCount: initialEvents?.count ?? 0,
            lastEventID: initialEvents?.last?.id
        )) {
            let events: [AgentEventPresentation]
            if let initialEvents {
                events = initialEvents
            } else {
                events = await loadEvents()
            }
            guard !Task.isCancelled else { return }
            do {
                try await Task.sleep(for: .milliseconds(40))
            } catch {
                return
            }
            let summaryTask = Task.detached(priority: .utility) {
                AgentTurnActivitySummaryBuilder().summary(process: process, events: events)
            }
            let summary = await withTaskCancellationHandler {
                await summaryTask.value
            } onCancel: {
                summaryTask.cancel()
            }
            guard !Task.isCancelled else { return }
            preparedSummary = summary
            preparedSummaryProcessID = process.id
        }
    }

    private var fallbackSummary: AgentTurnActivitySummaryPresentation {
        AgentTurnActivitySummaryBuilder().summary(
            process: process,
            events: AgentActivityFallbackEvents.events(for: process)
        )
    }

    private func activityHeader(
        _ summary: AgentTurnActivitySummaryPresentation,
        isLoadingSummary: Bool
    ) -> some View {
        let disclosure = AgentActivityHeaderDisclosurePresentation(
            isExpanded: isExpanded,
            isHovering: isHoveringHeader
        )
        return HStack(alignment: .center, spacing: AgentChatLayout.spaceS) {
            statusIcon(summary.state, isLoadingSummary: isLoadingSummary, color: activityHeaderForegroundColor)
                .frame(width: AgentChatTypography.controlIconSize, height: AgentChatTypography.controlIconSize)

            activityHeaderTitle(summary, isLoadingSummary: isLoadingSummary)

            if disclosure.showsChevron {
                Image(systemName: disclosure.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(activityHeaderControlColor)
                    .padding(.leading, 2)
                    .transition(.opacity)
            }

            Spacer(minLength: 0)
        }
        .padding(.trailing, AgentChatLayout.spaceM)
        .padding(.vertical, AgentChatLayout.spaceXS)
        .frame(minHeight: AgentChatLayout.activityRowMinHeight)
        .overlay(alignment: .leading) {
            if isAssistantContinuation {
                Capsule(style: .continuous)
                    .fill(continuationAccentColor(for: summary.state))
                    .frame(width: 2, height: 16)
            }
        }
        .contentShape(Rectangle())
    }

    private var emphasizesActivityHeader: Bool {
        isExpanded || isHoveringHeader
    }

    private var activityHeaderForegroundColor: Color {
        Color.primary.opacity(emphasizesActivityHeader ? 0.82 : 0.42)
    }

    private var activityHeaderControlColor: Color {
        Color.primary.opacity(emphasizesActivityHeader ? 0.56 : 0.24)
    }

    @ViewBuilder
    private func activityHeaderTitle(
        _ summary: AgentTurnActivitySummaryPresentation,
        isLoadingSummary: Bool
    ) -> some View {
        let title = isLoadingSummary ? "读取调用记录…" : activityHeaderText(summary)
        if summary.state == .running {
            AgentRunningActivityShimmerText(text: title, baseColor: activityHeaderForegroundColor)
        } else {
            Text(title)
                .font(AgentChatTypography.micro.weight(.medium))
                .foregroundStyle(activityHeaderForegroundColor)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func continuationAccentColor(for state: AgentTurnActivitySummaryState) -> Color {
        switch state {
        case .running:
            ConnorCraftPalette.accent.opacity(0.42)
        case .completed:
            Color.secondary.opacity(0.18)
        case .failed:
            Color.red.opacity(0.34)
        case .cancelled, .waitingForPermission:
            Color.orange.opacity(0.34)
        }
    }

    private func activityHeaderText(_ summary: AgentTurnActivitySummaryPresentation) -> String {
        AgentActivityHeaderTextPresentation(
            statusText: summary.statusText,
            toolNames: summary.toolNames
        ).text
    }

    @ViewBuilder
    private func statusIcon(
        _ state: AgentTurnActivitySummaryState,
        isLoadingSummary: Bool,
        color: Color
    ) -> some View {
        if isLoadingSummary {
            ProgressView()
                .controlSize(.small)
                .fixedSize()
                .tint(color)
        } else {
            switch state {
            case .running:
                ProgressView()
                    .controlSize(.small)
                    .fixedSize()
                    .tint(color)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(color)
            case .failed:
                Image(systemName: "xmark.octagon.fill")
                    .foregroundStyle(color)
            case .cancelled:
                Image(systemName: "slash.circle.fill")
                    .foregroundStyle(color)
            case .waitingForPermission:
                Image(systemName: "lock.fill")
                    .foregroundStyle(color)
            }
        }
    }
}

private struct AgentRunningActivityShimmerText: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var text: String
    var baseColor: Color

    var body: some View {
        Text(text)
            .font(AgentChatTypography.micro.weight(.medium))
            .foregroundStyle(baseColor)
            .lineLimit(1)
            .truncationMode(.tail)
            .overlay {
                if !reduceMotion {
                    GeometryReader { geometry in
                        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                            let duration = 1.8
                            let progress = context.date.timeIntervalSinceReferenceDate
                                .truncatingRemainder(dividingBy: duration) / duration
                            let highlightWidth = max(36, geometry.size.width * 0.24)
                            LinearGradient(
                                colors: [
                                    .clear,
                                    ConnorCraftPalette.accent.opacity(0.28),
                                    Color.primary.opacity(0.72),
                                    ConnorCraftPalette.accent.opacity(0.34),
                                    .clear
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: highlightWidth)
                            .offset(x: -highlightWidth + progress * (geometry.size.width + highlightWidth))
                        }
                    }
                }
            }
            .mask {
                Text(text)
                    .font(AgentChatTypography.micro.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .allowsHitTesting(false)
    }
}

private struct AgentTurnActivityDetailLoadingView: View {
    var body: some View {
        HStack(spacing: AgentChatLayout.spaceS) {
            ProgressView()
                .controlSize(.small)
                .fixedSize()
            Text("正在加载本轮详情…")
                .font(AgentChatTypography.micro)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: AgentChatLayout.activityRowMinHeight, alignment: .leading)
    }
}

struct AgentTurnActivitySummaryDetailView: View {
    var summary: AgentTurnActivitySummaryPresentation
    fileprivate var tools: [AgentTurnActivityPreparedTool]
    var isRunning: Bool
    var startedAt: Date
    var onOpenToolInvocation: (AgentToolInvocationPresentation) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !summary.toolSummaries.isEmpty {
                detailLine(icon: "wrench.and.screwdriver", text: toolSummaryText)
            }

            detailLine(icon: "checklist", text: resultText)

            if summary.isWaitingForPermission {
                detailLine(icon: "lock.fill", text: "当前会话正在等待权限审批，请前往处理", color: .orange)
            }

            if let primaryErrorMessage = summary.primaryErrorMessage {
                detailLine(icon: "exclamationmark.triangle", text: "错误：\(primaryErrorMessage)", color: .red)
            }

            if !tools.isEmpty {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(tools) { tool in
                        AgentToolActivityRow(activity: tool.activity) {
                            AppInteractionPerformance.beginAgentDetail(callID: tool.invocation.callID)
                            onOpenToolInvocation(tool.invocation)
                        }
                    }
                }
                .padding(.top, 2)
            }

            if isRunning {
                AgentActivityLoadingRow(startedAt: startedAt)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var toolSummaryText: String {
        summary.toolSummaries
            .map(\.compactCountText)
            .joined(separator: "、")
    }

    private var resultText: String {
        var parts: [String] = []
        if summary.toolSuccessCount > 0 {
            parts.append("成功 \(summary.toolSuccessCount) 次")
        }
        if summary.toolFailureCount > 0 {
            parts.append("失败 \(summary.toolFailureCount) 次")
        }
        if parts.isEmpty {
            parts.append(summary.statusText)
        }
        return parts.joined(separator: "，")
    }

    private func detailLine(icon: String, text: String, color: Color = .secondary) -> some View {
        Label {
            Text(text)
                .font(AgentChatTypography.micro)
                .foregroundStyle(color)
                .lineLimit(2)
        } icon: {
            Image(systemName: icon)
                .font(.system(size: AgentChatTypography.smallIconSize, weight: .semibold))
                .foregroundStyle(color)
        }
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, minHeight: AgentChatLayout.activityRowMinHeight, alignment: .leading)
    }
}

struct AgentToolActivityRow: View {
    var activity: AgentToolActivityPresentation
    var onOpenDetail: () -> Void

    var body: some View {
        Button(action: onOpenDetail) {
            HStack(spacing: AgentChatLayout.spaceS) {
                Image(systemName: leadingIcon)
                    .font(.system(size: AgentChatTypography.chevronIconSize, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: AgentChatTypography.controlIconSize)

                Text(activity.title)
                    .font(AgentChatTypography.micro.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let visibleTarget {
                    Text(visibleTarget)
                        .font(AgentChatTypography.monoMicro)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .frame(height: AgentChatLayout.chipHeight)
                        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusS, style: .continuous))
                }

                if let visibleSubtitle {
                    Text(visibleSubtitle)
                        .font(AgentChatTypography.micro)
                        .foregroundStyle(activity.severity == .error ? AnyShapeStyle(Color.red) : AnyShapeStyle(.tertiary))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Text(phaseText)
                    .font(AgentChatTypography.monoMicro)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: AgentChatTypography.smallIconSize, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 1)
            .frame(minHeight: AgentChatLayout.activityRowMinHeight)
            .contentShape(RoundedRectangle(cornerRadius: AgentChatLayout.radiusS, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var leadingIcon: String {
        if activity.severity == .error { return "xmark.octagon" }
        switch activity.phase {
        case .finished: return "checkmark.circle"
        case .failed: return "xmark.octagon"
        default: return activity.icon
        }
    }

    private var phaseText: String {
        switch activity.phase {
        case .requested: return "等待执行"
        case .approved: return "已授权"
        case .running: return "执行中"
        case .finished: return "已完成"
        case .failed: return "失败"
        }
    }

    private var visibleSubtitle: String? {
        guard let subtitle = activity.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines), !subtitle.isEmpty else { return nil }
        let genericStates = ["done", "finished", "running", "queued", "approved", "success", "failed", "error"]
        return genericStates.contains(subtitle.lowercased()) ? nil : subtitle
    }

    private var visibleTarget: String? {
        guard let target = activity.target?.trimmingCharacters(in: .whitespacesAndNewlines), !target.isEmpty else { return nil }
        if target.caseInsensitiveCompare(activity.rawToolName) == .orderedSame { return nil }
        if target.hasPrefix("mcp__") { return nil }
        return target
    }

    private var color: Color {
        switch activity.severity {
        case .info: return .secondary
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}

struct AgentActivityLoadingRow: View {
    var startedAt: Date

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 1)) { context in
            HStack(spacing: AgentChatLayout.spaceS) {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: AgentChatTypography.controlIconSize, height: AgentChatTypography.controlIconSize)
                    .fixedSize()
                Text("忙碌中…")
                    .font(AgentChatTypography.micro.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(Self.elapsedText(from: startedAt, to: context.date))
                    .font(AgentChatTypography.micro.monospacedDigit())
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
            .padding(.trailing, AgentChatLayout.spaceM)
            .padding(.vertical, 3)
            .frame(minHeight: AgentChatLayout.activityRowMinHeight)
            .contentShape(RoundedRectangle(cornerRadius: AgentChatLayout.radiusS, style: .continuous))
        }
    }

    private static func elapsedText(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        let minutes = seconds / 60
        let remainder = seconds % 60
        if minutes >= 60 {
            let hours = minutes / 60
            let minuteRemainder = minutes % 60
            return "\(hours):\(String(format: "%02d", minuteRemainder)):\(String(format: "%02d", remainder))"
        }
        return "\(minutes):\(String(format: "%02d", remainder))"
    }
}

struct AgentActivityEventRow: View {
    var event: AgentEventPresentation

    var body: some View {
        HStack(spacing: AgentChatLayout.spaceS) {
            Image(systemName: icon)
                .font(.system(size: AgentChatTypography.chevronIconSize, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: AgentChatTypography.controlIconSize)
            Text(event.title)
                .font(AgentChatTypography.micro.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            AgentMarkdownPreviewText(markdown: event.detail, font: AgentChatTypography.micro, lineLimit: 1)
                .foregroundStyle(.tertiary)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if let occurredAt = event.occurredAt {
                Text(occurredAt.formatted(date: .omitted, time: .standard))
                    .font(AgentChatTypography.micro.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Text(event.kind)
                .font(AgentChatTypography.monoMicro)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Image(systemName: "arrow.up.right")
                .font(.system(size: AgentChatTypography.smallIconSize, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, AgentChatLayout.spaceM)
        .padding(.vertical, 2)
        .frame(minHeight: AgentChatLayout.activityRowMinHeight)
        .contentShape(RoundedRectangle(cornerRadius: AgentChatLayout.radiusS, style: .continuous))
    }

    private var icon: String {
        switch event.severity {
        case .info: return "circle.dashed"
        case .success: return "checkmark.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        }
    }

    private var color: Color {
        switch event.severity {
        case .info: return .secondary
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}

enum AgentActivityFallbackEvents {
    static func events(for process: AgentChatTurnProcessPresentation) -> [AgentEventPresentation] {
        var items: [AgentEventPresentation] = []
        if let request = process.currentRequest, hasVisibleText(request) {
            items.append(AgentEventPresentation(kind: "user_input", title: "User prompt", detail: request, severity: .info, runID: nil, sessionID: nil))
        }
        if !process.expandedContextItems.isEmpty {
            items.append(AgentEventPresentation(kind: "context", title: "Context assembled", detail: "使用了 \(process.expandedContextItems.count) 个图谱上下文项", severity: .info, runID: nil, sessionID: nil))
        }
        if !process.citationIDs.isEmpty {
            items.append(AgentEventPresentation(kind: "citations", title: "Citations attached", detail: process.citationIDs.joined(separator: ", "), severity: .success, runID: nil, sessionID: nil))
        }
        if let response = process.assistantResponse, hasVisibleText(response) {
            items.append(AgentEventPresentation(kind: "assistant_response", title: "Answer completed", detail: response, severity: .success, runID: nil, sessionID: nil))
        }
        if items.isEmpty {
            items.append(AgentEventPresentation(kind: "activity", title: process.state == .running ? "Processing" : "Activity", detail: process.summary, severity: process.state == .running ? .info : .success, runID: nil, sessionID: nil))
        }
        return items
    }

    private static func hasVisibleText(_ text: String) -> Bool {
        text.contains { !$0.isWhitespace }
    }
}
