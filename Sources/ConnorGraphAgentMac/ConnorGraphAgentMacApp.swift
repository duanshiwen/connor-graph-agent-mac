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
    case graphNodes = "Graph Nodes"
    case search = "Search"
    case observeLog = "Observe Log"
    case agentChat = "Agent Chat"
    case promotionQueue = "Promotion Queue"
    case importKnowledge = "Import"
    case llmSettings = "LLM Settings"

    var id: String { rawValue }
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var selection: SidebarItem? = .agentChat
    @Published var query: String = "memory"
    @Published var searchResults: [GraphSearchResult] = []
    @Published var chatInput: String = "memory"
    @Published var transcript: [AgentMessage] = []
    @Published var lastContext: AgentContext?
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

    private var repository: AppGraphRepository?
    private var promotionRepository: AppPromotionQueueRepository?
    private var chatSessionRepository: AppChatSessionRepository?
    private var llmSettingsRepository: AppLLMSettingsRepository
    private var llmProviderHealthChecker: AppLLMProviderHealthChecker
    private var searchIndex: InMemoryGraphSearchIndex
    private var chatController: AgentChatController<AnyLLMProvider>

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
            viewModel.errorMessage = "Fell back to demo data: \(error)"
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
            llmSettingsMessage = "LLM settings saved."
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
            llmSettingsMessage = "API key cleared."
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
            lastContext = nil
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
            errorMessage = "Promotion queue is not available."
            return
        }
        do {
            let result = try promotionRepository.promote(entry)
            let snapshot = try repository.loadSnapshot()
            lastPromotionResultSummary = "Promoted \(entry.id): \(result.nodes.count) nodes, \(result.edges.count) edges"
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
            lastPromotionResultSummary = "Dismissed \(entry.id)"
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func pinPromotionCandidate(_ entry: ObserveLogEntry) {
        do {
            _ = try promotionRepository?.pin(entry)
            reloadPromotionCandidates()
            lastPromotionResultSummary = "Pinned \(entry.id) for 30 days"
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
            errorMessage = "SQLite repository is not available."
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
        guard !prompt.isEmpty else { return }
        chatInput = ""
        do {
            var controller = chatController
            let previousMessageCount = controller.transcript.count
            let sessionSummary: AgentSessionSummary?
            if let chatSessionRepository, let selectedChatSessionID {
                sessionSummary = try chatSessionRepository.loadLatestSummary(sessionID: selectedChatSessionID)
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
            errorMessage = nil
        } catch {
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
            Section("Nodes") {
                ForEach(nodes) { node in
                    VStack(alignment: .leading) {
                        Text(node.title).font(.headline)
                        Text(node.type.rawValue).font(.caption).foregroundStyle(.secondary)
                        if !node.summary.isEmpty { Text(node.summary).font(.subheadline) }
                    }
                }
            }
            Section("Edges") {
                ForEach(edges) { edge in
                    VStack(alignment: .leading) {
                        Text(edge.relation.rawValue).font(.headline)
                        Text("\(edge.sourceNodeID) → \(edge.targetNodeID)").font(.caption).foregroundStyle(.secondary)
                        Text(edge.fact).font(.subheadline)
                    }
                }
            }
        }
        .navigationTitle("Graph Nodes")
    }
}

struct SearchView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Search graph and observe log", text: $viewModel.query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { viewModel.runSearch() }
                Button("Search") { viewModel.runSearch() }
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
        .navigationTitle("Search")
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
                Text("Expires: \(entry.expiresAt.formatted())")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Observe Log")
    }
}

struct PromotionQueueView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Refresh") { viewModel.reloadPromotionCandidates() }
                if let summary = viewModel.lastPromotionResultSummary {
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
            }

            if viewModel.promotionCandidates.isEmpty {
                Text("No active promotion candidates.")
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
                                Text("Work Object: \(workObjectID)")
                            }
                            Text("Importance: \(entry.importance, format: .number.precision(.fractionLength(2)))")
                            Text("Confidence: \(entry.confidence, format: .number.precision(.fractionLength(2)))")
                            Text("Expires: \(entry.expiresAt.formatted())")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        HStack {
                            Button("Promote") { viewModel.promote(entry) }
                            Button("Dismiss") { viewModel.dismissPromotionCandidate(entry) }
                            Button("Pin 30 days") { viewModel.pinPromotionCandidate(entry) }
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
        .navigationTitle("Promotion Queue")
        .onAppear { viewModel.reloadPromotionCandidates() }
    }
}

struct LLMSettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Form {
            Picker("Provider", selection: $viewModel.llmProviderMode) {
                Text("Stub").tag(AppLLMProviderMode.stub)
                Text("OpenAI Compatible").tag(AppLLMProviderMode.openAICompatible)
            }
            .pickerStyle(.segmented)

            TextField("Base URL", text: $viewModel.llmBaseURLString)
                .textFieldStyle(.roundedBorder)
            TextField("Model", text: $viewModel.llmModel)
                .textFieldStyle(.roundedBorder)
            SecureField("API Key", text: $viewModel.llmAPIKeyInput)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Save Settings") { viewModel.saveLLMSettings() }
                Button("Clear API Key") { viewModel.clearLLMAPIKey() }
                Button("Reload") { viewModel.loadLLMSettings() }
                Button(viewModel.isTestingLLMConnection ? "Testing…" : "Test Connection") {
                    Task { await viewModel.testLLMConnection() }
                }
                .disabled(viewModel.isTestingLLMConnection)
            }

            Text(viewModel.llmHasAPIKey ? "API key: stored in Keychain" : "API key: not stored")
                .foregroundStyle(viewModel.llmHasAPIKey ? .green : .secondary)

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
        .navigationTitle("LLM Settings")
    }
}

struct ImportKnowledgeView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let databasePath = viewModel.databasePath {
                Text("Database: \(databasePath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            TextField("Knowledge repository path", text: $viewModel.importPath)
                .textFieldStyle(.roundedBorder)
            Button(viewModel.isImporting ? "Importing…" : "Import Read-only") {
                Task { await viewModel.importReadOnlyKnowledge() }
            }
            .disabled(viewModel.isImporting || viewModel.importPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let report = viewModel.lastImportReport {
                Section("Last Import Report") {
                    Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                        GridRow { Text("Scanned files"); Text("\(report.scannedFiles)") }
                        GridRow { Text("Imported nodes"); Text("\(report.importedNodes)") }
                        GridRow { Text("Imported edges"); Text("\(report.importedEdges)") }
                        GridRow { Text("Skipped files"); Text("\(report.skippedFiles)") }
                        GridRow { Text("Warnings"); Text("\(report.warnings.count)") }
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
                Text("Import scans Markdown read-only and writes graph nodes/edges into the local SQLite store.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding()
        .navigationTitle("Import")
    }
}

struct AgentChatView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button("New Chat") { viewModel.newChatSession() }
                Picker("Session", selection: Binding(
                    get: { viewModel.selectedChatSessionID ?? "" },
                    set: { viewModel.selectChatSession($0) }
                )) {
                    ForEach(viewModel.chatSessions) { session in
                        Text(session.title).tag(session.id)
                    }
                }
                .frame(maxWidth: 320)
                Button("Reload") { viewModel.reloadChatSessions() }
                Button(viewModel.isSummarizingChatSession ? "Summarizing…" : "Summarize Session") {
                    Task { await viewModel.summarizeSelectedChatSession() }
                }
                .disabled(viewModel.isSummarizingChatSession || viewModel.transcript.isEmpty)
                Spacer()
            }

            if let summary = viewModel.latestChatSummary {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Latest Summary").font(.headline)
                    Text(summary.content).font(.subheadline)
                    Text("Covers \(summary.sourceMessageCount) messages · Updated \(summary.updatedAt.formatted())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Summary will be included in the next answer.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            }

            List {
                ForEach(viewModel.transcript) { message in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(message.role.rawValue.capitalized).font(.caption).foregroundStyle(.secondary)
                        Text(message.content)
                    }
                    .padding(.vertical, 4)
                }
                if let context = viewModel.lastContext {
                    Section("Cited Graph Context") {
                        ForEach(context.items) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.sourceID).font(.headline)
                                Text(item.content).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            HStack {
                TextField("Ask the graph-backed agent", text: $viewModel.chatInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await viewModel.submitChat() } }
                Button("Ask") { Task { await viewModel.submitChat() } }
            }
            if let error = viewModel.errorMessage {
                Text(error).foregroundStyle(.red)
            }
        }
        .padding()
        .navigationTitle("Agent Chat")
        .onAppear { viewModel.reloadChatSessions() }
    }
}
