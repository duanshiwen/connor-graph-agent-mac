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
        VStack(alignment: .leading, spacing: 0) {
            dialogHeader

            Divider()
                .padding(.top, AppShellLayout.spaceL)

            ScrollView {
                VStack(alignment: .leading, spacing: AppShellLayout.spaceL) {
                    MCPSourceDialogSection(title: "基础信息", systemImage: "person.text.rectangle") {
                        MCPSourceDialogRow("Source ID") {
                            TextField("local-files", text: $draft.sourceID)
                                .disabled(draft.isEditing)
                                .textFieldStyle(.roundedBorder)
                        }
                        MCPSourceDialogRow("显示名称") {
                            TextField("Local Files MCP", text: $draft.displayName)
                                .textFieldStyle(.roundedBorder)
                        }
                        if draft.isEditing {
                            MCPSourceDialogHint("Source ID 已锁定，用于保持 health、catalog 和 audit 的持久化路径稳定。")
                        }
                    }

                    MCPSourceDialogSection(title: "连接方式", systemImage: "point.3.connected.trianglepath.dotted") {
                        MCPSourceDialogRow("模式") {
                            Picker("", selection: $draft.transportKind) {
                                Text("stdio").tag("stdio")
                                Text("HTTP").tag("http")
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 220, alignment: .leading)
                        }

                        if draft.transportKind == "http" {
                            MCPSourceDialogRow("Endpoint") {
                                TextField("https://mcp.example.com/mcp", text: $draft.command)
                                    .textFieldStyle(.roundedBorder)
                            }
                            MCPSourceDialogHint("HTTP endpoint 需使用 HTTPS；本地开发允许 localhost 或 127.0.0.1。当前支持 JSON response path，SSE 会 fail closed。")
                        } else {
                            MCPSourceDialogRow("Command") {
                                TextField("/usr/bin/python3 或 npx", text: $draft.command)
                                    .textFieldStyle(.roundedBorder)
                            }
                            MCPSourceDialogRow("Arguments", alignment: .top) {
                                TextField("用空格或换行分隔", text: $draft.argumentsText, axis: .vertical)
                                    .textFieldStyle(.roundedBorder)
                                    .lineLimit(2...4)
                            }
                        }
                    }

                    MCPSourceDialogSection(title: "凭据", systemImage: "key") {
                        MCPSourceDialogRow("类型") {
                            Picker("", selection: $draft.credentialRequirement) {
                                Text("None").tag(ProductOSCredentialRequirement.none)
                                Text("Bearer Token").tag(ProductOSCredentialRequirement.bearerToken)
                                Text("API Key Header").tag(ProductOSCredentialRequirement.apiKeyHeader)
                                Text("Multi Header").tag(ProductOSCredentialRequirement.multiHeader)
                            }
                            .labelsHidden()
                            .frame(maxWidth: 240, alignment: .leading)
                        }
                        if draft.credentialRequirement != .none {
                            MCPSourceDialogRow("Binding") {
                                TextField("GITHUB_TOKEN 或 x-api-key:API_KEY", text: $draft.credentialEnvironmentText)
                                    .textFieldStyle(.roundedBorder)
                            }
                            MCPSourceDialogRow("Secret") {
                                SecureField(draft.isEditing ? "留空则保留现有 secret" : "Secret 或 ENV=secret 多行", text: $draft.credentialSecret)
                                    .textFieldStyle(.roundedBorder)
                            }
                            MCPSourceDialogHint("Secret 只保存到 Connor credential store，不写入 source 配置文件。stdio 使用 env binding；HTTP bearer 使用 Authorization header。")
                        }
                    }

                    MCPSourceDialogSection(title: "治理", systemImage: "checkmark.shield") {
                        MCPSourceDialogRow("状态") {
                            Picker("", selection: $draft.status) {
                                Text("Draft").tag(ProductOSRegistryEntryStatus.draft)
                                Text("Enabled").tag(ProductOSRegistryEntryStatus.enabled)
                                Text("Disabled").tag(ProductOSRegistryEntryStatus.disabled)
                                Text("Needs Review").tag(ProductOSRegistryEntryStatus.needsReview)
                            }
                            .labelsHidden()
                            .frame(maxWidth: 180, alignment: .leading)
                        }
                        MCPSourceDialogToggleRow("允许外部网络", isOn: $draft.allowExternalNetwork)
                        MCPSourceDialogToggleRow("允许读取会话", isOn: $draft.allowReadSession)
                        MCPSourceDialogToggleRow("允许读取工作区", isOn: $draft.allowWorkspaceRead)
                        MCPSourceDialogRow("图谱写入") {
                            Text("关闭")
                                .foregroundStyle(.secondary)
                        }
                    }

                    MCPSourceDialogSection(title: "元数据", systemImage: "tag") {
                        MCPSourceDialogRow("标签") {
                            TextField("用逗号、空格或换行分隔", text: $draft.tagsText)
                                .textFieldStyle(.roundedBorder)
                        }
                        MCPSourceDialogRow("备注", alignment: .top) {
                            TextField("可选", text: $draft.notes, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(2...4)
                        }
                    }
                }
                .padding(.vertical, AppShellLayout.spaceL)
            }
            .scrollIndicators(.visible)

            Divider()

            dialogFooter
        }
        .padding(AppShellLayout.spaceXL)
        .frame(width: 680, height: 720)
    }

    private var dialogHeader: some View {
        HStack(alignment: .top, spacing: AppShellLayout.spaceM) {
            VStack(alignment: .leading, spacing: AppShellLayout.spaceXS) {
                Text(draft.isEditing ? "编辑 MCP Source" : "添加 MCP Source")
                    .font(.system(size: 26, weight: .semibold))
                Text("连接 stdio 或 HTTP MCP 服务。凭据由 Connor Keychain 托管，不写入 source 配置文件。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("关闭")
        }
    }

    private var dialogFooter: some View {
        HStack(alignment: .center, spacing: AppShellLayout.spaceM) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Source ID 使用 lowercase-kebab-case。")
                Text("需要凭据时，环境变量名需使用大写 ENV_NAME。")
            }
            .font(AgentChatTypography.meta)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Spacer()
            Button("取消", action: onCancel)
            Button(draft.isEditing ? "保存修改" : "保存 Source", action: onSave)
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.top, AppShellLayout.spaceM)
    }
}

private struct MCPSourceDialogSection<Content: View>: View {
    var title: String
    var systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppShellLayout.spaceS) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.primary)
            VStack(spacing: AppShellLayout.spaceS) {
                content
            }
            .padding(AppShellLayout.spaceM)
            .background(AppShellColors.subtleCardBackground, in: RoundedRectangle(cornerRadius: AppShellLayout.radiusL, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppShellLayout.radiusL, style: .continuous)
                    .stroke(AppShellColors.hairline, lineWidth: 1)
            }
        }
    }
}

private struct MCPSourceDialogRow<Content: View>: View {
    var title: String
    var alignment: VerticalAlignment
    @ViewBuilder var content: Content

    init(_ title: String, alignment: VerticalAlignment = .firstTextBaseline, @ViewBuilder content: () -> Content) {
        self.title = title
        self.alignment = alignment
        self.content = content()
    }

    var body: some View {
        HStack(alignment: alignment, spacing: AppShellLayout.spaceM) {
            Text("\(title):")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 116, alignment: .trailing)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct MCPSourceDialogToggleRow: View {
    var title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        self._isOn = isOn
    }

    var body: some View {
        MCPSourceDialogRow(title) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

private struct MCPSourceDialogHint: View {
    var text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(AgentChatTypography.meta)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 116 + AppShellLayout.spaceM)
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
