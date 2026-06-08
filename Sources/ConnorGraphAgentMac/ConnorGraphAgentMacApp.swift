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
    case importKnowledge = "Import"

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

    private var repository: AppGraphRepository?
    private var searchIndex: InMemoryGraphSearchIndex
    private var chatController: AgentChatController<StubLLMProvider>

    init(nodes: [GraphNode], edges: [SemanticEdge], observeLogEntries: [ObserveLogEntry], repository: AppGraphRepository? = nil, databasePath: String? = nil) {
        self.nodes = nodes
        self.edges = edges
        self.observeLogEntries = observeLogEntries
        self.repository = repository
        self.databasePath = databasePath
        self.searchIndex = InMemoryGraphSearchIndex(nodes: nodes, edges: edges, observeLogEntries: observeLogEntries)
        self.chatController = Self.makeChatController(searchIndex: searchIndex)
        self.searchResults = (try? searchIndex.search(query: query, options: .init(includeNeighborhood: true))) ?? []
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
            return AppViewModel(
                nodes: snapshot.nodes,
                edges: snapshot.edges,
                observeLogEntries: snapshot.observeLogEntries,
                repository: repository,
                databasePath: paths.databaseURL.path
            )
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

    private static func makeChatController(searchIndex: InMemoryGraphSearchIndex) -> AgentChatController<StubLLMProvider> {
        AgentChatController(
            agent: GraphAgent(
                session: AgentSession(id: "app-session"),
                contextBuilder: AgentContextBuilder(searchIndex: searchIndex, assembler: ContextAssembler()),
                llmProvider: StubLLMProvider()
            )
        )
    }

    private func apply(snapshot: GraphStoreSnapshot) {
        nodes = snapshot.nodes
        edges = snapshot.edges
        observeLogEntries = snapshot.observeLogEntries
        searchIndex = InMemoryGraphSearchIndex(nodes: snapshot.nodes, edges: snapshot.edges, observeLogEntries: snapshot.observeLogEntries)
        chatController = Self.makeChatController(searchIndex: searchIndex)
        runSearch()
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
            let response = try await controller.submit(prompt)
            chatController = controller
            transcript = controller.transcript
            lastContext = response.context
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
                case .importKnowledge:
                    ImportKnowledgeView(viewModel: viewModel)
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
    }
}
