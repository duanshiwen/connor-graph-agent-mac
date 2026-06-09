import Foundation
import ConnorGraphCore
import ConnorGraphMemory

public struct GraphIngestEpisodeTool: AgentTool {
    public let name = "graph_ingest_episode"
    public let description = "Ingest an observed episode into the graph evidence layer and observe log. This does not directly create or mutate nodes/facts."
    public let permission: AgentPermissionCapability = .proposeGraphWrite
    public let inputSchema = AgentToolInputSchema.object(properties: [
        "name": .string(description: "Episode name."),
        "content": .string(description: "Raw observed content."),
        "sourceDescription": .string(description: "Human-readable source description."),
        "sourceID": .string(description: "Optional external source identifier."),
        "workObjectID": .string(description: "Optional work object identifier."),
        "importance": .number(description: "Observe-log importance from 0 to 1."),
        "confidence": .number(description: "Observation confidence from 0 to 1.")
    ], required: ["name", "content", "sourceDescription"])

    private let repository: any GraphRuntimeRepository

    public init(repository: any GraphRuntimeRepository) {
        self.repository = repository
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let name = arguments.string("name"), !name.isEmpty else { throw AgentToolError.invalidArguments("name is required") }
        guard let content = arguments.string("content"), !content.isEmpty else { throw AgentToolError.invalidArguments("content is required") }
        guard let sourceDescription = arguments.string("sourceDescription"), !sourceDescription.isEmpty else { throw AgentToolError.invalidArguments("sourceDescription is required") }

        let episode = GraphEpisode(
            id: UUID().uuidString,
            groupID: context.groupID,
            sourceType: .chatMessage,
            sourceID: arguments.string("sourceID"),
            name: name,
            content: content,
            sourceDescription: sourceDescription,
            sessionID: context.sessionID,
            workObjectID: arguments.string("workObjectID"),
            metadata: ["proposedByRunID": context.runID, "proposedByToolCallID": context.toolCallID]
        )
        try repository.upsert(episode: episode)
        let observe = ObserveLogEntry(
            id: UUID().uuidString,
            kind: .observation,
            source: .tool,
            content: content,
            normalizedSummary: name,
            workObjectID: arguments.string("workObjectID"),
            sessionID: context.sessionID,
            relatedNodeIDs: [],
            relatedEdgeIDs: [],
            importance: 0.5,
            confidence: 0.8,
            metadata: ["episodeID": episode.id, "proposedByRunID": context.runID]
        )
        try repository.upsert(observeLogEntry: observe)
        let json = try renderJSON(["episodeID": episode.id, "observeLogEntryID": observe.id])
        return AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: "Ingested evidence episode \(episode.id). No graph facts were committed.",
            contentJSON: json,
            citations: [episode.id, observe.id]
        )
    }

    private func renderJSON(_ dictionary: [String: String]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

public struct GraphProposeWriteTool: AgentTool {
    public let name = "graph_propose_write"
    public let description = "Create a reviewed graph write candidate. It never commits graph nodes/facts directly."
    public let permission: AgentPermissionCapability = .proposeGraphWrite
    public let inputSchema = AgentToolInputSchema.object(properties: [
        "kind": .string(description: "Candidate kind: createNode, updateNode, createFact, updateFact, invalidateFact, attachEvidence, createMention."),
        "rationale": .string(description: "Why this graph write is proposed."),
        "confidence": .number(description: "Confidence from 0 to 1."),
        "payloadJSON": .string(description: "Candidate payload JSON."),
        "sourceEpisodeID": .string(description: "Optional source episode id."),
        "relatedNodeID": .string(description: "Optional related node id."),
        "relatedFactID": .string(description: "Optional related fact id.")
    ], required: ["kind", "rationale", "payloadJSON"])

    private let repository: any GraphRuntimeRepository

    public init(repository: any GraphRuntimeRepository) {
        self.repository = repository
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let kindRaw = arguments.string("kind"), let kind = GraphWriteCandidateKind(rawValue: kindRaw) else {
            throw AgentToolError.invalidArguments("kind must be a valid GraphWriteCandidateKind")
        }
        guard let rationale = arguments.string("rationale"), !rationale.isEmpty else { throw AgentToolError.invalidArguments("rationale is required") }
        guard let payloadJSON = arguments.string("payloadJSON"), !payloadJSON.isEmpty else { throw AgentToolError.invalidArguments("payloadJSON is required") }
        _ = try JSONSerialization.jsonObject(with: Data(payloadJSON.utf8))

        let candidate = GraphWriteCandidate(
            groupID: context.groupID,
            kind: kind,
            proposedByRunID: context.runID,
            proposedByToolCallID: context.toolCallID,
            rationale: rationale,
            confidence: 0.5,
            payloadJSON: payloadJSON,
            sourceEpisodeIDs: arguments.string("sourceEpisodeID").map { [$0] } ?? [],
            relatedNodeIDs: arguments.string("relatedNodeID").map { [$0] } ?? [],
            relatedFactIDs: arguments.string("relatedFactID").map { [$0] } ?? []
        )
        try repository.upsert(graphWriteCandidate: candidate)
        let json = try JSONSerialization.data(withJSONObject: ["candidateID": candidate.id, "status": candidate.status.rawValue], options: [.sortedKeys])
        return AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: "Created graph write candidate \(candidate.id). It is pending validation/review and was not committed.",
            contentJSON: String(data: json, encoding: .utf8),
            citations: [candidate.id]
        )
    }
}
