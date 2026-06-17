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
                onAdd: viewModel.presentAddSourceSheet,
                onRefresh: viewModel.reloadSourceRuntimeConfigurations
            )

            if presentation.cards.isEmpty {
                SourceListEmptyState(onAdd: viewModel.presentAddSourceSheet)
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
    var onAdd: () -> Void
    var onRefresh: () -> Void

    var body: some View {
        ZStack {
            Text("MCP")
                .font(AppListTypography.header)
                .frame(maxWidth: .infinity, alignment: .center)
            HStack(spacing: 8) {
                Spacer()
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 12.5, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
                .help("添加 MCP Source")
                .accessibilityLabel("添加 MCP Source")

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
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }
}

private struct SourceListEmptyState: View {
    var onAdd: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ContentUnavailableView(
                "暂无 MCP Source",
                systemImage: "server.rack",
                description: Text("添加并测试 MCP source 后，它会显示在这里。")
            )
            Button(action: onAdd) {
                Label("添加 Source", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.top, 80)
    }
}

private struct MCPSourceAddSheet: View {
    @Binding var draft: MCPSourceDraft
    var message: String?
    var onCancel: () -> Void
    var onSave: () -> Void

    private var canSave: Bool {
        !draft.normalizedSourceID.isEmpty &&
        !draft.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceL) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: AgentChatLayout.spaceXS) {
                    Text(draft.isEditing ? "编辑 MCP Source" : "添加 MCP Source")
                        .font(.system(size: 22, weight: .semibold))
                    Text("当前最小闭环支持 stdio + no credential。保存后可运行 Test Source 刷新工具目录。")
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
                    TextField("Command，例如 /usr/bin/python3 或 npx", text: $draft.command)
                    TextField("Arguments，用空格或换行分隔", text: $draft.argumentsText, axis: .vertical)
                        .lineLimit(2...4)
                    LabeledContent("Mode") {
                        Text("stdio · no credential")
                            .foregroundStyle(.secondary)
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
                Text("Source ID 需匹配 lowercase kebab-case；command 不能为空。")
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
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(rowColor.opacity(isSelected ? 0.20 : 0.12))
                    Image(systemName: "server.rack")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(rowColor)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Circle().fill(rowColor).frame(width: 7, height: 7)
                        Text(card.title)
                            .font(isSelected ? AppListTypography.rowTitleSelected : AppListTypography.rowTitle)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    Text(card.transportLabel)
                        .font(AppListTypography.rowSubtitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 6) {
                        SourceMiniPill(text: card.statusLabel, color: rowColor)
                        SourceMiniPill(text: card.toolCountLabel, color: .secondary)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.24) : Color.clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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

private struct SourceMiniPill: View {
    var text: String
    var color: Color

    var body: some View {
        Text(text)
            .font(AppListTypography.rowCaption)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .frame(height: 18)
            .foregroundStyle(color)
            .background(color.opacity(0.11), in: Capsule())
    }
}
