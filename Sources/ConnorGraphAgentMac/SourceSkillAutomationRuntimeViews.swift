import SwiftUI
import ConnorGraphAppSupport

struct SourceRuntimePanelView: View {
    @ObservedObject var viewModel: AppViewModel

    private var presentation: SourceRuntimeUIPresentation {
        SourceRuntimeUIPresentation.build(sources: viewModel.sourceRuntimeConfigurations)
    }

    var body: some View {
        RuntimePanelScaffold(
            title: "Sources",
            subtitle: "MCP source runtime：工具、凭据、权限、审计和图谱摄取由康纳同学治理。",
            metrics: [
                ("Total", "\(presentation.summary.totalCount)"),
                ("Enabled", "\(presentation.summary.enabledCount)"),
                ("Needs credentials", "\(presentation.summary.needsCredentialCount)")
            ],
            onRefresh: viewModel.reloadSourceRuntimeConfigurations
        ) {
            ForEach(presentation.cards) { card in
                RuntimePanelCard(
                    title: card.title,
                    subtitle: "\(card.statusLabel) · \(card.transportLabel)",
                    detail: "prefix \(card.toolPrefixLabel) · \(card.graphPolicyLabel) · credentials \(card.credentialLabel)",
                    chips: card.capabilityLabels + card.tags,
                    severity: card.severity
                )
            }
        }
        .task {
            viewModel.deferViewUpdate {
                viewModel.reloadSourceRuntimeConfigurations()
            }
        }
    }
}

struct SkillRuntimePanelView: View {
    @ObservedObject var viewModel: AppViewModel

    private var presentation: SkillManagerPresentation {
        viewModel.commercialSkillManagerPresentation
    }

    private var selectedCard: SkillManagerCard? {
        guard let id = viewModel.selectedSkillManagerCardID else { return nil }
        return presentation.cards.first(where: { $0.id == id })
    }

    var body: some View {
        Group {
            if let card = selectedCard {
                SkillManagerDetailView(card: card, summary: presentation.summary, globalWarnings: presentation.globalWarnings, onRefresh: viewModel.reloadSkillRuntimeDefinitions)
            } else {
                SkillManagerEmptyDetailView(summary: presentation.summary, warnings: presentation.globalWarnings, onRefresh: viewModel.reloadSkillRuntimeDefinitions)
            }
        }
    }
}

private struct SkillManagerDetailView: View {
    var card: SkillManagerCard
    var summary: SkillManagerSummary
    var globalWarnings: [String]
    var onRefresh: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AgentChatLayout.spaceL) {
                SkillManagerTopBar(title: card.title, subtitle: "Skill Manager")
                SkillHeroSection(card: card)

                if !card.warnings.isEmpty || !globalWarnings.isEmpty {
                    SkillInfoSection(title: "Warnings", systemImage: "exclamationmark.triangle") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(card.warnings + globalWarnings, id: \.self) { warning in
                                Label(warning, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }

                SkillInfoSection(title: "Metadata", systemImage: "info.circle") {
                    SkillInfoTable(rows: [
                        ("Slug", card.id),
                        ("Name", card.title),
                        ("Description", card.subtitle),
                        ("Source", card.sourceTier),
                        ("Lifecycle", card.lifecycleLabel),
                        ("Trust", card.trustState),
                        ("Risk", card.riskLabel),
                        ("Package", displayPath(card.packagePath)),
                        ("SKILL.md", displayPath(card.path))
                    ])
                }

                SkillInfoSection(title: "Governance", systemImage: "checkmark.shield") {
                    VStack(alignment: .leading, spacing: 12) {
                        SkillBadgeRow(title: "Required Sources", values: card.requiredSources, emptyText: "No source dependency")
                        SkillBadgeRow(title: "Permissions", values: card.permissionLabels, emptyText: "No explicit skill-scoped permission")
                        SkillBadgeRow(title: "Override Chain", values: card.overrideChain.map(displayPath), emptyText: "No override")
                    }
                }

                SkillInfoSection(title: "Instructions", systemImage: "doc.text") {
                    SkillInstructionsPreview(instructions: card.instructions)
                }
            }
            .padding(AgentChatLayout.spaceXL)
            .frame(maxWidth: AgentChatLayout.chatContentMaxWidth, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.18))
        .navigationTitle(card.title)
    }

    private func displayPath(_ path: String) -> String {
        guard !path.isEmpty else { return "—" }
        if let range = path.range(of: "/skills/") {
            return String(path[range.upperBound...]).isEmpty ? path : "skills/" + String(path[range.upperBound...])
        }
        if let range = path.range(of: "/.agents/skills/") {
            return ".agents/skills/" + String(path[range.upperBound...])
        }
        return path
    }
}

private struct SkillManagerEmptyDetailView: View {
    var summary: SkillManagerSummary
    var warnings: [String]
    var onRefresh: () -> Void

    private var hasSkills: Bool {
        summary.total > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceL) {
            SkillManagerTopBar(title: "技能", subtitle: "Skill Manager")
            Spacer(minLength: 80)
            ContentUnavailableView(
                hasSkills ? "选择一个技能" : "暂无技能",
                systemImage: hasSkills ? "bolt" : "sparkles",
                description: Text(hasSkills ? "从左侧技能列表中选择一个技能，查看它的元数据、治理状态和指令内容。" : "点击左侧列表右上角的 +，添加一个新技能。")
            )
            .frame(maxWidth: .infinity)
            Spacer()
            if !warnings.isEmpty {
                SkillInfoSection(title: "Global warnings", systemImage: "exclamationmark.triangle") {
                    ForEach(warnings, id: \.self) { warning in
                        Text(warning).font(.caption).foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(AgentChatLayout.spaceXL)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.18))
    }
}

private struct SkillManagerTopBar: View {
    var title: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceXS) {
            Text(title)
                .font(.system(size: 24, weight: .semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(AgentChatTypography.meta)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SkillHeroSection: View {
    var card: SkillManagerCard

    var body: some View {
        HStack(alignment: .top, spacing: AgentChatLayout.spaceL) {
            ZStack {
                RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous)
                    .fill(heroColor.opacity(0.14))
                Image(systemName: "bolt.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(heroColor)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                HStack(alignment: .firstTextBaseline, spacing: AgentChatLayout.spaceS) {
                    Text(card.title)
                        .font(AgentChatTypography.title)
                        .lineLimit(2)
                    SkillPill(text: card.sourceTier, color: .blue)
                    SkillPill(text: card.riskLabel, color: heroColor)
                }
                Text(card.subtitle)
                    .font(AgentChatTypography.meta)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: AgentChatLayout.spaceS) {
                    SkillPill(text: "trust: \(card.trustState)", color: trustColor)
                    SkillPill(text: card.lifecycleLabel, color: .secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(AgentChatLayout.spaceL)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous)
                .stroke(Color.secondary.opacity(AgentChatLayout.hairlineOpacity), lineWidth: 1)
        )
    }

    private var heroColor: Color {
        if !card.warnings.isEmpty { return .orange }
        if card.riskLabel == "high" || card.riskLabel == "critical" { return .orange }
        return .accentColor
    }

    private var trustColor: Color {
        switch card.trustState {
        case "projectRequiresTrust", "unknown": .orange
        case "bundledTrusted", "trusted", "userTrusted": .green
        default: .secondary
        }
    }
}

private struct SkillInfoSection<Content: View>: View {
    var title: String
    var systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
            Label(title, systemImage: systemImage)
                .font(AgentChatTypography.metaEmphasis)
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(AgentChatLayout.spaceL)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous)
                    .stroke(Color.secondary.opacity(AgentChatLayout.hairlineOpacity), lineWidth: 1)
            )
        }
    }
}

private struct SkillInstructionsPreview: View {
    var instructions: String
    @State private var isExpanded = false

    private var normalizedInstructions: String {
        instructions.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayText: String {
        guard !normalizedInstructions.isEmpty else { return "No instructions found." }
        guard !isExpanded, normalizedInstructions.count > 1_800 else { return normalizedInstructions }
        let prefix = normalizedInstructions.prefix(1_800)
        return "\(prefix)\n\n…"
    }

    private var shouldShowToggle: Bool {
        normalizedInstructions.count > 1_800
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
            Text(displayText)
                .font(AgentChatTypography.monoMeta)
                .textSelection(.enabled)
                .lineLimit(isExpanded ? nil : 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AgentChatLayout.spaceM)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.50), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusM, style: .continuous))

            if shouldShowToggle {
                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Label(isExpanded ? "收起完整指令" : "展开完整指令", systemImage: isExpanded ? "chevron.up" : "chevron.down")
                        .font(AgentChatTypography.metaEmphasis)
                }
                .buttonStyle(.plain)
                .foregroundStyle(ConnorCraftPalette.accent)
            }
        }
    }
}

private struct SkillInfoTable: View {
    var rows: [(String, String)]

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: AgentChatLayout.spaceL, verticalSpacing: AgentChatLayout.spaceS) {
            ForEach(rows, id: \.0) { row in
                GridRow {
                    Text(row.0)
                        .font(AgentChatTypography.microEmphasis)
                        .foregroundStyle(.secondary)
                        .frame(width: 108, alignment: .leading)
                    Text(row.1)
                        .font(AgentChatTypography.meta)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

private struct SkillBadgeRow: View {
    var title: String
    var values: [String]
    var emptyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(AgentChatTypography.microEmphasis).foregroundStyle(.secondary)
            if values.isEmpty {
                Text(emptyText).font(AgentChatTypography.meta).foregroundStyle(.secondary)
            } else {
                FlowLikeWrap(values: values)
            }
        }
    }
}

private struct FlowLikeWrap: View {
    var values: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(values.prefix(12)), id: \.self) { value in
                SkillPill(text: value, color: .secondary)
            }
        }
    }
}

private struct SkillPill: View {
    var text: String
    var color: Color

    var body: some View {
        Text(text)
            .font(AgentChatTypography.micro)
            .lineLimit(1)
            .padding(.horizontal, AgentChatLayout.spaceS)
            .frame(height: AgentChatLayout.chipHeight - 8)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
    }
}

struct AutomationRuntimePanelView: View {
    @ObservedObject var viewModel: AppViewModel

    private var presentation: AutomationRuntimeUIPresentation {
        AutomationRuntimeUIPresentation.build(
            config: viewModel.automationConfig,
            triggers: viewModel.automationTriggerRecords,
            history: viewModel.automationExecutionHistory
        )
    }

    var body: some View {
        RuntimePanelScaffold(
            title: "Automation",
            subtitle: "康纳同学负责事件/动作治理。Ready 动作可执行，待审核动作仍由人确认。",
            metrics: [
                ("Rules", "\(presentation.summary.totalRuleCount)"),
                ("Enabled", "\(presentation.summary.enabledRuleCount)"),
                ("Review", "\(presentation.summary.pendingReviewRuleCount)"),
                ("History", "\(presentation.summary.historyCount)")
            ],
            onRefresh: {
                viewModel.reloadAutomationConfig()
                viewModel.reloadAutomationExecutionHistory()
            }
        ) {
            SectionHeader(title: "Rules")
            ForEach(presentation.ruleCards) { card in
                RuntimePanelCard(title: card.title, subtitle: card.subtitle, detail: card.detail, chips: [card.dispositionLabel], severity: card.severity)
            }
            SectionHeader(title: "Recent triggers")
            ForEach(presentation.triggerCards) { card in
                RuntimePanelCard(title: card.title, subtitle: card.subtitle, detail: card.detail, chips: [card.dispositionLabel], severity: card.severity)
            }
            SectionHeader(title: "Execution history")
            ForEach(presentation.historyCards) { card in
                RuntimePanelCard(title: card.title, subtitle: card.subtitle, detail: card.detail, chips: [card.dispositionLabel], severity: card.severity)
            }
        }
        .task {
            viewModel.deferViewUpdate {
                viewModel.reloadAutomationConfig()
                viewModel.reloadAutomationExecutionHistory()
            }
        }
    }
}

private struct RuntimePanelScaffold<Content: View>: View {
    var title: String
    var subtitle: String
    var metrics: [(String, String)]
    var onRefresh: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.largeTitle.weight(.semibold))
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("刷新", action: onRefresh)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 10)], spacing: 10) {
                    ForEach(metrics, id: \.0) { metric in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(metric.0).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(metric.1).font(.title2.weight(.semibold))
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    content
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.18))
        .navigationTitle(title)
    }
}

private struct SectionHeader: View {
    var title: String

    var body: some View {
        Text(title)
            .font(.headline)
            .padding(.top, 8)
    }
}

private struct RuntimePanelCard: View {
    var title: String
    var subtitle: String
    var detail: String
    var chips: [String]
    var severity: AgentEventPresentationSeverity

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Circle().fill(color(for: severity)).frame(width: 8, height: 8)
                Text(title).font(.headline)
                Spacer()
                Text(subtitle).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            if !detail.isEmpty {
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            if !chips.isEmpty {
                PanelChips(values: Array(chips.prefix(8)))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct PanelChips: View {
    var values: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(values, id: \.self) { value in
                Text(value)
                    .font(.caption2)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.quaternary.opacity(0.24), in: Capsule())
            }
        }
    }
}

private func color(for severity: AgentEventPresentationSeverity) -> Color {
    switch severity {
    case .info: .blue
    case .success: .green
    case .warning: .orange
    case .error: .red
    }
}
