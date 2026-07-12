import SwiftUI
import ConnorGraphAgent
import ConnorGraphAppSupport

struct AgentEventTimelineView: View {
    var events: [AgentEventPresentation]

    var body: some View {
        DisclosureGroup {
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: AgentChatLayout.spaceM) {
                    ForEach(events) { event in
                        VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                            HStack(spacing: AgentChatLayout.spaceS) {
                                Image(systemName: icon(for: event.severity))
                                    .foregroundStyle(color(for: event.severity))
                                Text(event.title)
                                    .font(AgentChatTypography.metaEmphasis)
                                    .lineLimit(1)
                            }
                            AgentMarkdownPreviewText(markdown: event.detail, font: AgentChatTypography.micro, lineLimit: 3)
                                .foregroundStyle(.secondary)
                                .frame(width: 220, alignment: .leading)
                            Text(event.kind)
                                .font(AgentChatTypography.monoMicro)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(AgentChatLayout.spaceM)
                        .frame(width: 250, alignment: .leading)
                        .background(.quaternary.opacity(0.16), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusM, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AgentChatLayout.radiusM, style: .continuous)
                                .stroke(color(for: event.severity).opacity(0.28), lineWidth: 1)
                        )
                    }
                }
                .padding(.vertical, 4)
            }
        } label: {
            Label("Agent 运行时间线（\(events.count) 个事件）", systemImage: "point.3.connected.trianglepath.dotted")
                .font(AgentChatTypography.metaEmphasis)
        }
    }

    private func icon(for severity: AgentEventPresentationSeverity) -> String {
        switch severity {
        case .info: return "circle"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private func color(for severity: AgentEventPresentationSeverity) -> Color {
        switch severity {
        case .info: return .secondary
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}

struct AgentChatSessionLoadingView: View {
    var body: some View {
        VStack(spacing: AgentChatLayout.spaceM) {
            ProgressView()
                .controlSize(.regular)
            Text("正在加载会话…")
                .font(AgentChatTypography.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在加载会话")
    }
}

struct AgentChatEmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image("ConnorAvatar")
                .resizable()
                .scaledToFit()
                .frame(width: AgentChatTypography.largeIconSize, height: AgentChatTypography.largeIconSize)
                .accessibilityHidden(true)
            Text("我是康纳同学，你的个人助理")
                .font(AgentChatTypography.title)
            Text("我会忠实、可靠、勤奋地陪你处理工作与生活：整理资料、推进任务、安排日程、分析浏览内容，并结合你的长期记忆和当前上下文，帮你把信息汇总成更好的判断与下一步行动。")
                .font(AgentChatTypography.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
