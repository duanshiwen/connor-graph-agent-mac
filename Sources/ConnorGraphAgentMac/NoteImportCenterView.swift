import SwiftUI
import ConnorGraphCore
import ConnorGraphAppSupport

struct NoteImportCenterView: View {
    @ObservedObject var model: NoteImportViewModel
    @Environment(\.openWindow) private var openWindow
    @State private var confirmsCancellation = false
    @State private var confirmsDeletion = false
    @State private var pendingDeletionJobID: String?
    @State private var pendingControlJobID: String?
    @State private var selectedJobID: String?
    @State private var hasInitializedSelection = false

    var body: some View {
        NavigationSplitView {
            List {
                if !activeJobs.isEmpty { Section("进行中") { ForEach(activeJobs) { jobRow($0) } } }
                if !issueJobs.isEmpty { Section("需要处理") { ForEach(issueJobs) { jobRow($0) } } }
                if !completedJobs.isEmpty { Section("已完成") { ForEach(completedJobs) { jobRow($0) } } }
            }
            .navigationTitle("导入中心")
            .contentMargins(.top, 6, for: .scrollContent)
            .frame(minWidth: 260)
        } detail: {
            if let job = model.selectedJob { jobDetail(job) }
            else { ContentUnavailableView("还没有导入任务", systemImage: "square.and.arrow.down", description: Text("从 Markdown、Obsidian、Notion 或 ENEX 导入笔记。")) }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button { openWindow(id: AppMenuPresentation.noteImportWizardWindowID) } label: { Label("新建导入", systemImage: "plus") } }
            ToolbarItem { Button { Task { await model.reloadJobs() } } label: { Label("刷新", systemImage: "arrow.clockwise") } }
        }
        .task {
            await model.reloadJobs()
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                selectedJobID = model.selectedJobID
                hasInitializedSelection = true
            }
        }
        .task(id: selectedJobID) {
            guard hasInitializedSelection else { return }
            await model.selectJob(selectedJobID)
        }
        .onChange(of: model.selectedJobID) { _, newValue in
            guard hasInitializedSelection else { return }
            if selectedJobID != newValue { selectedJobID = newValue }
        }
        .confirmationDialog("取消剩余导入？", isPresented: $confirmsCancellation) {
            Button("取消剩余导入", role: .destructive) { Task { await model.cancelSelectedJob() } }
        } message: { Text("已经创建的笔记会保留，尚未开始的项目不会导入。") }
        .confirmationDialog("删除这条导入记录？", isPresented: $confirmsDeletion) {
            Button("删除导入记录", role: .destructive) {
                guard let id = pendingDeletionJobID else { return }
                Task { await model.deleteJob(id: id) }
            }
        } message: { Text("只会删除导入过程记录和暂存数据，已经导入的笔记会保留。") }
        .alert("导入中心", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("好") { model.error = nil } } message: { Text(model.error ?? "") }
    }

    private var activeJobs: [NoteImportJobRecord] {
        model.jobs.filter { NoteImportActivitySummary.isVisible($0) && !NoteImportActivitySummary.isPaused($0) }
    }
    private var issueJobs: [NoteImportJobRecord] {
        model.jobs.filter {
            NoteImportActivitySummary.isPaused($0) || $0.status == .completedWithIssues || $0.status == .failed
        }
    }
    private var completedJobs: [NoteImportJobRecord] {
        model.jobs.filter { $0.status == .completed || $0.status == .cancelled }
    }

    private func jobRow(_ job: NoteImportJobRecord) -> some View {
        let presentation = NoteImportJobPresentation(
            job: job,
            runtimeState: model.runtimeSnapshot.state(for: job.id)
        )
        return Button {
            selectedJobID = job.id
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack { Image(systemName: presentation.systemImage).foregroundStyle(job.status.tint); Text(model.sourceNamesByID[job.sourceID] ?? "笔记导入").fontWeight(.medium).lineLimit(1); Spacer() }
                jobProgress(job)
                HStack {
                    Text(presentation.displayName)
                    Spacer()
                    Text("\(NoteImportActivitySummary.processedCount(for: job))/\(job.discoveredCount)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .listRowBackground(selectedJobID == job.id ? Color.accentColor.opacity(0.14) : Color.clear)
        .onAppear { Task { await model.loadMoreJobsIfNeeded(currentJobID: job.id) } }
        .contextMenu {
            if job.status.isTerminal {
                Button("删除导入记录", systemImage: "trash", role: .destructive) {
                    selectedJobID = job.id
                    pendingDeletionJobID = job.id
                    confirmsDeletion = true
                }
            }
        }
    }

    private func jobDetail(_ job: NoteImportJobRecord) -> some View {
        let presentation = NoteImportJobPresentation(
            job: job,
            runtimeState: model.runtimeSnapshot.state(for: job.id)
        )
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: AppShellLayout.spaceXS) { Text(model.sourceNamesByID[job.sourceID] ?? "笔记导入").font(AppTypography.pageTitle); Label(presentation.displayName, systemImage: presentation.systemImage).foregroundStyle(job.status.tint) }
                Spacer()
                controls(job)
            }.padding(24)
            Divider()
            VStack(alignment: .leading, spacing: 16) {
                jobProgress(job)
                HStack(spacing: 24) { metric("已发现", job.discoveredCount); metric("已导入", job.importedCount); metric("重复", job.duplicateCount); metric("失败", job.failedCount) }
                Table(model.selectedJobItems) {
                    TableColumn("笔记") { item in
                        Text(item.title)
                            .lineLimit(1)
                            .onAppear { Task { await model.loadMoreSelectedJobItemsIfNeeded(currentItemID: item.id) } }
                    }
                    TableColumn("路径") { Text($0.relativePath ?? "—").foregroundStyle(.secondary).lineLimit(1) }
                    TableColumn("状态") { Label($0.status.displayName, systemImage: $0.status.systemImage).foregroundStyle($0.status.tint) }.width(120)
                    TableColumn("问题") { Text($0.errorMessage ?? "—").foregroundStyle($0.errorMessage == nil ? Color.secondary : Color.red).lineLimit(1) }
                }
            }.padding(24)
        }
    }

    @ViewBuilder private func controls(_ job: NoteImportJobRecord) -> some View {
        HStack {
            if let presentation = NoteImportControlPresentation(
                job: job,
                runtimeState: model.runtimeSnapshot.state(for: job.id)
            ) {
                Button(presentation.title, systemImage: presentation.systemImage) {
                    pendingControlJobID = job.id
                    Task {
                        switch presentation.action {
                        case .pause: await model.pauseSelectedJob()
                        case .resume: await model.resumeSelectedJob()
                        case .restart: await model.restartSelectedJob()
                        }
                        pendingControlJobID = nil
                    }
                }
                .disabled(pendingControlJobID == job.id)
            }
            if !job.status.isTerminal, job.cancelRequestedAt == nil, job.status != .cancelling {
                Button("取消…", role: .destructive) { confirmsCancellation = true }
            }
            if job.status.isTerminal {
                Button("删除记录…", systemImage: "trash", role: .destructive) {
                    pendingDeletionJobID = job.id
                    confirmsDeletion = true
                }
            }
        }
    }

    @ViewBuilder
    private func jobProgress(_ job: NoteImportJobRecord) -> some View {
        if job.discoveredCount > 0 {
            ProgressView(
                value: Double(NoteImportActivitySummary.processedCount(for: job)),
                total: Double(job.discoveredCount)
            )
            .tint(NoteImportProgressAppearance.accentColor)
        } else {
            ProgressView()
                .tint(NoteImportProgressAppearance.accentColor)
        }
    }

    private func metric(_ title: String, _ value: Int) -> some View { VStack(alignment: .leading, spacing: 2) { Text("\(value)").font(.title3.bold()); Text(title).font(.caption).foregroundStyle(.secondary) }.frame(minWidth: 72, alignment: .leading) }
}
