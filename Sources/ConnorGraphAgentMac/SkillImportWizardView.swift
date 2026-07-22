import SwiftUI
import AppKit
import ConnorGraphAppSupport

struct SkillImportWizardView: View {
    @Bindable var model: SkillRuntimeFeatureModel
    @Environment(\.dismiss) private var dismiss

    private var selectedCount: Int { model.selectedImportCandidateIDs.count }
    private var availableCount: Int { model.importCandidates.filter { !$0.isAlreadyImported }.count }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 760, minHeight: 600)
        .onAppear {
            if model.importCandidates.isEmpty {
                model.prepareSkillImport()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 44, height: 44)
                .background(.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: AppShellLayout.radiusM, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("导入技能")
                    .font(AppTypography.pageTitle)
                Text("从常用 Agent 技能库复制到康纳，源文件保持不变。")
                    .font(AppTypography.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(availableCount)")
                    .font(.title3.bold())
                Text("可导入")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: AppShellLayout.spaceM) {
            controls
            sourceSummary

            if model.filteredImportCandidates.isEmpty {
                ContentUnavailableView(
                    model.importCandidates.isEmpty ? "未发现技能" : "没有匹配的技能",
                    systemImage: "folder.badge.questionmark",
                    description: Text(model.importCandidates.isEmpty ? "可以选择其他 Agent 的技能目录继续扫描。" : "调整搜索词或来源筛选。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                candidateList
            }

            if !model.importWarnings.isEmpty {
                Label("\(model.importWarnings.count) 个目录或技能无法读取", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help(model.importWarnings.joined(separator: "\n"))
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var controls: some View {
        HStack(spacing: AppShellLayout.spaceS) {
            TextField("搜索技能名称或描述", text: $model.importSearchText)
                .textFieldStyle(.roundedBorder)

            Picker("来源", selection: $model.importSourceFilter) {
                Text("所有来源").tag(nil as ExternalSkillLibrarySource?)
                ForEach(model.discoveredImportSources, id: \.self) { source in
                    Text(source.title).tag(source as ExternalSkillLibrarySource?)
                }
            }
            .frame(width: 150)

            Button {
                chooseAdditionalDirectory()
            } label: {
                Label("其他目录", systemImage: "folder.badge.plus")
            }

            Button {
                model.prepareSkillImport()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("重新扫描")
        }
    }

    private var sourceSummary: some View {
        HStack {
            Text("已扫描 Claude Code、Codex、Cursor、Copilot、Gemini CLI、OpenCode、Windsurf、Cline 和通用 Agent 目录")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button("全选") { model.selectAllVisibleImportCandidates() }
                .buttonStyle(.link)
            Button("取消全选") { model.deselectAllImportCandidates() }
                .buttonStyle(.link)
        }
    }

    private var candidateList: some View {
        List(model.filteredImportCandidates) { candidate in
            Toggle(isOn: Binding(
                get: { model.selectedImportCandidateIDs.contains(candidate.id) },
                set: { model.setImportCandidateSelected(candidate.id, isSelected: $0) }
            )) {
                HStack(alignment: .top, spacing: AppShellLayout.spaceM) {
                    Image(systemName: sourceIcon(candidate.source))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(candidate.name)
                                .font(AppTypography.bodyEmphasis)
                            Text(candidate.source.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if candidate.isAlreadyImported {
                                Label("已存在", systemImage: "checkmark.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(candidate.description)
                            .font(AppTypography.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Text(candidate.packageURL.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .padding(.vertical, 4)
            }
            .toggleStyle(.checkbox)
            .disabled(candidate.isAlreadyImported || model.isImporting)
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(Color.secondary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: AppShellLayout.radiusM, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppShellLayout.radiusM, style: .continuous)
                .stroke(AppShellColors.hairline, lineWidth: 1)
        )
    }

    private var footer: some View {
        HStack(spacing: AppShellLayout.spaceM) {
            if let message = model.importDialogMessage {
                if model.isImporting { ProgressView().controlSize(.small) }
                Image(systemName: model.isImporting ? "arrow.down.circle" : (message.contains("失败") ? "exclamationmark.triangle" : "checkmark.circle"))
                    .foregroundStyle(message.contains("失败") ? .orange : .secondary)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("关闭") {
                model.resetSkillImport()
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .disabled(model.isImporting)

            Button(model.isImporting ? "导入中…" : "导入 \(selectedCount) 个技能") {
                Task { await model.submitSkillImport() }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(selectedCount == 0 || model.isImporting)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
    }

    private func chooseAdditionalDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择 Agent 技能目录"
        panel.prompt = "扫描此目录"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.addCustomImportRoot(url)
    }

    private func sourceIcon(_ source: ExternalSkillLibrarySource) -> String {
        switch source {
        case .claudeCode: "c.circle"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .cursor: "cursorarrow.rays"
        case .githubCopilot: "chevron.left.forwardslash.chevron.right"
        case .geminiCLI: "sparkles"
        case .openCode: "terminal"
        case .windsurf: "wind"
        case .cline: "command"
        case .agents: "person.2"
        case .custom: "folder"
        }
    }
}
