import SwiftUI
import AppKit
import ConnorGraphCore
import ConnorGraphAppSupport

struct SourceRuntimePanelView: View {
    @Bindable var model: SourceRuntimeFeatureModel

    private var presentation: SourceRuntimeUIPresentation {
        model.presentation
    }

    private var selectedCard: SourceRuntimeUICard? {
        guard let id = model.selectedCardID else { return nil }
        return presentation.cards.first(where: { $0.id == id })
    }

    private var selectedConfiguration: MCPSourceRuntimeConfiguration? {
        guard let id = model.selectedCardID else { return nil }
        return model.configurations.first(where: { $0.sourceID == id })
    }

    var body: some View {
        Group {
            if let card = selectedCard, let configuration = selectedConfiguration {
                MCPSourceDetailView(
                    card: card,
                    configuration: configuration,
                    summary: presentation.summary,
                    tools: model.toolCatalogs[card.id, default: []],
                    auditRecords: model.auditRecordsBySource[card.id, default: []],
                    isTesting: model.testingSourceIDs.contains(card.id),
                    testMessage: model.testMessages[card.id],
                    onEdit: { model.presentEditSheet(sourceID: card.id) },
                    onToggleEnabled: {
                        model.setStatus(
                            sourceID: card.id,
                            status: configuration.status == .enabled ? .disabled : .enabled
                        )
                    },
                    onArchive: { model.archive(sourceID: card.id) },
                    onDelete: { model.requestDelete(sourceID: card.id) },
                    onTest: { Task { await model.testSource(sourceID: card.id) } }
                )
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppShellColors.detailBackground)
            }
        }
        .confirmationDialog(
            "Delete MCP Source?",
            isPresented: Binding(
                get: { model.pendingDeletionID != nil },
                set: { if !$0 { model.cancelDelete() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Source", role: .destructive) {
                model.confirmDelete()
            }
            Button("Cancel", role: .cancel) {
                model.cancelDelete()
            }
        } message: {
            Text("This permanently deletes \(model.pendingDeletionName ?? "this source") and its persisted health, catalog, and audit files. Archive instead if you need to preserve history.")
        }
        .onAppear {
            model.reload()
        }
    }
}

private struct MCPSourceDetailView: View {
    var card: SourceRuntimeUICard
    var configuration: MCPSourceRuntimeConfiguration
    var summary: SourceRuntimeUISummary
    var tools: [MCPSourceToolDescriptor]
    var auditRecords: [MCPSourceRuntimeAuditRecord]
    var isTesting: Bool
    var testMessage: String?
    var onEdit: () -> Void
    var onToggleEnabled: () -> Void
    var onArchive: () -> Void
    var onDelete: () -> Void
    var onTest: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppShellLayout.spaceL) {
                MCPSourceTopBar(
                    title: card.title,
                    subtitle: "MCP Source",
                    status: configuration.status,
                    onEdit: onEdit,
                    onToggleEnabled: onToggleEnabled,
                    onArchive: onArchive,
                    onDelete: onDelete,
                    onTest: onTest,
                    isTesting: isTesting
                )
                MCPSourceHeroSection(card: card, configuration: configuration)

                if let testMessage, !testMessage.isEmpty {
                    SkillInfoSection(title: "Source Test", systemImage: isTesting ? "hourglass" : "checkmark.circle") {
                        HStack(spacing: AgentChatLayout.spaceS) {
                            if isTesting {
                                ProgressView().controlSize(.small)
                            }
                            Text(testMessage)
                                .font(AgentChatTypography.meta)
                                .foregroundStyle(testMessage.localizedCaseInsensitiveContains("failed") ? .red : .secondary)
                                .textSelection(.enabled)
                        }
                    }
                }

                if !card.lastErrorLabel.isEmpty {
                    SkillInfoSection(title: "Last Error", systemImage: "exclamationmark.triangle") {
                        Text(card.lastErrorLabel)
                            .font(AgentChatTypography.meta)
                            .foregroundStyle(.orange)
                            .textSelection(.enabled)
                    }
                }

                SkillInfoSection(title: "Metadata", systemImage: "info.circle") {
                    SkillInfoTable(rows: [
                        ("Source ID", configuration.sourceID),
                        ("Display Name", configuration.displayName),
                        ("Status", card.statusLabel),
                        ("Lifecycle", card.lifecycleLabel),
                        ("Health", card.healthLabel),
                        ("Transport", card.transportLabel),
                        ("Credentials", card.credentialLabel),
                        ("Tool Prefix", card.toolPrefixLabel),
                        ("Created", configuration.createdAt.connorLocalStandardDateTime()),
                        ("Updated", configuration.updatedAt.connorLocalStandardDateTime())
                    ])
                }

                SkillInfoSection(title: "Governance", systemImage: "checkmark.shield") {
                    VStack(alignment: .leading, spacing: 12) {
                        SkillBadgeRow(title: "Allowed Capabilities", values: card.capabilityLabels, emptyText: "No explicit runtime capability")
                        SkillBadgeRow(title: "Server Capabilities", values: card.platformCapabilityLabels, emptyText: "No discovery snapshot yet")
                        SkillBadgeRow(title: "Tags", values: card.tags, emptyText: "No tags")
                        SkillInfoTable(rows: [
                            ("Graph Policy", card.graphPolicyLabel),
                            ("Discovered Tools", card.toolCountLabel),
                            ("Recent Audits", card.auditCountLabel),
                            ("Last Checked", card.lastCheckedLabel)
                        ])
                    }
                }

                SkillInfoSection(title: "Tool Catalog", systemImage: "wrench.and.screwdriver") {
                    MCPToolCatalogPreview(tools: tools)
                }

                SkillInfoSection(title: "Recent Audit", systemImage: "clock.arrow.circlepath") {
                    MCPAuditPreview(records: auditRecords)
                }
            }
            .padding(AppShellLayout.spaceXL)
            .frame(maxWidth: AppShellLayout.contentMaxWidth, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppShellColors.detailBackground)
    }
}

private struct MCPSourceEmptyDetailView: View {
    var summary: SourceRuntimeUISummary

    private var hasSources: Bool { summary.totalCount > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: AppShellLayout.spaceL) {
            MCPSourceTopBar(title: "MCP Sources", subtitle: "Source Runtime", onTest: nil, isTesting: false)
            Spacer(minLength: 80)
            ContentUnavailableView(
                hasSources ? "请选择一个 MCP Source" : "暂无 MCP Source",
                systemImage: hasSources ? "server.rack" : "externaldrive.badge.plus",
                description: Text(hasSources ? "从左侧列表选择一个连接，即可查看健康状态、工具目录、治理策略和审计记录。" : "使用左侧列表标题栏的「+」创建外部工具连接；测试通过后，健康状态、工具目录和审计记录会显示在这里。")
            )
            .frame(maxWidth: .infinity)
            Spacer()
        }
        .padding(AppShellLayout.spaceXL)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppShellColors.detailBackground)
    }
}

private struct MCPSourceTopBar: View {
    var title: String
    var subtitle: String
    var status: ProductOSRegistryEntryStatus? = nil
    var onEdit: (() -> Void)? = nil
    var onToggleEnabled: (() -> Void)? = nil
    var onArchive: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var onTest: (() -> Void)?
    var isTesting: Bool

    var body: some View {
        HStack(alignment: .top, spacing: AppShellLayout.spaceM) {
            VStack(alignment: .leading, spacing: AppShellLayout.spaceXS) {
                HStack(alignment: .firstTextBaseline, spacing: AppShellLayout.spaceS) {
                    Text(title)
                        .font(AppTypography.pageTitle)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let status {
                        AppPill(text: status.rawValue, color: status == .enabled ? .green : .secondary)
                    }
                }
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: AppShellLayout.spaceS) {
                if let onTest {
                    Button(action: onTest) {
                        Label(isTesting ? "测试中…" : "测试 Source", systemImage: isTesting ? "hourglass" : "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isTesting)
                    .help("运行 MCP initialize + tools/list，并刷新 health/catalog/audit。")
                }
                if let onEdit {
                    Button(action: onEdit) {
                        Label("编辑", systemImage: "pencil")
                    }
                    .buttonStyle(.bordered)
                }
                if onToggleEnabled != nil || onArchive != nil || onDelete != nil {
                    Menu {
                        if let onToggleEnabled {
                            Button(action: onToggleEnabled) {
                                Label(status == .enabled ? "停用 Source" : "启用 Source", systemImage: status == .enabled ? "pause.circle" : "play.circle")
                            }
                        }
                        if let onArchive {
                            Button(action: onArchive) {
                                Label("归档 Source", systemImage: "archivebox")
                            }
                            .disabled(status == .deprecated)
                        }
                        if let onDelete {
                            Divider()
                            Button(role: .destructive, action: onDelete) {
                                Label("删除 Source", systemImage: "trash")
                            }
                        }
                    } label: {
                        Label("更多", systemImage: "ellipsis.circle")
                    }
                    .menuStyle(.button)
                    .help("更多 Source 生命周期操作")
                }
            }
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MCPSourceHeroSection: View {
    var card: SourceRuntimeUICard
    var configuration: MCPSourceRuntimeConfiguration

    var body: some View {
        HStack(alignment: .top, spacing: AppShellLayout.spaceL) {
            ZStack {
                RoundedRectangle(cornerRadius: AppShellLayout.radiusL, style: .continuous)
                    .fill(heroColor.opacity(0.14))
                Image(systemName: "server.rack")
                    .font(.system(size: 24, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(heroColor)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: AppShellLayout.spaceS) {
                HStack(alignment: .firstTextBaseline, spacing: AppShellLayout.spaceS) {
                    Text(card.title)
                        .font(AgentChatTypography.title)
                        .lineLimit(2)
                    AppPill(text: card.statusLabel, color: heroColor)
                    AppPill(text: card.healthLabel, color: heroColor)
                }
                Text(configuration.notes.isEmpty ? "Connor-governed MCP source. Tools, credentials, permissions and audit stay inside the app boundary." : configuration.notes)
                    .font(AgentChatTypography.meta)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: AppShellLayout.spaceS) {
                    AppPill(text: card.transportLabel, color: .secondary)
                    AppPill(text: card.toolCountLabel, color: .blue)
                    AppPill(text: card.auditCountLabel, color: .secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(AppShellLayout.spaceL)
        .background(AppShellColors.cardBackground, in: RoundedRectangle(cornerRadius: AppShellLayout.radiusL, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppShellLayout.radiusL, style: .continuous)
                .stroke(AppShellColors.hairline, lineWidth: 1)
        )
    }

    private var heroColor: Color {
        switch card.severity {
        case .success: .green
        case .warning: .orange
        case .error: .red
        case .info: .blue
        }
    }
}

private struct MCPToolCatalogPreview: View {
    var tools: [MCPSourceToolDescriptor]

    var body: some View {
        if tools.isEmpty {
            Text("No persisted tool catalog yet. Run source test/discovery to populate catalog.json.")
                .font(AgentChatTypography.meta)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(tools.prefix(24)) { tool in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(tool.name)
                            .font(AgentChatTypography.monoMeta.weight(.semibold))
                            .textSelection(.enabled)
                        if !tool.description.isEmpty {
                            Text(tool.description)
                                .font(AgentChatTypography.meta)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        HStack(spacing: 6) {
                            SkillPill(text: "raw: \(tool.rawName)", color: .secondary)
                            if let policy = tool.governancePolicy {
                                SkillPill(text: "risk: \(policy.riskClass.rawValue)", color: color(for: policy.riskClass))
                                SkillPill(text: "policy: \(policy.executionPolicy.rawValue)", color: color(for: policy.executionPolicy))
                            } else {
                                SkillPill(text: "policy: missing", color: .orange)
                            }
                            if let integrity = tool.integrityStatus {
                                SkillPill(text: "integrity: \(integrity.rawValue)", color: color(for: integrity))
                            }
                            ForEach(tool.requiredCapabilities.map(\.rawValue).prefix(3), id: \.self) { capability in
                                SkillPill(text: capability, color: .blue)
                            }
                        }
                        if let policy = tool.governancePolicy {
                            Text(policy.rationale)
                                .font(AgentChatTypography.micro)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let fingerprint = tool.definitionFingerprint {
                            Text("sha256: \(fingerprint.value)")
                                .font(AgentChatTypography.micro.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppShellColors.subtleCardBackground, in: RoundedRectangle(cornerRadius: AppShellLayout.radiusM, style: .continuous))
                }
            }
        }
    }

    private func color(for risk: MCPToolRiskClass) -> Color {
        switch risk {
        case .read: .green
        case .externalRead: .blue
        case .mutation: .orange
        case .destructive, .admin, .credentialAccess: .red
        case .unknown: .purple
        }
    }

    private func color(for policy: MCPToolExecutionPolicy) -> Color {
        switch policy {
        case .autoAllow: .green
        case .requireConfirmation: .orange
        case .block: .red
        }
    }

    private func color(for integrity: MCPToolIntegrityStatus) -> Color {
        switch integrity {
        case .new: .blue
        case .verified: .green
        case .changed: .red
        }
    }
}

private struct MCPAuditPreview: View {
    var records: [MCPSourceRuntimeAuditRecord]

    var body: some View {
        if records.isEmpty {
            Text("No recent audit records.")
                .font(AgentChatTypography.meta)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(records.reversed()) { record in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            SkillPill(text: record.eventKind.rawValue, color: color(for: record.eventKind))
                            Text(record.timestamp.connorLocalStandardDateTime())
                                .font(AgentChatTypography.micro)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                        }
                        if let toolName = record.prefixedToolName ?? record.rawToolName {
                            Text(toolName)
                                .font(AgentChatTypography.monoMeta)
                                .textSelection(.enabled)
                        }
                        HStack(spacing: 6) {
                            if let riskClass = record.riskClass {
                                SkillPill(text: "risk: \(riskClass.rawValue)", color: .orange)
                            }
                            if let executionPolicy = record.executionPolicy {
                                SkillPill(text: "policy: \(executionPolicy.rawValue)", color: .purple)
                            }
                            if let integrityStatus = record.integrityStatus {
                                SkillPill(text: "integrity: \(integrityStatus.rawValue)", color: integrityStatus == .changed ? .red : .green)
                            }
                        }
                        if let result = record.resultSummary, !result.isEmpty {
                            Text(result)
                                .font(AgentChatTypography.meta)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                        if let error = record.errorSummary, !error.isEmpty {
                            Text(error)
                                .font(AgentChatTypography.meta)
                                .foregroundStyle(.red)
                                .lineLimit(3)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppShellColors.subtleCardBackground, in: RoundedRectangle(cornerRadius: AppShellLayout.radiusM, style: .continuous))
                }
            }
        }
    }

    private func color(for kind: MCPSourceRuntimeAuditEventKind) -> Color {
        switch kind {
        case .toolFinished, .discoveryFinished: .green
        case .toolFailed, .toolPolicyBlocked, .toolDefinitionChanged: .red
        case .toolPermissionRequested: .orange
        case .toolStarted, .discoveryStarted: .blue
        }
    }
}

private struct SourceSummaryStrip: View {
    var summary: SourceRuntimeUISummary

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: AppShellLayout.spaceS)], spacing: AppShellLayout.spaceS) {
            AppMetricCard(title: "Total", value: "\(summary.totalCount)")
            AppMetricCard(title: "Enabled", value: "\(summary.enabledCount)", color: .green)
            AppMetricCard(title: "Healthy", value: "\(summary.healthyCount)", color: .green)
            AppMetricCard(title: "Tools", value: "\(summary.discoveredToolCount)", color: .blue)
        }
    }
}

struct SkillRuntimePanelView: View {
    @Bindable var model: SkillRuntimeFeatureModel

    private var presentation: SkillManagerPresentation {
        model.presentation
    }

    private var selectedCard: SkillManagerCard? {
        guard let id = model.selectedCardID else { return nil }
        return presentation.cards.first(where: { $0.id == id })
    }

    var body: some View {
        Group {
            if let card = selectedCard {
                SkillManagerDetailView(card: card, summary: presentation.summary, globalWarnings: presentation.globalWarnings, onRefresh: model.reload)
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.18))
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
                    SkillInstructionsPreview(skillID: card.id, instructions: card.instructions)
                }
            }
            .padding(AgentChatLayout.spaceXL)
            .frame(maxWidth: AgentChatLayout.chatContentMaxWidth, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.18))
    }

    private func displayPath(_ path: String) -> String {
        guard !path.isEmpty else { return "—" }
        if let range = path.range(of: "/skills/") {
            return String(path[range.upperBound...]).isEmpty ? path : "skills/" + String(path[range.upperBound...])
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
                .font(AppTypography.pageTitle)
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
        AppSectionCard(title: title, systemImage: systemImage) {
            content
        }
    }
}

private struct SkillInstructionsPreview: View {
    var skillID: String
    var instructions: String
    @State private var isExpanded = false
    @State private var presentation: SkillInstructionsPresentation?

    var body: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
            if let presentation {
                Group {
                    if isExpanded {
                        SkillInstructionsTextView(text: presentation.fullText)
                            .frame(height: 360)
                    } else {
                        Text(presentation.collapsedText)
                            .font(AgentChatTypography.monoMeta)
                            .lineLimit(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(AgentChatLayout.spaceM)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.50), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusM, style: .continuous))
            } else {
                ProgressView("正在加载指令…")
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }

            if presentation?.isCollapsible == true {
                Button {
                    isExpanded.toggle()
                } label: {
                    Label(isExpanded ? "收起完整指令" : "展开完整指令", systemImage: isExpanded ? "chevron.up" : "chevron.down")
                        .font(AgentChatTypography.metaEmphasis)
                }
                .buttonStyle(.plain)
                .foregroundStyle(ConnorCraftPalette.accent)
            }
        }
        .task(id: instructions) {
            isExpanded = false
            presentation = nil
            let source = instructions
            let prepared = await Task.detached(priority: .userInitiated) {
                SkillInstructionsPresentation(instructions: source)
            }.value
            guard !Task.isCancelled else { return }
            presentation = prepared
        }
        .accessibilityIdentifier("skill-instructions-\(skillID)")
    }
}

struct SkillInstructionsPresentation: Sendable, Equatable {
    static let previewCharacterLimit = 1_800

    var fullText: String
    var collapsedText: String
    var isCollapsible: Bool

    init(instructions: String, previewCharacterLimit: Int = Self.previewCharacterLimit) {
        let normalized = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        fullText = normalized.isEmpty ? "No instructions found." : normalized
        let limit = max(0, previewCharacterLimit)
        isCollapsible = fullText.count > limit
        collapsedText = isCollapsible ? "\(fullText.prefix(limit))\n\n…" : fullText
    }
}

private struct SkillInstructionsTextView: NSViewRepresentable {
    var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.textColor = .labelColor
        textView.font = .monospacedSystemFont(
            ofSize: NSFont.preferredFont(forTextStyle: .subheadline).pointSize,
            weight: .regular
        )
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.string = text
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView,
              textView.string != text else { return }
        textView.string = text
        textView.scrollToBeginningOfDocument(nil)
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
    @Bindable var model: TaskAutomationFeatureModel

    private var presentation: TaskManagementUIPresentation {
        model.presentation
    }

    var body: some View {
        RuntimePanelScaffold(
            title: "任务与自动化",
            subtitle: "三类任务：系统任务、用户任务、AI 任务。系统任务受保护；用户和 AI 任务暂时只支持会话状态触发消息，以及按时间/周期新建会话并发送消息。",
            metrics: [
                ("总计", "\(presentation.summary.totalTaskCount)"),
                ("系统", "\(presentation.summary.systemTaskCount)"),
                ("用户", "\(presentation.summary.userTaskCount)"),
                ("AI", "\(presentation.summary.aiTaskCount)"),
                ("定时", "\(presentation.summary.scheduledTaskCount)"),
                ("事件", "\(presentation.summary.eventTriggeredTaskCount)")
            ],
            onRefresh: {
                model.reload()
            }
        ) {
            if model.isRunningScheduledTasks {
                Label("正在执行到期任务…", systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SectionHeader(title: "定时任务")
            if presentation.scheduledTasks.isEmpty {
                Text("暂无定时任务。系统任务会在启动时自动补齐。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(presentation.scheduledTasks) { card in
                TaskRuntimeCard(card: card, model: model)
            }

            SectionHeader(title: "事件触发")
            if presentation.eventTriggeredTasks.isEmpty {
                Text("暂无事件触发任务。用户或 AI 可创建：当会话状态变为特定状态后，向 AI 发送指定内容。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(presentation.eventTriggeredTasks) { card in
                TaskRuntimeCard(card: card, model: model)
            }
        }
        .onAppear {
            model.reload()
        }
    }
}

private struct TaskRuntimeCard: View {
    var card: TaskManagementUICard
    @Bindable var model: TaskAutomationFeatureModel

    var body: some View {
        RuntimePanelCard(
            title: card.title,
            subtitle: card.originBadge,
            detail: detail,
            chips: chips,
            severity: card.severity
        )
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 8) {
                if card.canStop {
                    TaskRuntimeCardActionButton(title: "暂停", systemImage: "pause.fill") {
                        model.stopTask(card.id)
                    }
                }
                if card.canRestore {
                    TaskRuntimeCardActionButton(title: "恢复", systemImage: "play.fill") {
                        model.restoreTask(card.id)
                    }
                }
                if card.canDelete {
                    TaskRuntimeCardActionButton(title: "删除", systemImage: "trash", role: .destructive) {
                        model.deleteTask(card.id)
                    }
                }
            }
            .padding(12)
        }
    }

    private var detail: String {
        [
            card.targetLabel.isEmpty ? nil : "目标：\(card.targetLabel)",
            card.nextRunLabel.isEmpty ? nil : "下次：\(card.nextRunLabel)",
            card.lastRunLabel.isEmpty ? nil : "上次：\(card.lastRunLabel)",
            card.lastErrorLabel.isEmpty ? nil : "错误：\(card.lastErrorLabel)",
            card.rationaleLabel.isEmpty ? nil : "原因：\(card.rationaleLabel)"
        ].compactMap { $0 }.joined(separator: "\n")
    }

    private var chips: [String] {
        var values = [card.triggerLabel, card.statusLabel]
        if !card.deleteDisabledReason.isEmptyOrNil { values.append(card.deleteDisabledReason ?? "") }
        return values
    }
}

private struct TaskRuntimeCardActionButton: View {
    var title: String
    var systemImage: String
    var role: ButtonRole?
    var action: () -> Void

    init(title: String, systemImage: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption2.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .controlSize(AppButtonLayout.controlSize)
        .help(title)
    }
}

private extension Optional where Wrapped == String {
    var isEmptyOrNil: Bool { self?.isEmpty ?? true }
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
                            .font(AppTypography.pageTitle)
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
