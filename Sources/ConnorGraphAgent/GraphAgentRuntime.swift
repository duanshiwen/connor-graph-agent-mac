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
        let response = try await hybridSearchService.search(query: GraphSearchQuery(text: query, graphID: groupID, limit: limit))
        return AgentContext(query: query, items: response.hits.map(contextItem))
    }

    private func contextItem(_ hit: GraphSearchHit) -> AgentContextItem {
        AgentContextItem(
            sourceID: hit.id,
            kind: resultKind(for: hit.ownerType),
            content: renderedContent(for: hit),
            reason: "matched via \(hit.retrievalMethod)"
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
