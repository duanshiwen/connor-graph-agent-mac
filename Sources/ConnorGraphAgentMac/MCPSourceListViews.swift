import SwiftUI
import ConnorGraphCore
import ConnorGraphAppSupport

struct CraftSourceListPane: View {
    @ObservedObject var viewModel: AppViewModel

    private var presentation: SourceRuntimeUIPresentation {
        SourceRuntimeUIPresentation.build(
            sources: viewModel.sourceRuntimeConfigurations,
            healthRecords: viewModel.sourceRuntimeHealthRecords,
            auditRecords: viewModel.sourceRuntimeAuditRecordsBySource.values.flatMap { $0 }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            SourceListHeader(
                onRefresh: viewModel.reloadSourceRuntimeConfigurations
            )

            if presentation.cards.isEmpty {
                SourceListEmptyState()
            } else {
                List(presentation.cards) { card in
                    MCPSourceRow(
                        card: card,
                        isSelected: card.id == viewModel.selectedSourceRuntimeCardID,
                        onSelect: { viewModel.selectSourceRuntimeCard(card.id) }
                    )
                    .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $viewModel.isPresentingAddSourceSheet) {
            MCPSourceAddSheet(
                draft: $viewModel.addSourceDraft,
                message: viewModel.addSourceMessage,
                onCancel: viewModel.dismissAddSourceSheet,
                onSave: viewModel.saveSourceRuntimeDraft
            )
        }
        .task {
            guard viewModel.sourceRuntimeConfigurations.isEmpty else { return }
            viewModel.deferViewUpdate {
                viewModel.reloadSourceRuntimeConfigurations()
            }
        }
    }
}

private struct SourceListHeader: View {
    var onRefresh: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: AppShellLayout.spaceS) {
            VStack(alignment: .leading, spacing: 2) {
                Text("MCP Sources")
                    .font(AppListTypography.header)
                Text("外部工具连接")
                    .font(AppListTypography.rowCaption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12.5, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .help("刷新 MCP Sources")
            .accessibilityLabel("刷新 MCP Sources")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct SourceListEmptyState: View {
    var body: some View {
        ContentUnavailableView(
            "暂无 MCP Source",
            systemImage: "server.rack",
            description: Text("使用右上角「添加 Source」创建第一个外部工具连接。")
        )
        .padding(.top, 80)
    }
}

private struct MCPSourceAddSheet: View {
    @Binding var draft: MCPSourceDraft
    var message: String?
    var onCancel: () -> Void
    var onSave: () -> Void

    private var canSave: Bool {
        guard !draft.normalizedSourceID.isEmpty,
              !draft.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard draft.credentialRequirement != .none else { return true }
        let hasBinding = !draft.credentialEnvironmentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !draft.parsedCredentialSecretByEnvironment.isEmpty
        let hasSecretOrEditing = draft.isEditing || !draft.trimmedCredentialSecret.isEmpty
        return hasBinding && hasSecretOrEditing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceL) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: AgentChatLayout.spaceXS) {
                    Text(draft.isEditing ? "编辑 MCP Source" : "添加 MCP Source")
                        .font(.system(size: 22, weight: .semibold))
                    Text("支持 stdio 与 HTTP MCP source，以及 Connor-owned Keychain credential injection。Secret 不写入 source 配置文件。")
                        .font(AgentChatTypography.meta)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }

            Form {
                Section("Identity") {
                    TextField("Source ID，例如 local-files", text: $draft.sourceID)
                        .disabled(draft.isEditing)
                    TextField("Display Name，例如 Local Files MCP", text: $draft.displayName)
                    if draft.isEditing {
                        Text("Source ID editing is disabled to preserve persisted catalog/audit paths.")
                            .font(AgentChatTypography.meta)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Transport") {
                    Picker("Mode", selection: $draft.transportKind) {
                        Text("stdio").tag("stdio")
                        Text("HTTP").tag("http")
                    }
                    .pickerStyle(.segmented)
                    if draft.transportKind == "http" {
                        TextField("MCP Endpoint，例如 https://mcp.example.com/mcp", text: $draft.command)
                        Text("HTTP endpoint 必须使用 HTTPS；本地开发允许 http://localhost 或 127.0.0.1。当前支持 JSON response path；request-scoped SSE 会 fail closed。")
                            .font(AgentChatTypography.meta)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        TextField("Command，例如 /usr/bin/python3 或 npx", text: $draft.command)
                        TextField("Arguments，用空格或换行分隔", text: $draft.argumentsText, axis: .vertical)
                            .lineLimit(2...4)
                    }
                }

                Section("Credentials") {
                    Picker("Requirement", selection: $draft.credentialRequirement) {
                        Text("None").tag(ProductOSCredentialRequirement.none)
                        Text("Bearer Token").tag(ProductOSCredentialRequirement.bearerToken)
                        Text("API Key Header").tag(ProductOSCredentialRequirement.apiKeyHeader)
                        Text("Multi Header").tag(ProductOSCredentialRequirement.multiHeader)
                    }
                    if draft.credentialRequirement != .none {
                        TextField("Binding，例如 GITHUB_TOKEN 或 x-api-key:API_KEY", text: $draft.credentialEnvironmentText)
                        SecureField(draft.isEditing ? "Secret 或 ENV=secret 多行（留空则保留现有）" : "Secret 或 ENV=secret 多行", text: $draft.credentialSecret)
                        Text("stdio 使用 env binding；HTTP bearer 使用 Authorization header；HTTP API header 可写 header:ENV。multi-header 可用多组 header:ENV 与 ENV=secret。Secret 仅保存到 Connor credential store。")
                            .font(AgentChatTypography.meta)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Section("Governance") {
                    Picker("Status", selection: $draft.status) {
                        Text("Draft").tag(ProductOSRegistryEntryStatus.draft)
                        Text("Enabled").tag(ProductOSRegistryEntryStatus.enabled)
                        Text("Disabled").tag(ProductOSRegistryEntryStatus.disabled)
                        Text("Needs Review").tag(ProductOSRegistryEntryStatus.needsReview)
                    }
                    Toggle("Allow external network", isOn: $draft.allowExternalNetwork)
                    Toggle("Allow read session", isOn: $draft.allowReadSession)
                    Toggle("Allow workspace read", isOn: $draft.allowWorkspaceRead)
                    LabeledContent("Graph ingestion") {
                        Text("off")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Metadata") {
                    TextField("Tags，用逗号、空格或换行分隔", text: $draft.tagsText)
                    TextField("Notes", text: $draft.notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .formStyle(.grouped)

            if let message, !message.isEmpty {
                Text(message)
                    .font(AgentChatTypography.meta)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            HStack {
                Text("Source ID 需匹配 lowercase kebab-case；credential env var 需为大写 ENV_NAME。")
                    .font(AgentChatTypography.meta)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("取消", action: onCancel)
                Button(draft.isEditing ? "保存修改" : "保存 Source", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(AgentChatLayout.spaceXL)
        .frame(width: 560, height: 680)
    }
}

private struct MCPSourceRow: View {
    var card: SourceRuntimeUICard
    var isSelected: Bool
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: AppShellLayout.spaceM) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppShellLayout.radiusM, style: .continuous)
                        .fill(rowColor.opacity(isSelected ? 0.20 : 0.11))
                    Image(systemName: "server.rack")
                        .font(.system(size: 15, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(rowColor)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(card.title)
                            .font(isSelected ? AppListTypography.rowTitleSelected : AppListTypography.rowTitle)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Circle()
                            .fill(rowColor)
                            .frame(width: 7, height: 7)
                            .accessibilityHidden(true)
                    }
                    Text(card.transportLabel)
                        .font(AppListTypography.rowSubtitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 6) {
                        AppPill(text: card.statusLabel, color: rowColor)
                        AppPill(text: card.healthLabel, color: rowColor)
                        AppPill(text: card.toolCountLabel, color: .secondary)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppShellLayout.radiusM, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppShellLayout.radiusM, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.28) : Color.clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: AppShellLayout.radiusM, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var rowColor: Color {
        switch card.severity {
        case .success: .green
        case .warning: .orange
        case .error: .red
        case .info: .blue
        }
    }
}
