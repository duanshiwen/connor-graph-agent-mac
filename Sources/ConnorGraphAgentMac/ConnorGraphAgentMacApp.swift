import SwiftUI
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphSearch
import ConnorGraphAgent
import ConnorGraphStore
import ConnorGraphAppSupport

@main
struct ConnorGraphAgentMacApp: App {
    var body: some Scene {
        WindowGroup {
            AppShellView(viewModel: AppViewModel.live())
        }
    }
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case graphNodes = "图谱节点"
    case search = "搜索"
    case observeLog = "观察日志"
    case agentChat = "智能体聊天"
    case promotionQueue = "提升队列"
    case importKnowledge = "导入"
    case llmSettings = "模型设置"

    var id: String { rawValue }
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var selection: SidebarItem? = .agentChat
    @Published var query: String = "记忆"
    @Published var searchResults: [GraphSearchResult] = []
    @Published var chatInput: String = "记忆"
    @Published var transcript: [AgentMessage] = []
    @Published var lastContext: AgentContext?
    @Published var lastPromptInspection: AgentChatPromptInspection?
    @Published var errorMessage: String?
    @Published var nodes: [GraphNode]
    @Published var edges: [SemanticEdge]
    @Published var observeLogEntries: [ObserveLogEntry]
    @Published var importPath: String = "/Users/duanshiwen/notes/intelligence-repository"
    @Published var isImporting: Bool = false
    @Published var lastImportReport: AppImportReport?
    @Published var databasePath: String?
    @Published var promotionCandidates: [ObserveLogEntry] = []
    @Published var lastPromotionResultSummary: String?
    @Published var llmProviderMode: AppLLMProviderMode = .stub
    @Published var llmBaseURLString: String = AppLLMSettings.default.baseURLString
    @Published var llmModel: String = AppLLMSettings.default.model
    @Published var llmAPIKeyInput: String = ""
    @Published var llmHasAPIKey: Bool = false
    @Published var llmSettingsMessage: String?
    @Published var llmHealthCheckMessage: String?
    @Published var isTestingLLMConnection: Bool = false
    @Published var chatSessions: [AgentSession] = []
    @Published var selectedChatSessionID: String?
    @Published var latestChatSummary: AgentSessionSummary?
    @Published var isSummarizingChatSession: Bool = false
    @Published var chatSummaryMessage: String?
    @Published var isSubmittingChat: Bool = false

    private var repository: AppGraphRepository?
    private var promotionRepository: AppPromotionQueueRepository?
    private var chatSessionRepository: AppChatSessionRepository?
    private var llmSettingsRepository: AppLLMSettingsRepository
    private var llmProviderHealthChecker: AppLLMProviderHealthChecker
    private var searchIndex: InMemoryGraphSearchIndex
    private var chatController: AgentChatController<AnyLLMProvider>

    var latestChatSummaryFreshness: AgentSessionSummaryFreshness? {
        latestChatSummary?.freshness(for: chatController.agent.session)
    }

    var latestChatSummaryContextMessage: String {
        guard let freshness = latestChatSummaryFreshness else { return "" }
        if freshness.isFresh {
            return "会话摘要已是最新，将包含在下一次回答中。"
        }
        return "会话摘要已过期：还有 \(freshness.uncoveredMessageCount) 条消息未覆盖，因此不会包含在下一次回答中。"
    }

    var latestChatSummaryRefreshState: AgentSessionSummaryRefreshState {
        AgentSessionSummaryRefreshState(
            isSummarizing: isSummarizingChatSession,
            hasTranscriptMessages: !transcript.isEmpty,
            freshness: latestChatSummaryFreshness
        )
    }

    var summarizeChatSessionButtonTitle: String {
        latestChatSummaryRefreshState.buttonTitle
    }

    var canSummarizeSelectedChatSession: Bool {
        latestChatSummaryRefreshState.canSubmit
    }

    init(
        nodes: [GraphNode],
        edges: [SemanticEdge],
        observeLogEntries: [ObserveLogEntry],
        repository: AppGraphRepository? = nil,
        databasePath: String? = nil,
        llmSettingsRepository: AppLLMSettingsRepository = AppLLMSettingsRepository()
    ) {
        self.nodes = nodes
        self.edges = edges
        self.observeLogEntries = observeLogEntries
        self.repository = repository
        if let repository {
            self.promotionRepository = AppPromotionQueueRepository(store: repository.store)
            self.chatSessionRepository = AppChatSessionRepository(store: repository.store)
        }
        self.llmSettingsRepository = llmSettingsRepository
        self.llmProviderHealthChecker = AppLLMProviderHealthChecker(settingsRepository: llmSettingsRepository)
        self.databasePath = databasePath
        self.searchIndex = InMemoryGraphSearchIndex(nodes: nodes, edges: edges, observeLogEntries: observeLogEntries)
        self.chatController = Self.makeChatController(searchIndex: searchIndex, settingsRepository: llmSettingsRepository)
        self.searchResults = (try? searchIndex.search(query: query, options: .init(includeNeighborhood: true))) ?? []
        loadLLMSettings()
        reloadChatSessions()
    }

    static func live() -> AppViewModel {
        do {
            let paths = try AppStoragePaths.live()
            let repository = try AppGraphRepository.bootstrap(paths: paths)
            var snapshot = try repository.loadSnapshot()
            if snapshot.nodes.isEmpty {
                let demo = demoSnapshot()
                for node in demo.nodes { try repository.store.upsert(node: node) }
                for edge in demo.edges { try repository.store.upsert(edge: edge) }
                for entry in demo.observeLogEntries { try repository.store.upsert(observeLogEntry: entry) }
                snapshot = try repository.loadSnapshot()
            }
            let viewModel = AppViewModel(
                nodes: snapshot.nodes,
                edges: snapshot.edges,
                observeLogEntries: snapshot.observeLogEntries,
                repository: repository,
                databasePath: paths.databaseURL.path
            )
            viewModel.reloadPromotionCandidates()
            return viewModel
        } catch {
            let viewModel = AppViewModel.demo()
            viewModel.errorMessage = "已回退到演示数据：\(error)"
            return viewModel
        }
    }

    static func demo() -> AppViewModel {
        let snapshot = demoSnapshot()
        return AppViewModel(nodes: snapshot.nodes, edges: snapshot.edges, observeLogEntries: snapshot.observeLogEntries)
    }

    private static func demoSnapshot() -> GraphStoreSnapshot {
        let workObject = GraphNode.workObject(
            id: "work-object-agent-os",
            title: "Agent OS",
            summary: "A local-first operating system for graph-backed agents."
        )
        let question = GraphNode.question(
            id: "question-memory",
            title: "How should memory work?",
            summary: "Agent memory should be grounded in graph context."
        )
        let answer = GraphNode.answer(
            id: "answer-graph-memory",
            title: "Use graph-backed context",
            summary: "Use a local graph store as the runtime knowledge source of truth."
        )
        let edge = SemanticEdge.answeredBy(questionID: question.id, answerID: answer.id)
        let observe = ObserveLogEntry(
            id: "observe-demo",
            kind: .insight,
            source: .agent,
            content: "Recent insight: Markdown is only a legacy import source; graph store is the runtime knowledge layer.",
            normalizedSummary: "Graph store is runtime knowledge source of truth",
            workObjectID: workObject.id
        )
        return GraphStoreSnapshot(nodes: [workObject, question, answer], edges: [edge], observeLogEntries: [observe])
    }

    private static func makeChatController(
        searchIndex: InMemoryGraphSearchIndex,
        settingsRepository: AppLLMSettingsRepository,
        session: AgentSession = AgentSession(id: "app-session")
    ) -> AgentChatController<AnyLLMProvider> {
        let provider = Self.makeLLMProvider(settingsRepository: settingsRepository)
        return AgentChatController(
            agent: GraphAgent(
                session: session,
                contextBuilder: AgentContextBuilder(searchIndex: searchIndex, assembler: ContextAssembler()),
                llmProvider: provider
            )
        )
    }

    private static func makeLLMProvider(settingsRepository: AppLLMSettingsRepository) -> AnyLLMProvider {
        do {
            let settings = try settingsRepository.loadSettings()
            switch settings.providerMode {
            case .stub:
                return AnyLLMProvider(StubLLMProvider())
            case .openAICompatible:
                guard let config = try settingsRepository.openAICompatibleConfig() else {
                    return AnyLLMProvider { _, _ in
                        throw OpenAICompatibleProviderError.missingAPIKey
                    }
                }
                return AnyLLMProvider(OpenAICompatibleProvider(config: config))
            }
        } catch {
            return AnyLLMProvider { _, _ in throw error }
        }
    }

    private func apply(snapshot: GraphStoreSnapshot) {
        nodes = snapshot.nodes
        edges = snapshot.edges
        observeLogEntries = snapshot.observeLogEntries
        searchIndex = InMemoryGraphSearchIndex(nodes: snapshot.nodes, edges: snapshot.edges, observeLogEntries: snapshot.observeLogEntries)
        chatController = Self.makeChatController(searchIndex: searchIndex, settingsRepository: llmSettingsRepository, session: chatController.agent.session)
        runSearch()
        reloadPromotionCandidates()
    }

    func loadLLMSettings() {
        do {
            let settings = try llmSettingsRepository.loadSettings()
            llmProviderMode = settings.providerMode
            llmBaseURLString = settings.baseURLString
            llmModel = settings.model
            llmHasAPIKey = settings.hasAPIKey
            llmAPIKeyInput = ""
            llmSettingsMessage = nil
            llmHealthCheckMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func saveLLMSettings() {
        do {
            let settings = AppLLMSettings(
                baseURLString: llmBaseURLString.trimmingCharacters(in: .whitespacesAndNewlines),
                model: llmModel.trimmingCharacters(in: .whitespacesAndNewlines),
                hasAPIKey: llmHasAPIKey,
                providerMode: llmProviderMode
            )
            let apiKey = llmAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
            try llmSettingsRepository.save(settings: settings, apiKey: apiKey.isEmpty ? nil : apiKey)
            loadLLMSettings()
            chatController = Self.makeChatController(searchIndex: searchIndex, settingsRepository: llmSettingsRepository, session: chatController.agent.session)
            llmSettingsMessage = "模型设置已保存。"
            llmHealthCheckMessage = nil
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func clearLLMAPIKey() {
        do {
            try llmSettingsRepository.clearAPIKey()
            loadLLMSettings()
            chatController = Self.makeChatController(searchIndex: searchIndex, settingsRepository: llmSettingsRepository, session: chatController.agent.session)
            llmSettingsMessage = "API Key 已清除。"
            llmHealthCheckMessage = nil
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func testLLMConnection() async {
        isTestingLLMConnection = true
        defer { isTestingLLMConnection = false }
        llmHealthCheckMessage = nil
        let result = await llmProviderHealthChecker.testConnection()
        llmHealthCheckMessage = result.message
        switch result.status {
        case .success:
            errorMessage = nil
        case .notConfigured, .failed:
            errorMessage = result.message
        }
    }

    func reloadChatSessions() {
        guard let chatSessionRepository else {
            transcript = chatController.transcript
            selectedChatSessionID = chatController.agent.session.id
            return
        }
        do {
            var sessions = try chatSessionRepository.loadRecentSessions()
            if sessions.isEmpty {
                let session = try chatSessionRepository.createSession()
                sessions = [session]
            }
            chatSessions = sessions
            let selectedID = selectedChatSessionID ?? sessions.first?.id
            selectedChatSessionID = selectedID
            if let selectedID, let session = try chatSessionRepository.loadSession(id: selectedID) {
                chatController = Self.makeChatController(searchIndex: searchIndex, settingsRepository: llmSettingsRepository, session: session)
                transcript = session.messages
                latestChatSummary = try chatSessionRepository.loadLatestSummary(sessionID: selectedID)
            } else {
                latestChatSummary = nil
            }
            chatSummaryMessage = nil
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func newChatSession() {
        guard let chatSessionRepository else { return }
        do {
            let session = try chatSessionRepository.createSession()
            selectedChatSessionID = session.id
            chatController = Self.makeChatController(searchIndex: searchIndex, settingsRepository: llmSettingsRepository, session: session)
            transcript = []
            latestChatSummary = nil
            chatSummaryMessage = nil
            lastPromptInspection = nil
            reloadChatSessions()
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func selectChatSession(_ sessionID: String) {
        guard let chatSessionRepository else { return }
        do {
            guard let session = try chatSessionRepository.loadSession(id: sessionID) else { return }
            selectedChatSessionID = session.id
            chatController = Self.makeChatController(searchIndex: searchIndex, settingsRepository: llmSettingsRepository, session: session)
            transcript = session.messages
            latestChatSummary = try chatSessionRepository.loadLatestSummary(sessionID: session.id)
            chatSummaryMessage = nil
            lastContext = nil
            lastPromptInspection = nil
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func reloadPromotionCandidates() {
        do {
            promotionCandidates = try promotionRepository?.loadCandidates() ?? []
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func promote(_ entry: ObserveLogEntry) {
        guard let promotionRepository, let repository else {
            errorMessage = "提升队列不可用。"
            return
        }
        do {
            let result = try promotionRepository.promote(entry)
            let snapshot = try repository.loadSnapshot()
            lastPromotionResultSummary = "已提升 \(entry.id)：\(result.nodes.count) 个节点，\(result.edges.count) 条关系"
            apply(snapshot: snapshot)
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func dismissPromotionCandidate(_ entry: ObserveLogEntry) {
        do {
            _ = try promotionRepository?.dismiss(entry)
            reloadPromotionCandidates()
            lastPromotionResultSummary = "已忽略 \(entry.id)"
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func pinPromotionCandidate(_ entry: ObserveLogEntry) {
        do {
            _ = try promotionRepository?.pin(entry)
            reloadPromotionCandidates()
            lastPromotionResultSummary = "已置顶 \(entry.id) 30 天"
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func runSearch() {
        do {
            searchResults = try searchIndex.search(query: query, options: .init(includeNeighborhood: true))
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func importReadOnlyKnowledge() async {
        guard let repository else {
            errorMessage = "SQLite 仓库不可用。"
            return
        }
        let trimmedPath = importPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return }
        isImporting = true
        defer { isImporting = false }
        do {
            let directory = URL(fileURLWithPath: trimmedPath, isDirectory: true)
            let report = try await Task.detached(priority: .userInitiated) {
                try repository.importReadOnlyKnowledge(from: directory)
            }.value
            let snapshot = try repository.loadSnapshot()
            lastImportReport = report
            apply(snapshot: snapshot)
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func submitChat() async {
        let prompt = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isSubmittingChat else { return }
        chatInput = ""
        isSubmittingChat = true
        let optimisticTranscript = transcript
        let optimisticUserMessage = AgentMessage(role: .user, content: prompt)
        transcript = optimisticTranscript + [optimisticUserMessage]
        lastContext = nil
        lastPromptInspection = nil
        defer { isSubmittingChat = false }
        do {
            var controller = chatController
            let previousMessageCount = controller.transcript.count
            let sessionSummary: AgentSessionSummary?
            if let chatSessionRepository, let selectedChatSessionID {
                let candidateSummary = try chatSessionRepository.loadLatestSummary(sessionID: selectedChatSessionID)
                sessionSummary = AgentSessionSummaryPolicy().summaryForContext(candidateSummary, session: controller.agent.session)
            } else {
                sessionSummary = nil
            }
            let response = try await controller.submit(prompt, sessionSummary: sessionSummary)
            if let chatSessionRepository {
                _ = try chatSessionRepository.saveTurn(previousMessageCount: previousMessageCount, response: response)
            }
            chatController = controller
            transcript = controller.transcript
            selectedChatSessionID = response.session.id
            if chatSessionRepository != nil { reloadChatSessions() }
            lastContext = response.context
            lastPromptInspection = response.promptInspection
            errorMessage = nil
        } catch {
            transcript = optimisticTranscript + [optimisticUserMessage]
            errorMessage = String(describing: error)
        }
    }

    func summarizeSelectedChatSession() async {
        guard let selectedChatSessionID, let chatSessionRepository else { return }
        isSummarizingChatSession = true
        defer { isSummarizingChatSession = false }
        do {
            let provider = Self.makeLLMProvider(settingsRepository: llmSettingsRepository)
            let summarizer = AgentSessionSummarizer(provider: provider)
            let summary = try await chatSessionRepository.summarizeSession(id: selectedChatSessionID, using: summarizer)
            latestChatSummary = summary
            chatSummaryMessage = latestChatSummaryRefreshState.successMessage
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }
}

struct AppShellView: View {
    @StateObject var viewModel: AppViewModel

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $viewModel.selection) { item in
                Text(item.rawValue).tag(item)
            }
            .navigationTitle("Connor")
        } detail: {
            Group {
                switch viewModel.selection ?? .agentChat {
                case .graphNodes:
                    GraphNodesView(nodes: viewModel.nodes, edges: viewModel.edges)
                case .search:
                    SearchView(viewModel: viewModel)
                case .observeLog:
                    ObserveLogView(entries: viewModel.observeLogEntries)
                case .agentChat:
                    AgentChatView(viewModel: viewModel)
                case .promotionQueue:
                    PromotionQueueView(viewModel: viewModel)
                case .importKnowledge:
                    ImportKnowledgeView(viewModel: viewModel)
                case .llmSettings:
                    LLMSettingsView(viewModel: viewModel)
                }
            }
            .frame(minWidth: 720, minHeight: 480)
        }
    }
}

struct GraphNodesView: View {
    let nodes: [GraphNode]
    let edges: [SemanticEdge]

    var body: some View {
        List {
            Section("节点") {
                ForEach(nodes) { node in
                    VStack(alignment: .leading) {
                        Text(node.title).font(.headline)
                        Text(node.type.rawValue).font(.caption).foregroundStyle(.secondary)
                        if !node.summary.isEmpty { Text(node.summary).font(.subheadline) }
                    }
                }
            }
            Section("关系") {
                ForEach(edges) { edge in
                    VStack(alignment: .leading) {
                        Text(edge.relation.rawValue).font(.headline)
                        Text("\(edge.sourceNodeID) → \(edge.targetNodeID)").font(.caption).foregroundStyle(.secondary)
                        Text(edge.fact).font(.subheadline)
                    }
                }
            }
        }
        .navigationTitle("图谱节点")
    }
}

struct SearchView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("搜索图谱和观察日志", text: $viewModel.query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { viewModel.runSearch() }
                Button("搜索") { viewModel.runSearch() }
            }
            List(viewModel.searchResults) { result in
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.id).font(.headline)
                    Text(result.kind.rawValue).font(.caption).foregroundStyle(.secondary)
                    Text(result.reason).font(.subheadline)
                }
            }
        }
        .padding()
        .navigationTitle("搜索")
    }
}

struct ObserveLogView: View {
    let entries: [ObserveLogEntry]

    var body: some View {
        List(entries) { entry in
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.content).font(.headline)
                Text("\(entry.kind.rawValue) · \(entry.status.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("过期时间：\(entry.expiresAt.formatted())")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("观察日志")
    }
}

struct PromotionQueueView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("刷新") { viewModel.reloadPromotionCandidates() }
                if let summary = viewModel.lastPromotionResultSummary {
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
            }

            if viewModel.promotionCandidates.isEmpty {
                Text("暂无可提升候选项。")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(viewModel.promotionCandidates) { entry in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(entry.kind.rawValue).font(.headline)
                            Spacer()
                            Text(entry.status.rawValue).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(entry.content)
                        if !entry.normalizedSummary.isEmpty {
                            Text(entry.normalizedSummary).font(.subheadline).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 12) {
                            if let workObjectID = entry.workObjectID {
                                Text("工作对象：\(workObjectID)")
                            }
                            Text("重要性：\(entry.importance, format: .number.precision(.fractionLength(2)))")
                            Text("置信度：\(entry.confidence, format: .number.precision(.fractionLength(2)))")
                            Text("过期时间：\(entry.expiresAt.formatted())")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        HStack {
                            Button("提升") { viewModel.promote(entry) }
                            Button("忽略") { viewModel.dismissPromotionCandidate(entry) }
                            Button("置顶 30 天") { viewModel.pinPromotionCandidate(entry) }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }

            if let error = viewModel.errorMessage {
                Text(error).foregroundStyle(.red)
            }
        }
        .padding()
        .navigationTitle("提升队列")
        .onAppear { viewModel.reloadPromotionCandidates() }
    }
}

struct LLMSettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Form {
            Picker("模型提供方", selection: $viewModel.llmProviderMode) {
                Text("模拟模式").tag(AppLLMProviderMode.stub)
                Text("OpenAI 兼容").tag(AppLLMProviderMode.openAICompatible)
            }
            .pickerStyle(.segmented)

            TextField("Base URL", text: $viewModel.llmBaseURLString)
                .textFieldStyle(.roundedBorder)
            TextField("模型", text: $viewModel.llmModel)
                .textFieldStyle(.roundedBorder)
            SecureField("API Key", text: $viewModel.llmAPIKeyInput)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("保存设置") { viewModel.saveLLMSettings() }
                Button("清除 API Key") { viewModel.clearLLMAPIKey() }
                Button("重新加载") { viewModel.loadLLMSettings() }
                Button(viewModel.isTestingLLMConnection ? "测试中…" : "测试连接") {
                    Task { await viewModel.testLLMConnection() }
                }
                .disabled(viewModel.isTestingLLMConnection)
            }

            Text(viewModel.llmHasAPIKey ? "API Key：已存入钥匙串" : "API Key：尚未保存")
                .foregroundStyle(viewModel.llmHasAPIKey ? .green : .secondary)

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Label("安全提示：API Key 会保存到 macOS 钥匙串", systemImage: "lock.shield")
                        .font(.caption.weight(.semibold))
                    Text("为保证安全，Connor Graph Agent 会将 API Key 存入 macOS 钥匙串，而不是以明文写入应用设置或项目文件。")
                    Text("当 macOS 请求钥匙串访问权限时，请为当前已签名的应用构建选择“始终允许”，以避免重复弹窗。")
                    Text("如果每次 Xcode 重新构建后仍然弹窗，请打开 app target 的 Signing & Capabilities，并确认 Team 设置为 诗闻 段 (Personal Team)。")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let message = viewModel.llmSettingsMessage {
                Text(message).foregroundStyle(.secondary)
            }
            if let message = viewModel.llmHealthCheckMessage {
                Text(message).foregroundStyle(message.contains("OK") || message.contains("available") ? .green : .secondary)
            }
            if let error = viewModel.errorMessage {
                Text(error).foregroundStyle(.red)
            }
        }
        .padding()
        .navigationTitle("模型设置")
    }
}

struct ImportKnowledgeView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let databasePath = viewModel.databasePath {
                Text("数据库：\(databasePath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            TextField("知识库路径", text: $viewModel.importPath)
                .textFieldStyle(.roundedBorder)
            Button(viewModel.isImporting ? "导入中…" : "只读导入") {
                Task { await viewModel.importReadOnlyKnowledge() }
            }
            .disabled(viewModel.isImporting || viewModel.importPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let report = viewModel.lastImportReport {
                Section("最近一次导入报告") {
                    Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                        GridRow { Text("扫描文件数"); Text("\(report.scannedFiles)") }
                        GridRow { Text("导入节点数"); Text("\(report.importedNodes)") }
                        GridRow { Text("导入关系数"); Text("\(report.importedEdges)") }
                        GridRow { Text("跳过文件数"); Text("\(report.skippedFiles)") }
                        GridRow { Text("警告数"); Text("\(report.warnings.count)") }
                    }
                    .font(.subheadline)
                }

                if !report.warnings.isEmpty {
                    List(report.warnings.prefix(20)) { warning in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(warning.path).font(.caption).foregroundStyle(.secondary)
                            Text(warning.message).font(.subheadline)
                        }
                    }
                } else {
                    Spacer()
                }
            } else {
                Text("导入会以只读方式扫描 Markdown，并将图谱节点和关系写入本地 SQLite 存储。")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding()
        .navigationTitle("导入")
    }
}
