import Foundation
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphSearch

public struct ObserveLogRecorder: Sendable, Equatable {
    public init() {}

    public func entry(for message: AgentMessage, sessionID: String) -> ObserveLogEntry {
        ObserveLogEntry(
            id: "observe-message-\(message.id)",
            timestamp: message.createdAt,
            kind: .observation,
            source: message.role == .user ? .user : .agent,
            content: message.content,
            sessionID: sessionID
        )
    }
}

public struct AgentContextBuilder: Sendable {
    private var hybridSearchService: any GraphHybridSearchService
    public private(set) var groupID: String
    private var limit: Int

    public init(
        hybridSearchService: any GraphHybridSearchService,
        groupID: String,
        limit: Int = 20
    ) {
        self.hybridSearchService = hybridSearchService
        self.groupID = groupID
        self.limit = limit
    }

    public func context(for query: String) async throws -> AgentContext {
        try await memoryContextContract(for: query).agentContext
    }

    public func memoryContextContract(for request: AgentChatRequest, generatedAt: Date = Date()) async throws -> AgentGraphMemoryContextContract {
        try await memoryContextContract(
            for: request.userMessage,
            sessionID: request.sessionID,
            runID: request.runID,
            permissionMode: request.permissionMode,
            generatedAt: generatedAt
        )
    }

    public func memoryContextContract(
        for query: String,
        sessionID: String? = nil,
        runID: String? = nil,
        permissionMode: AgentPermissionMode = .askToWrite,
        generatedAt: Date = Date()
    ) async throws -> AgentGraphMemoryContextContract {
        let response = try await hybridSearchService.search(query: GraphSearchQuery(text: query, graphID: groupID, limit: limit))
        let items = response.hits.map(memoryContextItem)
        let roleCounts = Dictionary(grouping: items, by: { $0.role.rawValue }).mapValues(\.count)
        let evidenceEpisodes = Set(items.flatMap(\.evidenceEpisodeIDs))
        let retrievalMethods = Array(Set(response.hits.map(\.retrievalMethod))).sorted()
        let summary = items.isEmpty
            ? "No graph memory context for query '\(query)' in graph \(groupID)."
            : "\(items.count) graph memory item\(items.count == 1 ? "" : "s") for query '\(query)' in graph \(groupID); roles: \(roleCounts.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", "))."
        return AgentGraphMemoryContextContract(
            query: query,
            sessionID: sessionID,
            runID: runID,
            groupID: groupID,
            generatedAt: generatedAt,
            policy: permissionMode == .readOnly ? .passiveContext : .activeContextAndFeedback,
            items: items,
            summary: summary,
            hasStaleSignals: response.hits.contains { isTruthy($0.metadata["stale"]) || isTruthy($0.metadata["superseded"]) },
            hasConflictSignals: response.hits.contains { isTruthy($0.metadata["conflict"]) || isTruthy($0.metadata["anomaly"]) },
            hasUncertaintySignals: response.hits.contains { isTruthy($0.metadata["uncertain"]) || ($0.metadata["belief_status"] == "uncertain") },
            retrievalMetrics: AgentGraphMemoryRetrievalMetrics(
                itemCount: items.count,
                evidenceEpisodeCount: evidenceEpisodes.count,
                roleCounts: roleCounts,
                retrievalMethods: retrievalMethods
            )
        )
    }

    private func contextItem(_ hit: GraphSearchHit) -> AgentContextItem {
        let item = memoryContextItem(hit)
        return AgentContextItem(
            sourceID: item.sourceID,
            kind: item.kind,
            content: item.content,
            reason: item.reason
        )
    }

    private func memoryContextItem(_ hit: GraphSearchHit) -> AgentGraphMemoryContextItem {
        AgentGraphMemoryContextItem(
            sourceID: hit.id,
            kind: resultKind(for: hit.ownerType),
            role: memoryRole(for: hit),
            content: renderedContent(for: hit),
            reason: "matched via \(hit.retrievalMethod)",
            scoreLabel: "\(Int((hit.score * 100).rounded()))%",
            evidenceEpisodeIDs: hit.sourceEpisodeIDs,
            metadata: hit.metadata
        )
    }

    private func resultKind(for ownerType: GraphIndexOwnerType) -> GraphSearchResultKind {
        switch ownerType {
        case .entity: .node
        case .statement: .edge
        case .episode: .observeLog
        }
    }

    private func renderedContent(for hit: GraphSearchHit) -> String {
        switch hit.ownerType {
        case .entity:
            let type = hit.metadata["entity_kind"] ?? "entity"
            return "Entity[\(type)] \(hit.title): \(hit.text)"
        case .statement:
            var lines = ["Statement[\(hit.title)] \(hit.text)"]
            if let path = hit.metadata["inference_path"], !path.isEmpty {
                lines.append("Inference path: \(path)")
            }
            return lines.joined(separator: "\n")
        case .episode:
            let sourceType = hit.metadata["source_type"] ?? "episode"
            return "Episode[\(sourceType)] \(hit.title): \(hit.text)"
        }
    }

    private func memoryRole(for hit: GraphSearchHit) -> AgentGraphMemoryContextItemRole {
        let fields = [
            hit.metadata["memory_role"],
            hit.metadata["candidate_kind"],
            hit.metadata["kind"],
            hit.metadata["source_type"],
            hit.metadata["entity_kind"],
            hit.title,
            hit.text
        ].compactMap { $0?.lowercased() }.joined(separator: " ")
        if containsAny(fields, ["preference", "偏好", "喜欢", "不喜欢", "prefer"]) { return .preference }
        if containsAny(fields, ["decision", "决定", "decided", "采用", "不再", "改为"]) { return .decision }
        if containsAny(fields, ["project", "project_fact", "work_object", "项目", "架构", "实现", "branch", "commit"]) { return .projectState }
        if containsAny(fields, ["profile", "persona", "person", "用户画像", "身份"]) { return .profile }
        if containsAny(fields, ["risk", "risk_flag", "风险", "blocked", "blocker", "失败"]) { return .risk }
        if containsAny(fields, ["unresolved", "open_question", "question", "待确认", "未解决", "?"]) { return .openQuestion }
        if hit.ownerType == .statement { return .evidence }
        return .background
    }

    private func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0.lowercased()) }
    }

    private func isTruthy(_ value: String?) -> Bool {
        guard let value else { return false }
        return ["true", "1", "yes", "y"].contains(value.lowercased())
    }
}

public enum AgentContextBuilderError: Error, Sendable, Equatable {
    case asyncContextRequired
}

public struct LLMResponse: Sendable, Equatable {
    public var text: String
    public var citations: [String]

    public init(text: String, citations: [String]) {
        self.text = text
        self.citations = citations
    }
}

public protocol LLMProvider: Sendable {
    func complete(prompt: String, context: AgentContext) async throws -> LLMResponse
}

public extension AgentContextBuilder {
    var groupIdentifier: String { groupID }
}
