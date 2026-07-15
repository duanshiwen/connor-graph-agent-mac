import SwiftUI
import ConnorGraphCore
import ConnorGraphAppSupport

struct CloudKnowledgeCreatorView: View {
    @ObservedObject var store: CloudKnowledgeCreatorStore
    var sessions: [AgentSession]
    @State private var draft = CloudKnowledgeBaseDraft()
    @State private var appealStatement = ""
    @State private var creatorTermsAccepted = false

    var body: some View {
        SettingsGroup(title: "云端知识库创建者") {
            VStack(alignment: .leading, spacing: 14) {
                stageHeader
                switch store.snapshot.stage {
                case .configure: configure
                case .conversations: conversations
                case .confirm: confirmation
                case .generating, .paused: progress
                case .validating: validation
                case .preview: preview
                case .conflict: conflict
                case .completed: completed
                case .cancelled: cancelled
                }
                if let id = store.snapshot.knowledgeBaseID { Text("知识库 ID: \(id)") }
                Text("publication_status: \(store.currentPublicationStatusLabel)")
                Text("enforcement_status: \(store.currentEnforcementStatusLabel)")
                Text("governance_version: \(store.currentGovernanceVersion)")
                Toggle("我已阅读并同意创作者发布条款（版本 \(cloudKnowledgeCreatorTermsVersion)）", isOn: $creatorTermsAccepted)
                HStack {
                    Button("即时发布") { Task { await store.publishKnowledgeBase(termsAccepted: creatorTermsAccepted) } }
                        .disabled(!creatorTermsAccepted || store.snapshot.knowledgeBaseID == nil || store.snapshot.latestKnowledgeBaseDetail?.visibility != "public" || ["deleting", "deleted"].contains(store.snapshot.latestKnowledgeBaseDetail?.lifecycleStatus ?? "") || store.currentEnforcementStatusLabel == "taken_down")
                    Button("下架") { Task { await store.unpublishKnowledgeBase() } }
                        .disabled(store.snapshot.knowledgeBaseID == nil || store.currentPublicationStatusLabel != "published")
                }
                if store.currentEnforcementStatusLabel == "taken_down" {
                    HStack {
                        TextField("请说明申诉理由", text: $appealStatement)
                        Button("提交申诉") { Task { await store.appealKnowledgeBase(statement: appealStatement) } }
                            .disabled(appealStatement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.snapshot.latestKnowledgeBaseDetail?.latestTakedownActionID == nil || store.snapshot.latestKnowledgeBaseDetail?.appealCount ?? 0 > 0)
                    }
                }
                if let error = store.errorMessage { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.caption) }
            }
            .onAppear { draft = store.snapshot.draft; Task { await store.refreshLatestKnowledgeBaseDetail() } }
        }
    }

    private var stageHeader: some View {
        HStack { Label(stageTitle, systemImage: stageIcon).font(.headline); Spacer(); if store.isWorking { ProgressView().controlSize(.small) } }
    }
    private var configure: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("知识库名称", text: $draft.name); TextField("Slug", text: $draft.slug); TextField("描述", text: $draft.description, axis: .vertical).lineLimit(2...5)
            Picker("可见性", selection: $draft.visibility) { Text("私有").tag("private"); Text("不公开列出").tag("unlisted"); Text("公开").tag("public") }.pickerStyle(.segmented)
            HStack { Spacer(); Button("保存并选择对话") { store.updateDraft(draft); Task { await store.saveKnowledgeBase() } }.buttonStyle(.borderedProminent).disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }
    }
    private var conversations: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("原始对话会发送给当前配置的 LLM 提供商进行分析，但不会上传到康纳知识后端；后端只接收生成后的结构化知识操作。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("管理员下架 / 删除中 / 已删除将阻止继续发布；被下架后可提交一次开放申诉。")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(sessions.prefix(100)) { session in Toggle(isOn: Binding(get: { store.snapshot.selectedConversationIDs.contains(session.id) }, set: { _ in store.toggleConversation(session.id) })) { VStack(alignment: .leading) { Text(session.title); Text("\(session.messages.count) 条消息").font(.caption).foregroundStyle(.secondary) } } }
            HStack { Button("返回") { store.advance(to: .configure) }; Spacer(); Button("下一步：确认生成") { store.advance(to: .confirm) }.buttonStyle(.borderedProminent).disabled(store.snapshot.selectedConversationIDs.isEmpty) }
        }
    }
    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("将从 \(store.snapshot.selectedConversationIDs.count) 个本地对话生成结构化 L2/L3/L4 知识操作", systemImage: "wand.and.stars")
            Label("每组写入都会先检索 committed + staged 知识", systemImage: "magnifyingglass")
            Label("即时发布，无需人工审核", systemImage: "bolt.fill")
            Label("提交前可查看完整变更预览", systemImage: "checkmark.rectangle")
            HStack { Button("返回") { store.advance(to: .conversations) }; Spacer(); Button("确认并开始") { Task { await store.beginPublication() } }.buttonStyle(.borderedProminent) }
        }
    }
    private var progress: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressView(value: Double(store.snapshot.processedConversationIDs.count), total: Double(max(1, store.snapshot.selectedConversationIDs.count)))
            Text("已处理 \(store.snapshot.processedConversationIDs.count) / \(store.snapshot.selectedConversationIDs.count) 个对话").font(.caption).foregroundStyle(.secondary)
            ForEach(Array(store.snapshot.summaries.enumerated()), id: \.offset) { _, summary in Label(summary, systemImage: "checkmark.circle") }
            HStack { Button(store.snapshot.stage == .paused ? "恢复" : "暂停") { store.snapshot.stage == .paused ? store.resume() : store.pause() }; Button("取消", role: .destructive) { store.cancel() }; Spacer(); Button("验证发布") { Task { await store.validatePublication() } }.disabled(store.snapshot.processedConversationIDs.count < store.snapshot.selectedConversationIDs.count) }
        }
    }
    private var validation: some View { VStack(alignment: .leading, spacing: 8) { if store.snapshot.validationIssues.isEmpty { Label("等待 Publication Run 验证", systemImage: "checkmark.shield") } else { ForEach(store.snapshot.validationIssues) { issue in Label(issue.message, systemImage: issue.repairable ? "wrench.and.screwdriver" : "exclamationmark.octagon").foregroundStyle(issue.repairable ? .orange : .red) } }; HStack { Spacer(); Button("加载变更预览") { Task { await store.loadPreview() } }.buttonStyle(.borderedProminent) } } }
    private var preview: some View { VStack(alignment: .leading, spacing: 8) { Text("提交前预览").font(.headline); Text("selected \(store.snapshot.selectedConversationIDs.count) · processed \(store.snapshot.processedConversationIDs.count) · operations \(store.snapshot.preview?.operations.count ?? 0)").font(.caption).foregroundStyle(.secondary); ForEach(store.snapshot.preview?.summaries ?? store.snapshot.summaries, id: \.self) { Label($0, systemImage: "doc.text.magnifyingglass") }; ForEach(store.snapshot.preview?.operations ?? []) { operation in VStack(alignment: .leading) { Text("\(operation.layer.rawValue) · \(operation.operationType) · \(operation.decision.rawValue)").fontWeight(.medium); Text(operation.semanticTerms.joined(separator: "、")).font(.caption).foregroundStyle(.secondary) } }; HStack { Button("返回修复") { store.advance(to: .validating) }; Spacer(); Button("确认并提交全部变更") { Task { await store.commitPublication() } }.buttonStyle(.borderedProminent) } } }
    private var conflict: some View { VStack(alignment: .leading) { Label("知识库在生成期间发生了变化。需要重新检索受影响知识并 rebase，不能覆盖远端历史。", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.orange); HStack { Spacer(); Button("重新检索并继续") { store.resume() }.buttonStyle(.borderedProminent) } } }
    private var completed: some View { VStack(alignment: .leading, spacing: 8) { Label("知识已成功提交", systemImage: "checkmark.seal.fill").foregroundStyle(.green); Button("浏览修订历史") { Task { await store.loadHistory() } }; ForEach(store.history) { revision in VStack(alignment: .leading) { Text(revision.title ?? revision.identityID).fontWeight(.medium); Text("\(revision.layer.rawValue) · revision \(revision.revisionNumber)").font(.caption).foregroundStyle(.secondary); Text(revision.text).lineLimit(3) } }; HStack { Spacer(); Button("创建新的发布") { store.reset(); draft = .init() } } } }
    private var cancelled: some View { HStack { Label("发布已取消；未提交的 Run 可由后端 abandon。", systemImage: "xmark.circle"); Spacer(); Button("重新开始") { store.reset(); draft = .init() } } }
    private var stageTitle: String { switch store.snapshot.stage { case .configure: "创建或编辑知识库"; case .conversations: "选择本地对话"; case .confirm: "确认生成配置"; case .generating: "正在生成知识"; case .paused: "生成已暂停"; case .validating: "验证与修复"; case .preview: "变更预览"; case .conflict: "并发冲突"; case .completed: "发布完成"; case .cancelled: "发布已取消" } }
    private var stageIcon: String { switch store.snapshot.stage { case .configure: "books.vertical"; case .conversations: "text.bubble"; case .confirm: "checkmark.circle"; case .generating: "wand.and.stars"; case .paused: "pause.circle"; case .validating: "checkmark.shield"; case .preview: "doc.text.magnifyingglass"; case .conflict: "arrow.triangle.2.circlepath"; case .completed: "checkmark.seal"; case .cancelled: "xmark.circle" } }
}
