import SwiftUI
import ConnorGraphCore
import ConnorGraphAppSupport

struct CloudKnowledgeCreatorView: View {
    @ObservedObject var store: CloudKnowledgeCreatorStore
    var sessions: [AgentSession]
    var onPublished: ((String) -> Void)? = nil
    @State private var draft = CloudKnowledgeBaseDraft()
    @State private var appealStatement = ""
    @State private var creatorTermsAccepted = false
    @State private var isPresentingPublishingAgreement = false

    var body: some View {
        VStack(spacing: 0) {
            stageHeader
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

            Divider()

            stageContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if store.snapshot.stage == .validating || store.snapshot.stage == .preview {
                Divider()
                pendingCommitBar
            }

            Divider()
            publicationFooter
        }
        .onAppear {
            draft = store.snapshot.draft
            Task {
                await store.refreshLatestKnowledgeBaseDetail()
                if (store.snapshot.stage == .validating && store.snapshot.validationIssues.isEmpty)
                    || store.snapshot.stage == .preview {
                    await store.finalizePublication()
                }
            }
        }
        .sheet(isPresented: $isPresentingPublishingAgreement) {
            publishingAgreement
        }
    }

    private var stageHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: stageIcon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(stageTitle)
                    .font(.headline)
                Text(stageProgressLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.isWorking {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var stageContent: some View {
        switch store.snapshot.stage {
        case .conversations:
            conversations
        default:
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch store.snapshot.stage {
                    case .configure: configure
                    case .confirm: confirmation
                    case .generating, .paused: progress
                    case .validating: validation
                    case .preview: preview
                    case .conflict: conflict
                    case .completed: completed
                    case .cancelled: cancelled
                    case .conversations: EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
        }
    }

    private var configure: some View {
        VStack(alignment: .leading, spacing: 16) {
            Form {
                TextField("知识库名称", text: $draft.name)
                TextField("Slug", text: $draft.slug)
                TextField("描述", text: $draft.description, axis: .vertical)
                    .lineLimit(3...5)
                Picker("可见性", selection: $draft.visibility) {
                    Text("私有").tag("private")
                    Text("不公开列出").tag("unlisted")
                    Text("公开").tag("public")
                }
                .pickerStyle(.segmented)
            }
            .formStyle(.grouped)

            actionBar {
                Spacer()
                Button("保存并选择对话") {
                    store.updateDraft(draft)
                    Task { await store.saveKnowledgeBase() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var conversations: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("选择用于生成知识的对话")
                    .font(.headline)
                Text("原始对话仅发送给当前 LLM 提供商进行分析；康纳知识后端只接收生成后的结构化知识操作。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            List {
                ForEach(sessions.prefix(100)) { session in
                    Toggle(isOn: conversationSelection(for: session.id)) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.title)
                                .font(.body)
                                .lineLimit(1)
                            Text("\(session.messages.count) 条消息")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                    }
                    .toggleStyle(.checkbox)
                }
            }
            .listStyle(.inset)
            .frame(minHeight: 280, maxHeight: .infinity)

            Divider()

            actionBar {
                Button("返回") { store.advance(to: .configure) }
                    .controlSize(.large)
                Spacer()
                Text("已选择 \(store.snapshot.selectedConversationIDs.count) 个对话")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("下一步：确认生成") { store.advance(to: .confirm) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(store.snapshot.selectedConversationIDs.isEmpty)
            }
        }
    }

    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 14) {
            summaryRow("从 \(store.snapshot.selectedConversationIDs.count) 个本地对话生成结构化 L2/L3/L4 知识操作", systemImage: "wand.and.stars")
            summaryRow("每组写入前检索已提交和本次暂存的知识", systemImage: "magnifyingglass")
            summaryRow("提交前可以查看完整变更预览", systemImage: "checkmark.rectangle")
            actionBar {
                Button("返回") { store.advance(to: .conversations) }
                    .controlSize(.large)
                Spacer()
                Button("确认并开始") { Task { await store.beginPublication() } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 14) {
            ProgressView(
                value: Double(store.snapshot.processedConversationIDs.count),
                total: Double(max(1, store.snapshot.selectedConversationIDs.count))
            )
            Text("已处理 \(store.snapshot.processedConversationIDs.count) / \(store.snapshot.selectedConversationIDs.count) 个对话")
                .font(.callout)
                .foregroundStyle(.secondary)
            ForEach(Array(store.snapshot.summaries.enumerated()), id: \.offset) { _, summary in
                Label(summary, systemImage: "checkmark.circle")
            }
            actionBar {
                Button(store.snapshot.stage == .paused ? "恢复" : "暂停") {
                    store.snapshot.stage == .paused ? store.resume() : store.pause()
                }
                .controlSize(.large)
                Button("取消", role: .destructive) { store.cancel() }
                    .controlSize(.large)
                Spacer()
                Button("验证发布") { Task { await store.validatePublication() } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(store.snapshot.processedConversationIDs.count < store.snapshot.selectedConversationIDs.count)
            }
        }
    }

    private var validation: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.snapshot.validationIssues.isEmpty {
                summaryRow("正在检查知识变更", systemImage: "checkmark.shield")
            } else {
                ForEach(store.snapshot.validationIssues) { issue in
                    Label(issue.message, systemImage: issue.repairable ? "wrench.and.screwdriver" : "exclamationmark.octagon")
                        .foregroundStyle(issue.repairable ? .orange : .red)
                }
            }
            actionBar {
                Spacer()
                Button("修复后重试") { Task { await store.finalizePublication() } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(store.snapshot.validationIssues.isEmpty || store.isWorking)
            }
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(store.snapshot.preview?.operations.count ?? 0) 项知识变更")
                .font(.headline)
            ForEach(store.snapshot.preview?.summaries ?? store.snapshot.summaries, id: \.self) { summary in
                Label(summary, systemImage: "doc.text.magnifyingglass")
            }
            ForEach(store.snapshot.preview?.operations ?? []) { operation in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(operation.layer.rawValue) · \(operation.operationType) · \(operation.decision.rawValue)")
                        .fontWeight(.medium)
                    Text(operation.semanticTerms.joined(separator: "、"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            actionBar {
                Button("返回修复") { store.advance(to: .validating) }
                    .controlSize(.large)
            }
        }
    }

    private var pendingCommitBar: some View {
        HStack(spacing: 12) {
            Label(
                store.snapshot.stage == .preview ? "知识变更待提交" : "正在检查知识变更",
                systemImage: store.snapshot.stage == .preview ? "tray.and.arrow.down" : "checkmark.shield"
            )
            .font(.callout.weight(.medium))
            Spacer()
            if store.isWorking { ProgressView().controlSize(.small) }
            Button(store.errorMessage == nil ? "提交知识变更" : "重试提交") {
                Task { await store.finalizePublication() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(store.isWorking || !store.snapshot.validationIssues.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var conflict: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("知识库在生成期间发生了变化。请重新检索受影响知识并 rebase，避免覆盖远端历史。", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.orange)
            actionBar {
                Spacer()
                Button("重新检索并继续") { store.resume() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
    }

    private var completed: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("知识已成功提交", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(.green)
            Button("浏览修订历史") { Task { await store.loadHistory() } }
            ForEach(store.history) { revision in
                VStack(alignment: .leading, spacing: 3) {
                    Text(revision.title ?? revision.identityID)
                        .fontWeight(.medium)
                    Text("\(revision.layer.rawValue) · revision \(revision.revisionNumber)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(revision.text)
                        .lineLimit(3)
                }
            }
            actionBar {
                Spacer()
                Button("创建新的发布") {
                    store.reset()
                    draft = .init()
                }
                .controlSize(.large)
            }
        }
    }

    private var cancelled: some View {
        actionBar {
            Label("发布已取消；未提交的 Run 可由后端 abandon。", systemImage: "xmark.circle")
            Spacer()
            Button("重新开始") {
                store.reset()
                draft = .init()
            }
            .controlSize(.large)
        }
    }

    private var publicationFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                if let id = store.snapshot.knowledgeBaseID {
                    Label(id, systemImage: "number")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help("知识库 ID：\(id)")
                }
                Label(publicationStatusLabel, systemImage: publicationStatusIcon)
                Label("治理版本 \(store.currentGovernanceVersion)", systemImage: "shield")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if store.snapshot.knowledgeBaseID != nil {
                HStack(spacing: 10) {
                    Toggle("", isOn: $creatorTermsAccepted)
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .accessibilityLabel("我已阅读并同意知识库发布协议")
                    Text("我已阅读并同意")
                        .font(.callout)
                    Button("《知识库发布协议》") {
                        isPresentingPublishingAgreement = true
                    }
                    .buttonStyle(.link)
                    Spacer()
                    Button("下架") { Task { await store.unpublishKnowledgeBase() } }
                        .disabled(store.currentPublicationStatusLabel != "published")
                    Button("即时发布") {
                        Task {
                            if let id = await store.publishKnowledgeBase(termsAccepted: creatorTermsAccepted) {
                                onPublished?(id)
                            }
                        }
                    }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canPublish)
                }
            } else {
                Button("查看《知识库发布协议》") {
                    isPresentingPublishingAgreement = true
                }
                .buttonStyle(.link)
            }

            if store.currentEnforcementStatusLabel == "taken_down" {
                HStack {
                    TextField("请说明申诉理由", text: $appealStatement)
                    Button("提交申诉") {
                        Task { await store.appealKnowledgeBase(statement: appealStatement) }
                    }
                    .disabled(
                        appealStatement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || store.snapshot.latestKnowledgeBaseDetail?.latestTakedownActionID == nil
                            || store.snapshot.latestKnowledgeBaseDetail?.appealCount ?? 0 > 0
                    )
                }
            }

            if let error = store.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var publishingAgreement: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(CloudKnowledgePublishingAgreement.title)
                        .font(.title2.bold())
                    Text("版本 \(CloudKnowledgePublishingAgreement.version) · \(CloudKnowledgePublishingAgreement.effectiveDate)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    isPresentingPublishingAgreement = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .help("关闭")
                .accessibilityLabel("关闭发布协议")
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label(CloudKnowledgePublishingAgreement.operatorName, systemImage: "building.2")
                        .font(.headline)

                    ForEach(CloudKnowledgePublishingAgreement.sections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.title)
                                .font(.headline)
                            Text(section.body)
                                .font(.body)
                                .lineSpacing(5)
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }

            Divider()

            HStack {
                Text("发布时将记录本协议版本。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("同意并关闭") {
                    creatorTermsAccepted = true
                    isPresentingPublishingAgreement = false
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(minWidth: 640, idealWidth: 720, minHeight: 560, idealHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func conversationSelection(for id: String) -> Binding<Bool> {
        Binding(
            get: { store.snapshot.selectedConversationIDs.contains(id) },
            set: { _ in store.toggleConversation(id) }
        )
    }

    private func actionBar<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            content()
        }
        .frame(maxWidth: .infinity)
    }

    private func summaryRow(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.body)
            .symbolRenderingMode(.hierarchical)
    }

    private var canPublish: Bool {
        creatorTermsAccepted
            && store.snapshot.latestKnowledgeBaseDetail?.visibility == "public"
            && !["deleting", "deleted"].contains(store.snapshot.latestKnowledgeBaseDetail?.lifecycleStatus ?? "")
            && store.currentEnforcementStatusLabel != "taken_down"
    }

    private var publicationStatusLabel: String {
        switch store.currentPublicationStatusLabel {
        case "published": "已发布"
        case "unpublished": "未发布"
        default: store.currentPublicationStatusLabel
        }
    }

    private var publicationStatusIcon: String {
        store.currentPublicationStatusLabel == "published" ? "checkmark.circle.fill" : "circle.dashed"
    }

    private var stageProgressLabel: String {
        let stages = CloudKnowledgeCreatorStage.allCases
        let current = stages.firstIndex(of: store.snapshot.stage).map { $0 + 1 } ?? 1
        return "步骤 \(current) / \(stages.count)"
    }

    private var stageTitle: String {
        switch store.snapshot.stage {
        case .configure: "创建或编辑知识库"
        case .conversations: "选择本地对话"
        case .confirm: "确认生成配置"
        case .generating: "正在生成知识"
        case .paused: "生成已暂停"
        case .validating: "正在检查并提交"
        case .preview: "变更预览"
        case .conflict: "并发冲突"
        case .completed: "发布完成"
        case .cancelled: "发布已取消"
        }
    }

    private var stageIcon: String {
        switch store.snapshot.stage {
        case .configure: "books.vertical"
        case .conversations: "text.bubble"
        case .confirm: "checkmark.circle"
        case .generating: "wand.and.stars"
        case .paused: "pause.circle"
        case .validating: "checkmark.shield"
        case .preview: "doc.text.magnifyingglass"
        case .conflict: "arrow.triangle.2.circlepath"
        case .completed: "checkmark.seal"
        case .cancelled: "xmark.circle"
        }
    }
}
