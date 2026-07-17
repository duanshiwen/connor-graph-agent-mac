import SwiftUI
import ConnorGraphCore
import ConnorGraphAppSupport

struct CraftSourceListPane: View {
    @Bindable var model: SourceRuntimeFeatureModel

    private var presentation: SourceRuntimeUIPresentation {
        model.presentation
    }

    var body: some View {
        VStack(spacing: 0) {
            SourceListHeader(
                onAdd: model.presentAddSheet
            )

            if presentation.cards.isEmpty {
                SourceListEmptyState()
            } else {
                List(presentation.cards) { card in
                    MCPSourceRow(
                        card: card,
                        isSelected: card.id == model.selectedCardID,
                        onSelect: { model.selectCard(card.id) }
                    )
                    .nativeListRowStyle()
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $model.isPresentingAddSheet) {
            MCPSourceAddSheet(
                draft: $model.addDraft,
                message: model.addMessage,
                onCancel: model.dismissAddSheet,
                onSave: model.saveDraft
            )
        }
        .onAppear {
            guard model.configurations.isEmpty else { return }
            model.reload()
        }
    }
}

private struct SourceListHeader: View {
    var onAdd: () -> Void

    var body: some View {
        AppListPaneHeader(title: "外部工具连接", verticalPadding: 12) {
            Button(action: onAdd) {
                Image(systemName: "plus")
            }
            .buttonStyle(.appIcon)
            .help("添加外部工具连接")
            .accessibilityLabel("添加外部工具连接")
        }
    }
}

private struct SourceListEmptyState: View {
    var body: some View {
        ContentUnavailableView(
            "暂无外部工具连接",
            systemImage: "server.rack",
            description: Text("使用右上角「添加」创建第一个外部工具连接。")
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
                        MCPSourceDialogRow("连接标识") {
                            TextField("local-files", text: $draft.sourceID)
                                .disabled(draft.isEditing)
                                .textFieldStyle(.roundedBorder)
                        }
                        MCPSourceDialogRow("显示名称") {
                            TextField("Local Files MCP", text: $draft.displayName)
                                .textFieldStyle(.roundedBorder)
                        }
                        if draft.isEditing {
                            MCPSourceDialogHint("连接标识已锁定，用于保持已有连接记录稳定。")
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
                            MCPSourceDialogRow("连接地址") {
                                TextField("https://mcp.example.com/mcp", text: $draft.command)
                                    .textFieldStyle(.roundedBorder)
                            }
                            MCPSourceDialogHint("远程连接建议使用 HTTPS；本机服务可使用 localhost 或 127.0.0.1。")
                        } else {
                            MCPSourceDialogRow("启动命令") {
                                TextField("/usr/bin/python3 或 npx", text: $draft.command)
                                    .textFieldStyle(.roundedBorder)
                            }
                            MCPSourceDialogRow("启动参数", alignment: .top) {
                                TextField("用空格或换行分隔", text: $draft.argumentsText, axis: .vertical)
                                    .textFieldStyle(.roundedBorder)
                                    .lineLimit(2...4)
                            }
                        }
                    }

                    MCPSourceDialogSection(title: "凭据", systemImage: "key") {
                        MCPSourceDialogRow("类型") {
                            Picker("", selection: $draft.credentialRequirement) {
                                Text("不需要").tag(ProductOSCredentialRequirement.none)
                                Text("Bearer Token").tag(ProductOSCredentialRequirement.bearerToken)
                                Text("API Key 请求头").tag(ProductOSCredentialRequirement.apiKeyHeader)
                                Text("多个请求头").tag(ProductOSCredentialRequirement.multiHeader)
                            }
                            .labelsHidden()
                            .frame(maxWidth: 240, alignment: .leading)
                        }
                        if draft.credentialRequirement != .none {
                            MCPSourceDialogRow("凭据名称") {
                                TextField("GITHUB_TOKEN 或 x-api-key:API_KEY", text: $draft.credentialEnvironmentText)
                                    .textFieldStyle(.roundedBorder)
                            }
                            MCPSourceDialogRow("密钥内容") {
                                SecureField(draft.isEditing ? "留空则保留现有密钥" : "密钥内容，或每行一个 NAME=secret", text: $draft.credentialSecret)
                                    .textFieldStyle(.roundedBorder)
                            }
                            MCPSourceDialogHint("密钥只会安全保存在本机，不会写入连接配置。")
                        }
                    }

                    MCPSourceDialogSection(title: "权限", systemImage: "checkmark.shield") {
                        MCPSourceDialogRow("状态") {
                            Picker("", selection: $draft.status) {
                                Text("草稿").tag(ProductOSRegistryEntryStatus.draft)
                                Text("已启用").tag(ProductOSRegistryEntryStatus.enabled)
                                Text("已停用").tag(ProductOSRegistryEntryStatus.disabled)
                                Text("需要确认").tag(ProductOSRegistryEntryStatus.needsReview)
                            }
                            .labelsHidden()
                            .frame(maxWidth: 180, alignment: .leading)
                        }
                        MCPSourceDialogToggleRow("允许外部网络", isOn: $draft.allowExternalNetwork)
                        MCPSourceDialogToggleRow("允许读取会话", isOn: $draft.allowReadSession)
                        MCPSourceDialogToggleRow("允许读取工作区", isOn: $draft.allowWorkspaceRead)
                        MCPSourceDialogRow("写入记忆") {
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
                Text(draft.isEditing ? "编辑外部工具连接" : "添加外部工具连接")
                    .font(AppTypography.pageTitle)
                Text("连接本机命令或 HTTP 工具服务。凭据会安全保存在本机，不写入连接配置。")
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
                Text("连接标识建议使用小写英文、数字和连字符。")
                Text("需要凭据时，请使用清晰的凭据名称。")
            }
            .font(AgentChatTypography.meta)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Spacer()
            Button("取消", action: onCancel)
            Button(draft.isEditing ? "保存修改" : "保存连接", action: onSave)
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
            .appListRowSurface(isSelected: isSelected)
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
