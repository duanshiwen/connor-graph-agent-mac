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

    private var presentation: SkillRuntimeUIPresentation {
        SkillRuntimeUIPresentation.build(skills: viewModel.skillRuntimeDefinitions)
    }

    var body: some View {
        RuntimePanelScaffold(
            title: "Skills",
            subtitle: "受治理的指令配置。技能可以请求能力和数据源，但不能绕过康纳同学权限。",
            metrics: [
                ("Total", "\(presentation.summary.totalCount)"),
                ("Project", "\(presentation.summary.projectScopedCount)"),
                ("Needs source", "\(presentation.summary.requiresSourceCount)")
            ],
            onRefresh: viewModel.reloadSkillRuntimeDefinitions
        ) {
            ForEach(presentation.cards) { card in
                RuntimePanelCard(
                    title: card.title,
                    subtitle: "\(card.scopeLabel) · \(card.graphPolicyLabel)",
                    detail: card.description,
                    chips: card.triggerLabels + card.capabilityLabels + card.requiredSourceLabels + card.globLabels,
                    severity: card.severity
                )
            }
        }
        .task {
            viewModel.deferViewUpdate {
                viewModel.reloadSkillRuntimeDefinitions()
            }
        }
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
