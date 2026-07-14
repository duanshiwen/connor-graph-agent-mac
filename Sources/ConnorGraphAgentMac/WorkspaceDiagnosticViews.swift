import SwiftUI
import AppKit
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphSearch
import ConnorGraphAgent
import ConnorGraphStore
import ConnorGraphAppSupport
import Observation

@MainActor
@Observable
final class GraphDiagnosticsModel {
    var entities: [GraphEntity]
    var statements: [GraphStatement]
    var episodes: [GraphEpisodeV3]
    var observeLogEntries: [ObserveLogEntry]
    let databasePath: String?
    var query = "记忆"
    var searchResults: [GraphSearchHit] = []
    var schemaHealthReport: GraphSchemaHealthReport?
    var promotionCandidates: [ObserveLogEntry] = []
    var lastPromotionResultSummary: String?
    var errorMessage: String?

    @ObservationIgnored private let repository: AppGraphRepository?
    @ObservationIgnored private let promotionRepository: AppPromotionQueueRepository?
    @ObservationIgnored private let hybridSearchService: (any GraphHybridSearchService)?
    @ObservationIgnored var onPromotedSnapshot: ((GraphStoreSnapshot) -> Void)?

    init(
        entities: [GraphEntity],
        statements: [GraphStatement],
        episodes: [GraphEpisodeV3],
        observeLogEntries: [ObserveLogEntry],
        databasePath: String?,
        repository: AppGraphRepository?
    ) {
        self.entities = entities
        self.statements = statements
        self.episodes = episodes
        self.observeLogEntries = observeLogEntries
        self.databasePath = databasePath
        self.repository = repository
        self.promotionRepository = repository.map { AppPromotionQueueRepository(store: $0.store) }
        self.hybridSearchService = repository.map { SQLiteGraphHybridSearchService(store: $0.store) }
    }

    func apply(snapshot: GraphStoreSnapshot) {
        entities = snapshot.entities
        statements = snapshot.statements
        episodes = snapshot.episodes
        observeLogEntries = snapshot.observeLogEntries
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
            lastPromotionResultSummary = "已提升 \(entry.id)：\(result.entities.count) 个节点，\(result.statements.count) 条事实"
            apply(snapshot: snapshot)
            promotionCandidates = try promotionRepository.loadCandidates()
            onPromotedSnapshot?(snapshot)
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

    func reloadSchemaHealthReport() {
        do {
            schemaHealthReport = try repository?.store.schemaHealthReport()
        } catch {
            schemaHealthReport = GraphSchemaHealthReport(
                expectedVersion: SQLiteGraphKernelStore.currentSchemaVersion,
                actualVersion: 0,
                status: .warning,
                missingTables: [],
                missingIndexes: [],
                checkedAt: Date()
            )
            errorMessage = String(describing: error)
        }
    }

    func runSearch() async {
        guard let hybridSearchService else {
            searchResults = []
            errorMessage = "SQLite hybrid search is unavailable."
            return
        }
        do {
            let response = try await hybridSearchService.search(query: GraphSearchQuery(text: query, graphID: "default"))
            searchResults = response.hits
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }
}

struct SchemaHealthBanner: View {
    let model: GraphDiagnosticsModel

    var body: some View {
        HStack(spacing: 10) {
            if let report = model.schemaHealthReport {
                Circle()
                    .fill(statusColor(report.status))
                    .frame(width: 8, height: 8)
                Text("图模型 v\(report.actualVersion)")
                    .font(.caption.weight(.semibold))
                Text(report.status.rawValue)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                if report.status != .healthy {
                    Text(report.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Circle()
                    .fill(Color.gray)
                    .frame(width: 8, height: 8)
                Text("图模型版本未加载")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let databasePath = model.databasePath {
                Text(databasePath)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Button("刷新") { model.reloadSchemaHealthReport() }
                .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.06))
    }

    private func statusColor(_ status: GraphSchemaHealthReport.Status) -> Color {
        switch status {
        case .healthy: return .green
        case .warning: return .orange
        case .migrationRequired: return .red
        }
    }
}

struct GraphEntitiesView: View {
    let entities: [GraphEntity]
    let statements: [GraphStatement]
    let episodes: [GraphEpisodeV3]

    var body: some View {
        List {
            Section("实体") {
                ForEach(entities) { entity in
                    VStack(alignment: .leading) {
                        Text(entity.name).font(.headline)
                        Text("\(entity.entityKind.rawValue) · \(entity.status.rawValue)").font(.caption).foregroundStyle(.secondary)
                        if !entity.summary.isEmpty { Text(entity.summary).font(.subheadline) }
                    }
                }
            }
            Section("陈述") {
                ForEach(statements) { statement in
                    VStack(alignment: .leading) {
                        Text(statement.predicate.rawValue).font(.headline)
                        Text("\(statement.subjectEntityID) → \(statement.objectEntityID)").font(.caption).foregroundStyle(.secondary)
                        Text(statement.statementText).font(.subheadline)
                    }
                }
            }
            Section("Episodes") {
                ForEach(episodes) { episode in
                    VStack(alignment: .leading) {
                        Text(episode.title).font(.headline)
                        Text("\(episode.sourceType.rawValue) · \(episode.status.rawValue)").font(.caption).foregroundStyle(.secondary)
                        Text(episode.content).font(.subheadline).lineLimit(3)
                    }
                }
            }
        }
    }
}

struct SearchView: View {
    @Bindable var model: GraphDiagnosticsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("搜索图谱和观察日志", text: $model.query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await model.runSearch() } }
                Button("搜索") { Task { await model.runSearch() } }
            }
            List(model.searchResults) { result in
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.id).font(.headline)
                    Text(result.ownerType.rawValue).font(.caption).foregroundStyle(.secondary)
                    Text(result.retrievalMethod).font(.subheadline)
                    Text(result.text).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
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
                Text("过期时间：\(entry.expiresAt.connorLocalStandardDateTime())")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct PromotionQueueView: View {
    let model: GraphDiagnosticsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("刷新") { model.reloadPromotionCandidates() }
                if let summary = model.lastPromotionResultSummary {
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
            }

            if model.promotionCandidates.isEmpty {
                Text("暂无可提升候选项。")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(model.promotionCandidates) { entry in
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
                            Text("过期时间：\(entry.expiresAt.connorLocalStandardDateTime())")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        HStack {
                            Button("提升") { model.promote(entry) }
                            Button("忽略") { model.dismissPromotionCandidate(entry) }
                            Button("置顶 30 天") { model.pinPromotionCandidate(entry) }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }

            if let error = model.errorMessage {
                Text(error).foregroundStyle(.red)
            }
        }
        .padding()
        .onAppear {
            model.reloadPromotionCandidates()
        }
    }
}
