import SwiftUI
import ConnorGraphCore
import ConnorGraphAppSupport

@MainActor
struct KnowledgePublicationActivitySummary: Equatable {
    enum PresentationState: Equatable { case running, paused, needsReview, conflict }

    var stage: CloudKnowledgeCreatorStage
    var processedCount: Int
    var totalCount: Int

    init(store: CloudKnowledgeCreatorStore) {
        stage = store.snapshot.stage
        processedCount = store.snapshot.processedConversationIDs.count
        totalCount = store.snapshot.selectedConversationIDs.count
    }

    var isVisible: Bool { [.generating, .paused, .validating, .preview, .conflict].contains(stage) }
    var progressFraction: Double? {
        guard totalCount > 0 else { return nil }
        return min(max(Double(processedCount) / Double(totalCount), 0), 1)
    }
    var presentationState: PresentationState {
        switch stage {
        case .paused: .paused
        case .preview, .validating: .needsReview
        case .conflict: .conflict
        default: .running
        }
    }
}

struct KnowledgePublicationToolbarProgressButton: View {
    @ObservedObject var store: CloudKnowledgeCreatorStore
    var action: () -> Void

    private var summary: KnowledgePublicationActivitySummary { .init(store: store) }

    @ViewBuilder
    var body: some View {
        if summary.isVisible {
            Button(action: action) {
                ZStack {
                    if let progress = summary.progressFraction {
                        Circle().stroke(Color.secondary.opacity(0.22), lineWidth: 2.5)
                        Circle().trim(from: 0, to: progress)
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    } else {
                        ProgressView().controlSize(.small).progressViewStyle(.circular)
                    }
                    statusImage.font(.system(size: 8, weight: .bold)).foregroundStyle(Color.accentColor)
                }
                .frame(width: 21, height: 21)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(helpText)
            .accessibilityLabel("打开知识库发布进度")
            .accessibilityValue(helpText)
        }
    }

    @ViewBuilder private var statusImage: some View {
        switch summary.presentationState {
        case .running: Image(systemName: "sparkles")
        case .paused: Image(systemName: "pause.fill")
        case .needsReview: Image(systemName: "checkmark")
        case .conflict: Image(systemName: "exclamationmark")
        }
    }

    private var helpText: String {
        let progress = summary.progressFraction.map { " · \(Int(($0 * 100).rounded()))%" } ?? ""
        return switch summary.presentationState {
        case .running: "打开知识库发布进度\(progress)"
        case .paused: "知识库发布已暂停\(progress)"
        case .needsReview: "知识库发布等待检查\(progress)"
        case .conflict: "知识库发布需要处理冲突\(progress)"
        }
    }
}

struct KnowledgePublicationProgressView: View {
    @ObservedObject var store: CloudKnowledgeCreatorStore
    var sessions: [AgentSession]
    @State private var confirmsCancellation = false

    private var selectedSessions: [AgentSession] {
        let byID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        return store.snapshot.selectedConversationIDs.map { id in
            byID[id] ?? AgentSession(id: id, title: "会话 \(id.prefix(8))")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 30)).foregroundStyle(Color.accentColor)
                    .frame(width: 52, height: 52)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 5) {
                    Text(store.snapshot.draft.name.isEmpty ? "知识库发布" : store.snapshot.draft.name).font(.title2.bold())
                    Label(stageTitle, systemImage: stageIcon).foregroundStyle(stageColor)
                }
                Spacer()
                controls
            }
            .padding(24)

            Divider()

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: Double(store.snapshot.processedConversationIDs.count), total: Double(max(1, store.snapshot.selectedConversationIDs.count)))
                        .tint(Color.accentColor)
                    HStack {
                        Text("已处理 \(store.snapshot.processedConversationIDs.count) / \(store.snapshot.selectedConversationIDs.count) 个会话")
                        Spacer()
                        if let current = currentSession { Text("正在处理：\(current.title)").foregroundStyle(Color.accentColor) }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }

                if let error = store.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red).padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }

                Table(selectedSessions) {
                    TableColumn("会话") { session in Text(session.title).lineLimit(1) }
                    TableColumn("消息") { session in Text("\(session.messages.count)").foregroundStyle(.secondary) }.width(60)
                    TableColumn("状态") { session in
                        let presentation = conversationPresentation(session.id)
                        Label(presentation.title, systemImage: presentation.systemImage).foregroundStyle(presentation.color)
                    }.width(130)
                }

                if !store.snapshot.summaries.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("处理记录").font(.headline)
                        ForEach(Array(store.snapshot.summaries.enumerated()), id: \.offset) { _, summary in
                            Label(summary, systemImage: "checkmark.circle").font(.callout).lineLimit(3)
                        }
                    }
                }
            }
            .padding(24)
        }
        .frame(minWidth: 760, minHeight: 520)
        .confirmationDialog("取消知识库发布？", isPresented: $confirmsCancellation) {
            Button("取消剩余处理", role: .destructive) { store.cancel() }
        } message: {
            Text("已经暂存的知识操作会随 Publication Run 一起放弃，不会写入正式知识库。")
        }
    }

    @ViewBuilder private var controls: some View {
        HStack {
            switch store.snapshot.stage {
            case .generating:
                Button("暂停", systemImage: "pause") { store.pause() }
                Button("取消…", role: .destructive) { confirmsCancellation = true }
            case .paused:
                Button("继续", systemImage: "play") { store.resume() }
                Button("取消…", role: .destructive) { confirmsCancellation = true }
            case .validating:
                Button("验证发布", systemImage: "checkmark.shield") { Task { await store.validatePublication() } }
            case .preview:
                Button("返回知识市场", systemImage: "storefront") { }
                    .disabled(true)
            case .conflict:
                Label("需要在发布页处理冲突", systemImage: "arrow.triangle.2.circlepath")
            default: EmptyView()
            }
        }
    }

    private var currentSession: AgentSession? {
        guard let id = store.currentConversationID else { return nil }
        return selectedSessions.first { $0.id == id }
    }

    private func conversationPresentation(_ id: String) -> (title: String, systemImage: String, color: Color) {
        if store.snapshot.processedConversationIDs.contains(id) { return ("已完成", "checkmark.circle.fill", .green) }
        if store.currentConversationID == id { return ("AI 处理中", "sparkles", .accentColor) }
        if store.snapshot.stage == .cancelled { return ("已取消", "xmark.circle", .secondary) }
        return ("等待处理", "clock", .secondary)
    }

    private var stageTitle: String {
        switch store.snapshot.stage {
        case .configure: "配置知识库"
        case .conversations: "选择会话"
        case .confirm: "等待确认"
        case .generating: "AI 正在生成知识"
        case .paused: "已暂停"
        case .validating: "等待验证"
        case .preview: "等待提交"
        case .conflict: "存在版本冲突"
        case .completed: "已完成"
        case .cancelled: "已取消"
        }
    }
    private var stageIcon: String {
        switch store.snapshot.stage {
        case .generating: "sparkles"
        case .paused: "pause.circle.fill"
        case .validating, .preview: "checkmark.shield"
        case .conflict: "exclamationmark.triangle.fill"
        case .completed: "checkmark.circle.fill"
        case .cancelled: "xmark.circle"
        default: "books.vertical"
        }
    }
    private var stageColor: Color {
        switch store.snapshot.stage {
        case .conflict: .orange
        case .completed: .green
        case .cancelled: .secondary
        default: .accentColor
        }
    }
}
