import Foundation
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphStore

public struct MemoryOSIngestObservationTool: AgentTool {
    public let name = "memory_os_ingest_observation"
    public let description = "Archive an evidence-backed observation into Connor Memory OS L0 provenance and L1 capture. This replaces legacy graph staging/candidate-write tools."
    public let permission: AgentPermissionCapability = .proposeGraphWrite
    public let inputSchema = AgentToolInputSchema.object(properties: [
        "title": .string(description: "Short human-readable observation title."),
        "content": .string(description: "Raw observed content to archive as provenance."),
        "sourceID": .string(description: "Optional external source/message id."),
        "sessionID": .string(description: "Optional session id. Defaults to current session."),
        "role": .string(description: "Optional source role such as user, assistant, tool, external. Defaults to tool.")
    ], required: ["title", "content"])

    private let facade: AppMemoryOSFacade

    public init(facade: AppMemoryOSFacade) {
        self.facade = facade
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let title = arguments.string("title"), !title.isEmpty else {
            throw AgentToolError.invalidArguments("title is required")
        }
        guard let content = arguments.string("content"), !content.isEmpty else {
            throw AgentToolError.invalidArguments("content is required")
        }
        let sourceID = arguments.string("sourceID") ?? context.toolCallID
        let sessionID = arguments.string("sessionID") ?? context.sessionID
        let role = arguments.string("role") ?? "tool"
        let result = try facade.ingestChatMessage(
            messageID: sourceID,
            sessionID: sessionID,
            role: role,
            content: content,
            occurredAt: Date(),
            metadata: ["title": title, "toolCallID": context.toolCallID, "runID": context.runID]
        )
        let provenanceObjectID = result.provenanceObject?.id ?? ""
        let spanID = result.span?.id ?? ""
        let captureEventID = result.captureEvent?.id ?? ""
        let decisionAction = String(describing: result.decision.action)
        let payload: [String: Any] = [
            "decision": decisionAction,
            "decisionReason": result.decision.reason,
            "provenanceObjectID": provenanceObjectID,
            "spanID": spanID,
            "captureEventID": captureEventID
        ]
        let json = try Self.renderJSON(payload)
        let citations = [provenanceObjectID, spanID, captureEventID].filter { !$0.isEmpty }
        return AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: "Memory OS ingestion decision: \(decisionAction). Provenance object: \(provenanceObjectID.isEmpty ? "none" : provenanceObjectID).",
            contentJSON: json,
            citations: citations
        )
    }

    private static func renderJSON(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

public struct MemoryOSProjectStructuredArtifactTool: AgentTool {
    public let name = "memory_os_project_structured_artifact"
    public let description = "Validate and project a Memory OS structured artifact. GraphStructuredExtractionOutput projects operational facts into L2/L4; MemoryOSKnowledgeExtractionOutput projects reusable knowledge into L3 and concept entities/relations into L4. The artifact is persisted and audited before projection."
    public let permission: AgentPermissionCapability = .proposeGraphWrite
    public let inputSchema = AgentToolInputSchema.object(properties: [
        "rawContent": .string(description: "Raw structured artifact JSON to validate and project."),
        "modelID": .string(description: "Model identifier that produced the artifact."),
        "schemaName": .string(description: "Artifact schema. Defaults to GraphStructuredExtractionOutput. Use MemoryOSKnowledgeExtractionOutput for L3 knowledge candidates."),
        "artifactType": .string(description: "Optional artifact type. Defaults to graph_structured_extraction."),
        "processingRunID": .string(description: "Optional processing run id for audit correlation.")
    ], required: ["rawContent", "modelID"])

    private let facade: AppMemoryOSFacade

    public init(facade: AppMemoryOSFacade) { self.facade = facade }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let rawContent = arguments.string("rawContent"), !rawContent.isEmpty else {
            throw AgentToolError.invalidArguments("rawContent is required")
        }
        guard let modelID = arguments.string("modelID"), !modelID.isEmpty else {
            throw AgentToolError.invalidArguments("modelID is required")
        }
        let runID = arguments.string("processingRunID") ?? context.runID
        let schemaName = arguments.string("schemaName") ?? "GraphStructuredExtractionOutput"
        let artifactType = arguments.string("artifactType") ?? (schemaName == "MemoryOSKnowledgeExtractionOutput" ? "memory_os_knowledge_extraction" : "graph_structured_extraction")
        let summary = try facade.projectAndRecordLLMArtifact(rawContent: rawContent, modelID: modelID, processingRunID: runID, artifactType: artifactType, schemaName: schemaName)
        let payload: [String: Any] = [
            "artifactID": summary.artifactID,
            "accepted": summary.accepted,
            "nodeCount": summary.nodeCount,
            "statementCount": summary.statementCount,
            "entityCount": summary.entityCount,
            "entityStatementCount": summary.entityStatementCount,
            "knowledgeRecordCount": summary.beliefCount,
            "issueCount": summary.issues.count
        ]
        let json = try Self.renderJSON(payload)
        return AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: summary.accepted ? "Memory OS projected artifact \(summary.artifactID): \(summary.statementCount) L2 statements, \(summary.entityCount) L4 entities, \(summary.beliefCount) L3 knowledge records." : "Memory OS rejected artifact \(summary.artifactID): \(summary.issues.count) validation issue(s).",
            contentJSON: json,
            citations: [summary.artifactID]
        )
    }

    private static func renderJSON(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

public struct MemoryOSSearchTool: AgentTool {
    public let name = "memory_os_search"
    public let description = "Search Connor Memory OS across L0/L1/L2/L3/L4 using the local embedded search path. Returns ranked candidate records and entry points only; retrieval hits are context, not graph-complete memory truth. For list/all/which/有哪些/所有/列出 class membership questions, resolve the class first and use memory_os_l4_instances. Use graph tools for relationships, evidence chains, timelines, and cross-layer context."
    public let permission: AgentPermissionCapability = .readGraph
    public let inputSchema = AgentToolInputSchema.object(properties: [
        "query": .string(description: "Search query text."),
        "layers": .array(items: .string(description: "Layer name: L0, L1, L2, L3 or L4."), description: "Optional Memory OS layers to search. Defaults to all layers."),
        "limit": .number(description: "Maximum number of hits. Defaults to 10."),
        "depth": .number(description: "Optional depth hint. Search returns summaries; use memory_os_expand_l4 for explicit depth expansion.")
    ], required: ["query"])

    private let facade: AppMemoryOSFacade

    public init(facade: AppMemoryOSFacade) { self.facade = facade }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let queryText = arguments.string("query"), !queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentToolError.invalidArguments("query is required")
        }
        let layers = parseLayers(arguments.array("layers"))
        let limit = max(1, min(arguments.int("limit") ?? 10, 50))
        let depth = max(0, min(arguments.int("depth") ?? 0, 5))
        let hits = try facade.searchMemoryOS(MemoryOSRetrievalQuery(text: queryText, layers: layers, limit: limit, depth: depth))
        let rows = hits.map { hit -> [String: Any] in
            [
                "layer": hit.layer.rawValue,
                "recordID": hit.recordID,
                "title": hit.title,
                "summary": hit.summary,
                "matchedText": hit.matchedText,
                "score": hit.score,
                "evidenceRefs": hit.evidenceRefs,
                "provenanceRefs": hit.provenanceRefs,
                "entityRefs": hit.entityRefs,
                "canReadRaw": hit.canReadRaw,
                "canExpandDepth": hit.canExpandDepth,
                "metadata": hit.metadata
            ]
        }
        let payload: [String: Any] = ["query": queryText, "hitCount": hits.count, "hits": rows]
        let json = try Self.renderJSON(payload)
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "Memory OS search returned \(hits.count) hit(s) across \(layers.map(\.rawValue).joined(separator: ",")).", contentJSON: json, citations: hits.map(\.recordID))
    }

    private func parseLayers(_ values: [SendableJSONValue]?) -> [MemoryOSRetrievalLayer] {
        guard let values else { return MemoryOSRetrievalLayer.allCases }
        let parsed = values.compactMap { $0.stringValue }.compactMap(MemoryOSRetrievalLayer.init(rawValue:))
        return parsed.isEmpty ? MemoryOSRetrievalLayer.allCases : parsed
    }

    private static func renderJSON(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

public struct MemoryOSGetCurrentUserProfileTool: AgentTool {
    public let name = "memory_os_get_current_user_profile"
    public let description = "Retrieve current-user personalization context from Connor Memory OS using the stable marker current_user. Returns relevant L2/L3/L4 summaries for preferences, habits, traits, projects, constraints, and interaction guidance without relying on mutable display names."
    public let permission: AgentPermissionCapability = .readGraph
    public let inputSchema = AgentToolInputSchema.object(properties: [
        "limit": .number(description: "Maximum number of aggregated hits. Defaults to 12, capped at 50."),
        "focus": .string(description: "Optional task-specific focus query to combine with current-user profile retrieval.")
    ], required: [])

    private let facade: AppMemoryOSFacade

    public init(facade: AppMemoryOSFacade) { self.facade = facade }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let limit = max(1, min(arguments.int("limit") ?? 12, 50))
        let focus = arguments.string("focus")?.trimmingCharacters(in: .whitespacesAndNewlines)
        var queries = [
            "current_user current user profile",
            "current_user user preferences user habits user personality traits user communication preferences",
            "current_user current projects constraints interaction guidance knowledge background"
        ]
        if let focus, !focus.isEmpty {
            queries.insert("current_user \(focus)", at: 0)
        }

        var rows: [[String: Any]] = []
        var seen = Set<String>()
        for query in queries where rows.count < limit {
            let hits = try facade.searchMemoryOS(MemoryOSRetrievalQuery(text: query, layers: [.l2, .l3, .l4], limit: limit, depth: 1))
            for hit in hits where rows.count < limit {
                let key = "\(hit.layer.rawValue):\(hit.recordID)"
                guard seen.insert(key).inserted else { continue }
                rows.append([
                    "layer": hit.layer.rawValue,
                    "recordID": hit.recordID,
                    "title": hit.title,
                    "summary": hit.summary,
                    "matchedText": hit.matchedText,
                    "score": hit.score,
                    "evidenceRefs": hit.evidenceRefs,
                    "provenanceRefs": hit.provenanceRefs,
                    "entityRefs": hit.entityRefs,
                    "canReadRaw": hit.canReadRaw,
                    "canExpandDepth": hit.canExpandDepth,
                    "metadata": hit.metadata
                ])
            }
        }

        let payload: [String: Any] = [
            "currentUserMarker": "current_user",
            "hitCount": rows.count,
            "queries": queries,
            "hits": rows,
            "identityPolicy": "Use current_user as the stable internal role marker. Treat display names and aliases as mutable metadata, never as identity keys."
        ]
        let json = try Self.renderJSON(payload)
        return AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: "Retrieved current_user profile context with \(rows.count) Memory OS hit(s).",
            contentJSON: json,
            citations: rows.compactMap { $0["recordID"] as? String }
        )
    }

    private static func renderJSON(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

public struct MemoryOSExpandL4Tool: AgentTool {
    public let name = "memory_os_expand_l4"
    public let description = "Expand a Memory OS L4 entity/concept by depth-limited traversal. Use this for neighborhood context around a known entity; for complete class membership/list questions, use memory_os_l4_instances instead. Expansion hits are context and do not replace evidence validation."
    public let permission: AgentPermissionCapability = .readGraph
    public let inputSchema = AgentToolInputSchema.object(properties: [
        "entityID": .string(description: "L4 entity id to expand from."),
        "depth": .number(description: "Traversal depth. Defaults to 1, capped at 5."),
        "limit": .number(description: "Maximum expansion hits. Defaults to 20.")
    ], required: ["entityID"])

    private let facade: AppMemoryOSFacade

    public init(facade: AppMemoryOSFacade) { self.facade = facade }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let entityID = arguments.string("entityID"), !entityID.isEmpty else {
            throw AgentToolError.invalidArguments("entityID is required")
        }
        let depth = max(1, min(arguments.int("depth") ?? 1, 5))
        let limit = max(1, min(arguments.int("limit") ?? 20, 100))
        let hits = try facade.expandMemoryOSL4(entityID: entityID, depth: depth, limit: limit)
        let rows = hits.map { hit -> [String: Any] in
            [
                "recordID": hit.recordID,
                "sourceEntityID": hit.sourceEntityID,
                "relatedEntityID": hit.relatedEntityID ?? "",
                "predicate": hit.predicate,
                "text": hit.text,
                "depth": hit.depth,
                "score": hit.score
            ]
        }
        let payload: [String: Any] = ["entityID": entityID, "depth": depth, "hitCount": hits.count, "hits": rows]
        let json = try Self.renderJSON(payload)
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "L4 expansion returned \(hits.count) hit(s) from \(entityID) at depth \(depth).", contentJSON: json, citations: hits.map(\.recordID))
    }

    private static func renderJSON(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

public struct MemoryOSTraceEvidenceTool: AgentTool {
    public let name = "memory_os_trace_evidence"
    public let description = "Trace Memory OS evidence from L3 beliefs or L2 statements down to exact L0 provenance spans and objects. Use this when answer quality depends on source verification."
    public let permission: AgentPermissionCapability = .readGraph
    public let inputSchema = AgentToolInputSchema.object(properties: [
        "spanIDs": .array(items: .string(description: "L0 span id."), description: "Optional L0 span ids."),
        "statementIDs": .array(items: .string(description: "L2 statement id."), description: "Optional L2 statement ids."),
        "beliefIDs": .array(items: .string(description: "L3 belief id."), description: "Optional L3 belief ids."),
        "limit": .number(description: "Maximum traced nodes/refs. Defaults to 100.")
    ], required: [])

    private let facade: AppMemoryOSFacade
    public init(facade: AppMemoryOSFacade) { self.facade = facade }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let spanIDs = Self.parseStringArray(arguments.array("spanIDs"))
        let statementIDs = Self.parseStringArray(arguments.array("statementIDs"))
        let beliefIDs = Self.parseStringArray(arguments.array("beliefIDs"))
        guard !spanIDs.isEmpty || !statementIDs.isEmpty || !beliefIDs.isEmpty else { throw AgentToolError.invalidArguments("At least one of spanIDs, statementIDs, or beliefIDs is required") }
        let limit = max(1, min(arguments.int("limit") ?? 100, 500))
        let subgraph = try facade.traceMemoryOSEvidence(spanIDs: spanIDs, statementIDs: statementIDs, beliefIDs: beliefIDs, limit: limit)
        let payload = MemoryOSL4GraphToolPayload.render(subgraph: subgraph, extra: ["spanIDs": spanIDs, "statementIDs": statementIDs, "beliefIDs": beliefIDs])
        let json = try MemoryOSL4GraphToolPayload.renderJSON(payload)
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "Evidence trace returned \(subgraph.nodes.count) node(s) and \(subgraph.edges.count) edge(s).", contentJSON: json, citations: subgraph.evidenceRefs + subgraph.provenanceRefs)
    }

    private static func parseStringArray(_ values: [SendableJSONValue]?) -> [String] {
        values?.compactMap { $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } ?? []
    }
}

public struct MemoryOSL2FindStatementsTool: AgentTool {
    public let name = "memory_os_l2_find_statements"
    public let description = "Find Memory OS L2 statement edges by text, subject id, and/or predicate filters. Use this for working-fact graph queries before tracing exact evidence."
    public let permission: AgentPermissionCapability = .readGraph
    public let inputSchema = AgentToolInputSchema.object(properties: [
        "text": .string(description: "Optional text query over statement text, subject/object ids, or predicate."),
        "subjectID": .string(description: "Optional L2 subject node id."),
        "predicates": .array(items: .string(description: "Optional predicate filter."), description: "Optional predicate filters."),
        "limit": .number(description: "Maximum statement edges. Defaults to 50.")
    ], required: [])

    private let facade: AppMemoryOSFacade
    public init(facade: AppMemoryOSFacade) { self.facade = facade }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let text = arguments.string("text") ?? ""
        let subjectID = arguments.string("subjectID")
        let predicates = arguments.array("predicates")?.compactMap { $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } ?? []
        let limit = max(1, min(arguments.int("limit") ?? 50, 500))
        let subgraph = try facade.findMemoryOSL2Statements(text: text, subjectID: subjectID, predicates: predicates, limit: limit)
        let payload = MemoryOSL4GraphToolPayload.render(subgraph: subgraph, extra: ["query": text, "subjectID": subjectID ?? "", "predicates": predicates])
        let json = try MemoryOSL4GraphToolPayload.renderJSON(payload)
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "L2 statement query returned \(subgraph.edges.count) edge(s).", contentJSON: json, citations: subgraph.edges.map(\.id) + subgraph.evidenceRefs)
    }
}

public struct MemoryOSL3ExpandBeliefTool: AgentTool {
    public let name = "memory_os_l3_expand_belief"
    public let description = "Expand Memory OS L3 belief nodes to their supporting L2 statements. Use this before memory_os_trace_evidence when derived knowledge requires source grounding."
    public let permission: AgentPermissionCapability = .readGraph
    public let inputSchema = AgentToolInputSchema.object(properties: [
        "beliefID": .string(description: "Optional L3 belief id."),
        "topic": .string(description: "Optional belief topic filter."),
        "text": .string(description: "Optional text query over belief topic/statement."),
        "limit": .number(description: "Maximum belief nodes. Defaults to 20.")
    ], required: [])

    private let facade: AppMemoryOSFacade
    public init(facade: AppMemoryOSFacade) { self.facade = facade }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let beliefID = arguments.string("beliefID")
        let topic = arguments.string("topic")
        let text = arguments.string("text")
        guard !(beliefID ?? "").isEmpty || !(topic ?? "").isEmpty || !(text ?? "").isEmpty else { throw AgentToolError.invalidArguments("At least one of beliefID, topic, or text is required") }
        let limit = max(1, min(arguments.int("limit") ?? 20, 100))
        let subgraph = try facade.expandMemoryOSL3Belief(beliefID: beliefID, topic: topic, text: text, limit: limit)
        let payload = MemoryOSL4GraphToolPayload.render(subgraph: subgraph, extra: ["beliefID": beliefID ?? "", "topic": topic ?? "", "query": text ?? ""])
        let json = try MemoryOSL4GraphToolPayload.renderJSON(payload)
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "L3 belief expansion returned \(subgraph.nodes.count) node(s) and \(subgraph.edges.count) edge(s).", contentJSON: json, citations: subgraph.nodes.map(\.id) + subgraph.edges.map(\.id))
    }
}

public struct MemoryOSL4FindEntityTool: AgentTool {
    public let name = "memory_os_l4_find_entity"
    public let description = "Find Memory OS L4 entity nodes by exact id, stable key, name, or alias. Use this to resolve an entity/class before graph traversal or class membership queries."
    public let permission: AgentPermissionCapability = .readGraph
    public let inputSchema = AgentToolInputSchema.object(properties: [
        "text": .string(description: "Entity id, stable key, name, or alias to resolve."),
        "limit": .number(description: "Maximum entity nodes. Defaults to 20.")
    ], required: ["text"])

    private let facade: AppMemoryOSFacade
    public init(facade: AppMemoryOSFacade) { self.facade = facade }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let text = arguments.string("text"), !text.isEmpty else { throw AgentToolError.invalidArguments("text is required") }
        let limit = max(1, min(arguments.int("limit") ?? 20, 100))
        let subgraph = try facade.findMemoryOSL4Entity(text: text, limit: limit)
        let payload = MemoryOSL4GraphToolPayload.render(subgraph: subgraph, extra: ["query": text])
        let json = try MemoryOSL4GraphToolPayload.renderJSON(payload)
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "L4 entity find returned \(subgraph.nodes.count) node(s) for \(text).", contentJSON: json, citations: subgraph.nodes.map(\.id))
    }
}

public struct MemoryOSL4NeighborsTool: AgentTool {
    public let name = "memory_os_l4_neighbors"
    public let description = "Query outgoing, incoming, or both-direction L4 graph neighbors for a known entity id. Use this for relationship questions after resolving the entity."
    public let permission: AgentPermissionCapability = .readGraph
    public let inputSchema = AgentToolInputSchema.object(properties: [
        "entityID": .string(description: "L4 entity id to traverse from."),
        "direction": .string(description: "outgoing, incoming, or both. Defaults to both."),
        "predicates": .array(items: .string(description: "Optional predicate id filter."), description: "Optional predicate filters."),
        "limit": .number(description: "Maximum edge count. Defaults to 100.")
    ], required: ["entityID"])

    private let facade: AppMemoryOSFacade
    public init(facade: AppMemoryOSFacade) { self.facade = facade }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let entityID = arguments.string("entityID"), !entityID.isEmpty else { throw AgentToolError.invalidArguments("entityID is required") }
        let direction = arguments.string("direction").flatMap(MemoryOSGraphDirection.init(rawValue:)) ?? .both
        let predicates = arguments.array("predicates")?.compactMap { $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } ?? []
        let limit = max(1, min(arguments.int("limit") ?? 100, 1_000))
        let subgraph = try facade.queryMemoryOSL4Neighbors(entityID: entityID, direction: direction, predicates: predicates, limit: limit)
        let payload = MemoryOSL4GraphToolPayload.render(subgraph: subgraph, extra: ["entityID": entityID, "direction": direction.rawValue, "predicates": predicates])
        let json = try MemoryOSL4GraphToolPayload.renderJSON(payload)
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "L4 neighbors query returned \(subgraph.edges.count) edge(s) for \(entityID).", contentJSON: json, citations: subgraph.nodes.map(\.id) + subgraph.edges.map(\.id))
    }
}

private enum MemoryOSL4GraphToolPayload {
    static func render(subgraph: MemoryOSGraphSubgraph, extra: [String: Any]) -> [String: Any] {
        var payload = extra
        payload["nodeCount"] = subgraph.nodes.count
        payload["edgeCount"] = subgraph.edges.count
        payload["nodes"] = subgraph.nodes.map { ["id": $0.id, "layer": $0.layer.rawValue, "kind": $0.kind, "title": $0.title, "summary": $0.summary, "metadata": $0.metadata] as [String: Any] }
        payload["edges"] = subgraph.edges.map { ["id": $0.id, "layer": $0.layer.rawValue, "sourceID": $0.sourceID, "targetID": $0.targetID, "predicate": $0.predicate, "evidenceRefs": $0.evidenceRefs, "confidence": $0.confidence as Any, "validAt": $0.validAt as Any, "metadata": $0.metadata] as [String: Any] }
        payload["evidenceRefs"] = subgraph.evidenceRefs
        payload["provenanceRefs"] = subgraph.provenanceRefs
        payload["explanation"] = subgraph.explanation
        return payload
    }

    static func renderJSON(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

public struct MemoryOSL4InstancesTool: AgentTool {
    public let name = "memory_os_l4_instances"
    public let description = "Query Memory OS L4 graph for instances of one or more class entities using predicates such as P31. Use this for list/all/which/有哪些/所有/列出 class membership questions after resolving the class entity id; unlike memory_os_search, this returns graph-structured instance edges."
    public let permission: AgentPermissionCapability = .readGraph
    public let inputSchema = AgentToolInputSchema.object(properties: [
        "classEntityIDs": .array(items: .string(description: "L4 class entity id such as wikidata:Q6256 or wikidata:Q3624078."), description: "Class entity ids to enumerate instances for."),
        "predicates": .array(items: .string(description: "Predicate id, usually P31 for instance-of."), description: "Optional predicates. Defaults to P31."),
        "limit": .number(description: "Maximum instance edges. Defaults to 100, capped at 1000.")
    ], required: ["classEntityIDs"])

    private let facade: AppMemoryOSFacade

    public init(facade: AppMemoryOSFacade) { self.facade = facade }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let classIDs = parseStringArray(arguments.array("classEntityIDs"))
        guard !classIDs.isEmpty else {
            throw AgentToolError.invalidArguments("classEntityIDs is required")
        }
        let predicates = parseStringArray(arguments.array("predicates"))
        let limit = max(1, min(arguments.int("limit") ?? 100, 1_000))
        let subgraph = try facade.queryMemoryOSL4Instances(classEntityIDs: classIDs, predicates: predicates.isEmpty ? ["P31"] : predicates, limit: limit)
        let payload: [String: Any] = [
            "classEntityIDs": classIDs,
            "predicates": predicates.isEmpty ? ["P31"] : predicates,
            "nodeCount": subgraph.nodes.count,
            "edgeCount": subgraph.edges.count,
            "nodes": subgraph.nodes.map { node in
                ["id": node.id, "layer": node.layer.rawValue, "kind": node.kind, "title": node.title, "summary": node.summary, "metadata": node.metadata] as [String: Any]
            },
            "edges": subgraph.edges.map { edge in
                ["id": edge.id, "layer": edge.layer.rawValue, "sourceID": edge.sourceID, "targetID": edge.targetID, "predicate": edge.predicate, "evidenceRefs": edge.evidenceRefs, "confidence": edge.confidence as Any, "validAt": edge.validAt as Any, "metadata": edge.metadata] as [String: Any]
            },
            "evidenceRefs": subgraph.evidenceRefs,
            "provenanceRefs": subgraph.provenanceRefs,
            "explanation": subgraph.explanation
        ]
        let json = try Self.renderJSON(payload)
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "L4 instances query returned \(subgraph.edges.count) instance edge(s) for \(classIDs.joined(separator: ", ")).", contentJSON: json, citations: subgraph.nodes.map(\.id) + subgraph.edges.map(\.id))
    }

    private func parseStringArray(_ values: [SendableJSONValue]?) -> [String] {
        values?.compactMap { value in
            value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty } ?? []
    }

    private static func renderJSON(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

public struct MemoryOSReadRecordTool: AgentTool {
    public let name = "memory_os_read_record"
    public let description = "Read a full Connor Memory OS record by layer and recordID after a search hit. Use when summary-level context is insufficient for evidence, novelty, or concept/entity identity checks."
    public let permission: AgentPermissionCapability = .readGraph
    public let inputSchema = AgentToolInputSchema.object(properties: [
        "layer": .string(description: "Memory OS layer: L0, L1, L2, L3 or L4."),
        "recordID": .string(description: "Record identifier returned by Memory OS search or known from a job packet.")
    ], required: ["layer", "recordID"])

    private let facade: AppMemoryOSFacade

    public init(facade: AppMemoryOSFacade) { self.facade = facade }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let layer = arguments.string("layer"), !layer.isEmpty else { throw AgentToolError.invalidArguments("layer is required") }
        guard let recordID = arguments.string("recordID"), !recordID.isEmpty else { throw AgentToolError.invalidArguments("recordID is required") }
        let json = try facade.readMemoryOSRecordJSON(layer: layer, recordID: recordID)
        return AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: "Read Memory OS \(layer.uppercased()) record \(recordID).",
            contentJSON: json,
            citations: [recordID]
        )
    }
}

public struct MemoryOSReadProvenanceTool: AgentTool {
    public let name = "memory_os_read_provenance"
    public let description = "Read exact Connor Memory OS L0 provenance object/span content. Use when a prompt preview or search hit is insufficient and exact raw evidence is required."
    public let permission: AgentPermissionCapability = .readGraph
    public let inputSchema = AgentToolInputSchema.object(properties: [
        "provenanceObjectID": .string(description: "L0 provenance object id."),
        "spanID": .string(description: "Optional L0 provenance span id.")
    ], required: ["provenanceObjectID"])

    private let facade: AppMemoryOSFacade

    public init(facade: AppMemoryOSFacade) { self.facade = facade }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let provenanceObjectID = arguments.string("provenanceObjectID"), !provenanceObjectID.isEmpty else { throw AgentToolError.invalidArguments("provenanceObjectID is required") }
        let spanID = arguments.string("spanID")
        let json = try facade.readMemoryOSProvenanceJSON(provenanceObjectID: provenanceObjectID, spanID: spanID)
        return AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: spanID?.isEmpty == false ? "Read Memory OS L0 provenance object \(provenanceObjectID) span \(spanID ?? "")." : "Read Memory OS L0 provenance object \(provenanceObjectID).",
            contentJSON: json,
            citations: [provenanceObjectID, spanID ?? ""].filter { !$0.isEmpty }
        )
    }
}

public extension AgentToolRegistry {
    mutating func registerMemoryOSTools(facade: AppMemoryOSFacade) {
        register(MemoryOSIngestObservationTool(facade: facade))
        register(MemoryOSProjectStructuredArtifactTool(facade: facade))
        register(MemoryOSGetCurrentUserProfileTool(facade: facade))
        register(MemoryOSSearchTool(facade: facade))
        register(MemoryOSTraceEvidenceTool(facade: facade))
        register(MemoryOSL2FindStatementsTool(facade: facade))
        register(MemoryOSL3ExpandBeliefTool(facade: facade))
        register(MemoryOSExpandL4Tool(facade: facade))
        register(MemoryOSL4FindEntityTool(facade: facade))
        register(MemoryOSL4NeighborsTool(facade: facade))
        register(MemoryOSL4InstancesTool(facade: facade))
        register(MemoryOSReadRecordTool(facade: facade))
        register(MemoryOSReadProvenanceTool(facade: facade))
    }
}
