import SwiftUI
import ConnorGraphAgent
import ConnorGraphAppSupport

struct AgentActivityDetailOverlay: View {
    var event: AgentEventPresentation
    var onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Label("Activity", systemImage: "info.circle")
                        .font(AgentChatTypography.meta.weight(.medium))
                        .padding(.horizontal, AgentChatLayout.spaceS)
                        .frame(height: AgentChatLayout.chipHeight)
                        .background(Color.clear, in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusS, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AgentChatLayout.radiusS, style: .continuous)
                                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                        )
                    Spacer()

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: AgentChatTypography.controlIconSize, weight: .semibold))
                            .frame(width: AgentChatLayout.iconButtonSize, height: AgentChatLayout.iconButtonSize)
                    }
                    .buttonStyle(.plain)
                    .frame(width: AgentChatLayout.hitTargetSize, height: AgentChatLayout.hitTargetSize)
                    .contentShape(Rectangle())
                    .keyboardShortcut(.escape, modifiers: [])
                }
                .padding(AgentChatLayout.spaceM)

                Spacer(minLength: 0)

                ScrollView {
                    VStack(alignment: .leading, spacing: AgentChatLayout.spaceM) {
                        HStack(spacing: AgentChatLayout.spaceS) {
                            Text(event.title)
                                .font(AgentChatTypography.sectionTitle)
                            Text(event.kind)
                                .font(AgentChatTypography.monoMicro)
                                .foregroundStyle(.tertiary)
                            Spacer()
                        }
                        AgentMarkdownPreviewText(markdown: event.detail, font: AgentChatTypography.body)
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: 900, alignment: .leading)
                    .padding(AgentChatLayout.spaceXL)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.48), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous)
                            .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                    )
                }
                .frame(maxWidth: .infinity)

                Spacer(minLength: 0)
            }
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.96), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusXL, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AgentChatLayout.radiusXL, style: .continuous)
                    .stroke(Color.secondary.opacity(0.20), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 14)
            .padding(AgentChatLayout.spaceXL)
        }
    }
}

struct AgentChatPendingAssistantRow: View {
    var pending: AgentChatPendingAssistantPresentation

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: AgentChatLayout.spaceM) {
                HStack(spacing: AgentChatLayout.spaceS) {
                    Text("助手")
                        .font(AgentChatTypography.metaEmphasis)
                        .foregroundStyle(.secondary)
                    Text("第 \(pending.turnNumber) 轮")
                        .font(AgentChatTypography.micro)
                        .foregroundStyle(.secondary)
                    ProgressView()
                        .controlSize(.regular)
                        .frame(width: 14, height: 14)
                        .fixedSize()
                    Text(pending.title)
                        .font(AgentChatTypography.meta)
                        .foregroundStyle(.secondary)
                }

                ThinkingDotsView()

                DisclosureGroup {
                    VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                        Label(pending.processingSummary, systemImage: "magnifyingglass")
                        Label("正在组装近期对话和可选会话摘要", systemImage: "text.bubble")
                        Label("正在调用已配置的模型提供方", systemImage: "network")
                    }
                    .font(AgentChatTypography.meta)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                } label: {
                    Text("处理中")
                        .font(AgentChatTypography.metaEmphasis)
                }
                .font(AgentChatTypography.meta)
            }
            .padding(AgentChatLayout.spaceM)
            .frame(maxWidth: AgentChatLayout.messageMaxWidth, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.85), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous)
                    .stroke(Color.secondary.opacity(AgentChatLayout.hairlineOpacity), lineWidth: 1)
            )

            Spacer(minLength: AgentChatLayout.messageSideInset)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ThinkingDotsView: View {
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary.opacity(0.65))
                    .frame(width: 6, height: 6)
                    .opacity(index == 0 ? 1.0 : 0.45)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.18), in: Capsule())
    }
}

struct AgentChatTurnInspectorView: View {
    var row: AgentChatMessagePresentation

    var body: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
            if let summary = row.turnMetadataSummary {
                HStack(spacing: AgentChatLayout.spaceS) {
                    Image(systemName: "info.circle")
                    AgentMarkdownPreviewText(markdown: summary, font: AgentChatTypography.meta, lineLimit: 1)
                    Spacer(minLength: 0)
                }
                .font(AgentChatTypography.meta)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            DisclosureGroup {
                VStack(alignment: .leading, spacing: AgentChatLayout.spaceM) {
                    if let request = row.currentRequest {
                        MetadataBlock(title: "当前请求", text: request)
                    }

                    if !row.citationIDs.isEmpty {
                        MetadataChips(title: "引用", values: row.citationIDs)
                    }

                    if !row.expandedContextItems.isEmpty {
                        VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                            Text("引用的图谱上下文")
                                .font(AgentChatTypography.metaEmphasis)
                                .foregroundStyle(.secondary)
                            ForEach(row.expandedContextItems) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.sourceID)
                                        .font(AgentChatTypography.metaEmphasis)
                                    AgentMarkdownPreviewText(markdown: item.content, font: AgentChatTypography.meta)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.quaternary.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }

                }
                .padding(.top, 8)
            } label: {
                Text("轮次信息")
                    .font(AgentChatTypography.metaEmphasis)
            }
            .font(AgentChatTypography.meta)
        }
    }
}

struct MetadataBlock: View {
    var title: String
    var text: String
    var monospaced: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(AgentChatTypography.metaEmphasis)
                .foregroundStyle(.secondary)
            AgentMarkdownPreviewText(markdown: text, font: AgentChatTypography.meta, monospacedFallback: monospaced)
                .padding(8)
                .background(.quaternary.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

struct MetadataChips: View {
    var title: String
    var values: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
            Text(title)
                .font(AgentChatTypography.metaEmphasis)
                .foregroundStyle(.secondary)
            FlowLikeChips(values: values)
        }
    }
}

struct FlowLikeChips: View {
    var values: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
            ForEach(values, id: \.self) { value in
                Text(value)
                    .font(AgentChatTypography.micro)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
        }
    }
}
