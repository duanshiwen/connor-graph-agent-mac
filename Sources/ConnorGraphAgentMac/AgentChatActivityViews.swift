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
                            if event.severity == .success {
                                Image("ConnorComplete")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 64, height: 64)
                                    .accessibilityHidden(true)
                            }
                            AgentMarkdownPreviewText(markdown: event.detail, font: AgentChatTypography.micro, lineLimit: 3)
                                .foregroundStyle(.secondary)
                                .frame(width: 220, alignment: .leading)
                            HStack(spacing: AgentChatLayout.spaceS) {
                                Text(event.kind)
                                    .font(AgentChatTypography.monoMicro)
                                if let occurredAt = event.occurredAt {
                                    Text(occurredAt.formatted(date: .omitted, time: .standard))
                                        .font(AgentChatTypography.micro.monospacedDigit())
                                }
                            }
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
    /// 静态加载视图：不再使用 30fps TimelineView 流光，改用系统 ProgressView（低 CPU）。
    var body: some View {
        VStack(spacing: 14) {
            Image("ConnorEmpty")
                .resizable()
                .scaledToFit()
                .frame(width: 132, height: 132)
                .accessibilityHidden(true)
            ProgressView()
                .controlSize(.small)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, AgentChatLayout.spaceXL)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在加载会话数据")
    }
}

/// 欢迎区采用朝朝的图文分区，窄屏自动堆叠；正文保持原有康纳提示语。
struct AgentChatEmptyStateView: View {
    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 680
            ScrollView {
                Group {
                    if wide {
                        HStack(spacing: 0) {
                            artwork.frame(width: min(geometry.size.width * 0.43, 380), height: 300)
                            copy.padding(28).frame(maxWidth: .infinity)
                        }
                    } else {
                        VStack(spacing: 0) {
                            artwork.frame(height: geometry.size.height < 440 ? 112 : 180)
                            copy.padding(20)
                        }
                    }
                }
                .background(ConnorCraftPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .frame(maxWidth: 880)
                .padding(wide ? 28 : 16)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }
    }

    private var artwork: some View {
        GeometryReader { geometry in
            Image("ConnorWelcome")
                .resizable()
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .accessibilityHidden(true)
        }
    }

    private var copy: some View {
        VStack(spacing: 12) {
            Text("我是康纳同学，你的私人小助理")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(ConnorCraftPalette.foreground)
            Text("我是一个有记忆、可以和你一起成长进化的 AI Agent。我会记得我们一起经历和做过的事情，在每一次相处中更懂你，也帮你把工作和生活中的想法一步步变成行动。")
                .font(.system(size: 16))
                .foregroundStyle(ConnorCraftPalette.foreground.opacity(0.78))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 440)
        }
        .multilineTextAlignment(.center)
    }
}
