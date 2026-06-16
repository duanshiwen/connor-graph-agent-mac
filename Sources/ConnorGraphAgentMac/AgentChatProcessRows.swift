import SwiftUI
import ConnorGraphAgent
import ConnorGraphAppSupport

struct AgentChatTurnProcessRow: View {
    var process: AgentChatTurnProcessPresentation
    var events: [AgentEventPresentation]
    var onOpenDetail: (AgentEventPresentation) -> Void
    var onOpenToolInvocation: (AgentToolInvocationPresentation) -> Void = { _ in }
    @State private var isExpanded: Bool = false
    @State private var startedAt: Date = Date()

    private var visibleEvents: [AgentEventPresentation] {
        events.isEmpty ? AgentActivityFallbackEvents.events(for: process) : events
    }

    private var summary: AgentTurnActivitySummaryPresentation {
        AgentTurnActivitySummaryBuilder().summary(process: process, events: visibleEvents)
    }

    var body: some View {
        HStack(alignment: .top, spacing: AgentChatLayout.spaceS) {
            VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                Button(action: { withAnimation(.easeOut(duration: 0.16)) { isExpanded.toggle() } }) {
                    activityHeader(summary)
                }
                .buttonStyle(.plain)

                if isExpanded {
                    AgentTurnActivitySummaryDetailView(
                        summary: summary,
                        events: visibleEvents,
                        isRunning: process.state == .running,
                        startedAt: startedAt,
                        onOpenDetail: onOpenDetail,
                        onOpenToolInvocation: onOpenToolInvocation
                    )
                    .padding(.leading, AgentChatLayout.iconButtonSize + AgentChatLayout.spaceM)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func activityHeader(_ summary: AgentTurnActivitySummaryPresentation) -> some View {
        HStack(alignment: .center, spacing: AgentChatLayout.spaceS) {
            statusIcon(summary.state)
                .frame(width: AgentChatTypography.controlIconSize, height: AgentChatTypography.controlIconSize)

            Text("\(summary.title) · \(summary.subtitle)")
                .font(AgentChatTypography.micro.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: AgentChatTypography.chevronIconSize, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, AgentChatLayout.spaceM)
        .padding(.vertical, AgentChatLayout.spaceXS)
        .frame(minHeight: AgentChatLayout.activityRowMinHeight)
        .background(Color.clear)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func statusIcon(_ state: AgentTurnActivitySummaryState) -> some View {
        switch state {
        case .running:
            ProgressView()
                .controlSize(.small)
                .fixedSize()
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "slash.circle.fill")
                .foregroundStyle(.orange)
        case .waitingForPermission:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}

struct AgentTurnActivitySummaryDetailView: View {
    var summary: AgentTurnActivitySummaryPresentation
    var events: [AgentEventPresentation]
    var isRunning: Bool
    var startedAt: Date
    var onOpenDetail: (AgentEventPresentation) -> Void
    var onOpenToolInvocation: (AgentToolInvocationPresentation) -> Void
    @State private var showsRawEvents = false

    var body: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceXS) {
            if !summary.toolSummaries.isEmpty {
                detailLine(icon: "wrench.and.screwdriver", text: "工具：\(toolSummaryText)")
            }

            detailLine(icon: "checklist", text: resultText)

            if summary.hasPermissionRequest {
                detailLine(icon: "hand.raised", text: "权限：等待用户确认后继续")
            }

            if let primaryErrorMessage = summary.primaryErrorMessage {
                detailLine(icon: "exclamationmark.triangle", text: "错误：\(primaryErrorMessage)", color: .red)
            }

            if !toolInvocations.isEmpty {
                VStack(alignment: .leading, spacing: AgentChatLayout.spaceXS) {
                    ForEach(toolInvocations) { invocation in
                        AgentToolActivityRow(activity: activityPresentation(for: invocation)) {
                            onOpenToolInvocation(invocation)
                        }
                    }
                }
                .padding(.top, AgentChatLayout.spaceXS)
            }

            if isRunning {
                AgentActivityLoadingRow(startedAt: startedAt)
                    .padding(.leading, -AgentChatLayout.spaceM)
            }

            DisclosureGroup(isExpanded: $showsRawEvents) {
                VStack(alignment: .leading, spacing: AgentChatLayout.spaceXS) {
                    ForEach(events) { event in
                        Button(action: { onOpenDetail(event) }) {
                            AgentActivityEventRow(event: event)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, AgentChatLayout.spaceXS)
            } label: {
                Label("查看底层事件（\(events.count)）", systemImage: "ladybug")
                    .font(AgentChatTypography.micro.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
            .tint(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var toolInvocations: [AgentToolInvocationPresentation] {
        AgentToolInvocationAssembler().invocations(from: events)
    }

    private func activityPresentation(for invocation: AgentToolInvocationPresentation) -> AgentToolActivityPresentation {
        AgentToolActivityPresentation(
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
        parts.append("底层事件 \(summary.eventCount) 个")
        return "结果：\(parts.joined(separator: "，"))"
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
        .padding(.horizontal, AgentChatLayout.spaceM)
        .padding(.vertical, 2)
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

                if let target = activity.target, !target.isEmpty {
                    Text(target)
                        .font(AgentChatTypography.monoMicro)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .frame(height: AgentChatLayout.chipHeight)
                        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusS, style: .continuous))
                }

                if let subtitle = activity.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
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
            .padding(.horizontal, AgentChatLayout.spaceM)
            .padding(.vertical, 2)
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
        case .requested: return "queued"
        case .approved: return "approved"
        case .running: return "running"
        case .finished: return "done"
        case .failed: return "error"
        }
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
            .padding(.horizontal, AgentChatLayout.spaceM)
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
        if let request = process.currentRequest, !request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(AgentEventPresentation(kind: "user_input", title: "User prompt", detail: request, severity: .info, runID: nil, sessionID: nil))
        }
        if !process.expandedContextItems.isEmpty {
            items.append(AgentEventPresentation(kind: "context", title: "Context assembled", detail: "使用了 \(process.expandedContextItems.count) 个图谱上下文项", severity: .info, runID: nil, sessionID: nil))
        }
        if !process.citationIDs.isEmpty {
            items.append(AgentEventPresentation(kind: "citations", title: "Citations attached", detail: process.citationIDs.joined(separator: ", "), severity: .success, runID: nil, sessionID: nil))
        }
        if let response = process.assistantResponse, !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(AgentEventPresentation(kind: "assistant_response", title: "Answer completed", detail: response, severity: .success, runID: nil, sessionID: nil))
        }
        if items.isEmpty {
            items.append(AgentEventPresentation(kind: "activity", title: process.state == .running ? "Processing" : "Activity", detail: process.summary, severity: process.state == .running ? .info : .success, runID: nil, sessionID: nil))
        }
        return items
    }
}

