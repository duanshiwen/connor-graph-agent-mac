import SwiftUI
import ConnorGraphCore
import ConnorGraphAppSupport

@MainActor final class NoteImportViewModel: ObservableObject {
    enum Step: Int, CaseIterable { case source, preview, encoding, options, confirm }
    @Published var step: Step = .source
    @Published var sourceKind: NoteImportSourceKind = .markdownFolder
    @Published var sourceURL: URL?
    @Published var options = NoteImportOptions()
    @Published var notes: [ImportedNote] = []
    @Published var jobs: [NoteImportJobRecord] = []
    @Published var error: String?

    let ledger: AppNoteImportRepository?
    let coordinator: NoteImportCoordinator?
    let sourceAccessService: NoteImportSourceAccessService

    init(
        ledger: AppNoteImportRepository? = nil,
        coordinator: NoteImportCoordinator? = nil,
        sourceAccessService: NoteImportSourceAccessService = .init(),
        configurationError: String? = nil
    ) {
        self.ledger = ledger
        self.coordinator = coordinator
        self.sourceAccessService = sourceAccessService
        self.error = configurationError
        reloadJobs()
    }

    convenience init(configurationError: String) {
        self.init(configurationError: Optional(configurationError))
    }

    var encodingReview: [ImportedNote] { notes.filter { $0.diagnostics.contains { $0.code == .decodingAmbiguous || $0.code == .decodingFailed } } }
    var canAdvance: Bool { step != .source || sourceURL != nil }
    func advance() { if let next = Step(rawValue: step.rawValue + 1) { step = next } }
    func back() { if let previous = Step(rawValue: step.rawValue - 1) { step = previous } }
    func reloadJobs() {
        guard let ledger else { return }
        do { jobs = try ledger.jobs() } catch { self.error = error.localizedDescription }
    }
}

struct NoteImportWizardView: View {
    @ObservedObject var model: NoteImportViewModel
    var importExecutionEnabled = true

    var body: some View { VStack(alignment: .leading, spacing: 16) { Text("导入笔记").font(.title2.bold()); if !importExecutionEnabled { Label("批量导入正在发布验证中。你可以查看向导，但暂时不能启动导入。", systemImage: "exclamationmark.shield").foregroundStyle(.secondary) }; ProgressView(value: Double(model.step.rawValue + 1), total: Double(NoteImportViewModel.Step.allCases.count)); content; Divider(); HStack { if model.step != .source { Button("上一步", action: model.back) }; Spacer(); if model.step != .confirm { Button("继续", action: model.advance).disabled(!model.canAdvance) } else { Button("开始后台导入") {}.buttonStyle(.borderedProminent).disabled(!importExecutionEnabled).help(importExecutionEnabled ? "开始后台导入" : "商业发布验证完成后可用") } } }.padding(24).frame(minWidth: 680, minHeight: 520) }
    @ViewBuilder private var content: some View { switch model.step { case .source: VStack(alignment: .leading) { Picker("来源", selection: $model.sourceKind) { ForEach(NoteImportSourceKind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }; Text(model.sourceURL?.path ?? "请选择文件夹、Notion ZIP 或 ENEX 文件").foregroundStyle(.secondary) }; case .preview: summary; case .encoding: List(model.encodingReview) { Text($0.relativePath ?? $0.title); Text($0.diagnostics.first?.message ?? "需要确认编码").foregroundStyle(.secondary) }; case .options: Form { Toggle("导入附件", isOn: $model.options.importAttachments); Toggle("自动运行 LLM", isOn: Binding(get: { model.options.llmMode == .automatic }, set: { model.options.llmMode = $0 ? .automatic : .disabled })); Stepper("LLM 并发：\(model.options.llmConcurrency)", value: $model.options.llmConcurrency, in: 1...3) }; case .confirm: summary } }
    private var summary: some View { List { LabeledContent("笔记", value: "\(model.notes.count)"); LabeledContent("附件", value: "\(model.notes.reduce(0) { $0 + $1.attachments.count })"); LabeledContent("编码待确认", value: "\(model.encodingReview.count)") } }
}

struct NoteImportCenterView: View {
    @ObservedObject var model: NoteImportViewModel

    var body: some View {
        NavigationSplitView {
            List(model.jobs) { job in
                VStack(alignment: .leading) {
                    Text(job.sourceID).font(.headline)
                    ProgressView(
                        value: Double(job.importedCount + job.failedCount),
                        total: Double(max(job.discoveredCount, 1))
                    )
                    Text(job.status.rawValue).foregroundStyle(.secondary)
                }
            }
        } detail: {
            ContentUnavailableView("选择导入任务", systemImage: "tray.and.arrow.down")
        }
        .navigationTitle("导入中心")
    }
}
