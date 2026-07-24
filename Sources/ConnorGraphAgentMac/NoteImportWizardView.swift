import SwiftUI
import ConnorGraphCore
import ConnorGraphAppSupport

struct NoteImportWizardView: View {
    @ObservedObject var model: NoteImportViewModel
    var importExecutionEnabled = true
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            wizardHeader
            Divider()
            ScrollView { content.padding(28).frame(maxWidth: .infinity, alignment: .topLeading) }
            Divider()
            footer
        }
        .frame(minWidth: 720, minHeight: 580)
        .alert("导入笔记", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("好") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    private var wizardHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 28, weight: .medium)).foregroundStyle(.tint)
                .frame(width: 44, height: 44).background(.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text("导入笔记").font(AppTypography.pageTitle)
                Text(stepSubtitle).foregroundStyle(.secondary)
            }
            Spacer()
            Text("第 \(model.step.rawValue + 1) 步，共 \(NoteImportViewModel.Step.allCases.count) 步")
                .font(.callout).foregroundStyle(.secondary)
        }.padding(.horizontal, 28).padding(.vertical, 20)
    }

    @ViewBuilder private var content: some View {
        switch model.step {
        case .source: sourceStep
        case .review: reviewStep
        case .options: optionsStep
        case .confirm: confirmStep
        }
    }

    private var sourceStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("选择来源").font(AppTypography.sectionTitle)
            Text("Connor 会保留原始内容和来源信息。导入在本机后台完成。")
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(NoteImportSourceKind.allCases, id: \.self) { kind in
                    sourceCard(kind)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: model.sourceKind.systemImage).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.sourceURL?.lastPathComponent ?? "尚未选择来源").fontWeight(.medium)
                        Text(model.sourceURL?.deletingLastPathComponent().path ?? model.sourceKind.selectionHint)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    Button(model.sourceURL == nil ? "选择…" : "更改…") { model.chooseSource() }
                }
                if model.sourceKind == .notionExport {
                    Label("当前请选择已解压的 Notion 导出文件夹；ZIP 直读将在安全归档验证完成后开放。", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(16).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func sourceCard(_ kind: NoteImportSourceKind) -> some View {
        Button { model.sourceKind = kind; model.sourceURL = nil; model.notes = [] } label: {
            HStack(spacing: 12) {
                Image(systemName: kind.systemImage).font(.title2).frame(width: 30).foregroundStyle(model.sourceKind == kind ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(kind.displayName).fontWeight(.semibold)
                    Text(kind.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                if model.sourceKind == kind { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
            }.padding(14).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(model.sourceKind == kind ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(model.sourceKind == kind ? Color.accentColor.opacity(0.55) : .clear, lineWidth: 1))
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("检查导入内容").font(AppTypography.sectionTitle); Spacer(); summaryPills }
            if model.notes.isEmpty {
                ContentUnavailableView("没有找到可导入的笔记", systemImage: "doc.text.magnifyingglass", description: Text("请返回并选择其他来源。"))
                    .frame(maxWidth: .infinity, minHeight: 300)
            } else {
                HStack {
                    TextField("搜索标题或路径", text: $model.searchText).textFieldStyle(.roundedBorder)
                    if model.warningCount > 0 { Label("\(model.warningCount) 个问题", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                }
                Table(model.filteredNotes) {
                    TableColumn("标题") { Text($0.title).lineLimit(1) }
                    TableColumn("路径") { Text($0.relativePath ?? "—").foregroundStyle(.secondary).lineLimit(1) }
                    TableColumn("附件") { Text("\($0.attachments.count)") }.width(55)
                    TableColumn("状态") { note in
                        Label(note.diagnostics.isEmpty ? "可导入" : "需注意", systemImage: note.diagnostics.isEmpty ? "checkmark.circle" : "exclamationmark.triangle")
                            .foregroundStyle(note.diagnostics.isEmpty ? Color.secondary : Color.orange)
                    }.width(90)
                }.frame(minHeight: 300)
            }
        }
    }

    private var optionsStep: some View {
        Form {
            Section("内容") {
                Toggle("导入附件", isOn: $model.options.importAttachments)
                Picker("遇到重复笔记", selection: $model.options.duplicatePolicy) {
                    Text("跳过未变化的内容").tag(NoteImportDuplicatePolicy.skipUnchanged)
                    Text("作为更新追加").tag(NoteImportDuplicatePolicy.appendUpdate)
                    Text("创建副本").tag(NoteImportDuplicatePolicy.createCopy)
                }
            }
            Section("AI 处理") {
                Toggle("导入后自动理解和整理", isOn: Binding(get: { model.options.llmMode == .automatic }, set: { model.options.llmMode = $0 ? .automatic : .disabled }))
                Text("原始笔记始终会先保存。关闭 AI 不会影响正文和附件导入。")
                    .font(.caption).foregroundStyle(.secondary)
                if model.options.llmMode == .automatic {
                    Stepper("并行处理：\(model.options.llmConcurrency)", value: $model.options.llmConcurrency, in: 1...3)
                    Toggle("允许 AI 使用网络读取工具", isOn: $model.options.allowNetworkReadTools)
                    Text("网络读取默认关闭；开启后，AI 可能根据笔记内容访问外部网页。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }.formStyle(.grouped)
    }

    private var confirmStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("确认导入").font(AppTypography.sectionTitle)
            VStack(spacing: 0) {
                confirmationRow("来源", model.sourceKind.displayName, "externaldrive")
                Divider()
                confirmationRow("位置", model.sourceURL?.path ?? "—", "folder")
                Divider()
                confirmationRow("笔记", "\(model.notes.count) 篇", "doc.text")
                Divider()
                confirmationRow("附件", model.options.importAttachments ? "\(model.attachmentCount) 个" : "不导入", "paperclip")
                Divider()
                confirmationRow("AI 处理", model.options.llmMode == .automatic ? "自动，最多并行 \(model.options.llmConcurrency) 项" : "关闭", "sparkles")
            }.background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            Label("导入会在后台继续。你可以关闭此窗口，并在“笔记导入中心”查看、暂停或取消任务。", systemImage: "clock.arrow.circlepath")
                .foregroundStyle(.secondary)
        }
    }

    private func confirmationRow(_ title: String, _ value: String, _ image: String) -> some View {
        HStack(spacing: 12) { Image(systemName: image).foregroundStyle(.secondary).frame(width: 22); Text(title); Spacer(); Text(value).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }.padding(14)
    }

    private var footer: some View {
        HStack {
            if model.step != .source { Button("上一步") { model.back() }.disabled(model.isBusy) }
            Spacer()
            if model.isBusy { ProgressView().controlSize(.small); Text(activityLabel).foregroundStyle(.secondary) }
            if model.step == .source {
                Button("扫描内容") { Task { await model.scanSource() } }
                    .buttonStyle(.borderedProminent).disabled(model.sourceURL == nil || model.isBusy)
            } else if model.step != .confirm {
                Button("继续") { model.advance() }.buttonStyle(.borderedProminent).disabled(model.notes.isEmpty || model.isBusy)
            } else {
                Button("开始导入") {
                    Task {
                        if await model.startImport() {
                            openWindow(id: AppMenuPresentation.noteImportCenterWindowID)
                            dismiss()
                            model.resetWizard()
                        }
                    }
                }.buttonStyle(.borderedProminent).disabled(!importExecutionEnabled || model.notes.isEmpty || model.isBusy)
                    .help(importExecutionEnabled ? "开始后台导入" : "此构建尚未启用导入执行")
            }
        }.padding(.horizontal, 28).padding(.vertical, 16)
    }

    private var stepSubtitle: String { ["选择笔记来源", "预览并检查内容", "设置导入方式", "确认后在后台开始"][model.step.rawValue] }
    private var activityLabel: String { switch model.activity { case .idle: ""; case .scanning: "正在扫描…"; case .starting: "正在创建任务…"; case .importing: "正在导入…" } }
    private var summaryPills: some View { HStack { Label("\(model.notes.count) 篇", systemImage: "doc.text"); Label("\(model.attachmentCount) 个附件", systemImage: "paperclip") }.font(.callout).foregroundStyle(.secondary) }
}
