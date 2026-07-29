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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = Date()

    var body: some View {
        if reduceMotion {
            loadingIcon(lightProgress: nil)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                loadingIcon(
                    lightProgress: AgentChatLoadingLightEffect.progress(
                        elapsed: context.date.timeIntervalSince(startedAt)
                    )
                )
            }
        }
    }

    private func loadingIcon(lightProgress: Double?) -> some View {
        let icon = Image("ConnorAvatar")
            .resizable()
            .scaledToFit()
        return icon
            .opacity(0.62)
            .overlay {
                if let lightProgress {
                    GeometryReader { geometry in
                        let highlightWidth = max(24, geometry.size.width * 0.34)
                        LinearGradient(
                            colors: [
                                .clear,
                                Color.white.opacity(0.18),
                                Color.white.opacity(0.92),
                                ConnorCraftPalette.accent.opacity(0.28),
                                .clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: highlightWidth)
                        .offset(
                            x: -highlightWidth
                                + CGFloat(lightProgress) * (geometry.size.width + highlightWidth)
                        )
                    }
                    .mask(icon)
                }
            }
            .frame(width: 72, height: 72)
            .padding(.horizontal, AgentChatLayout.spaceXL)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("正在加载会话数据")
    }
}

enum AgentChatLoadingLightEffect {
    static let cycleDuration: TimeInterval = 3.6

    static func progress(elapsed: TimeInterval) -> Double {
        max(0, elapsed).truncatingRemainder(dividingBy: cycleDuration) / cycleDuration
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
            Text("我是康纳同学，你的私人小助理")
                .font(AgentChatTypography.title)
            Text("我是一个有记忆、可以和你一起成长进化的 AI Agent。我会记得我们一起经历和做过的事情，在每一次相处中更懂你，也帮你把工作和生活中的想法一步步变成行动。")
                .font(AgentChatTypography.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
