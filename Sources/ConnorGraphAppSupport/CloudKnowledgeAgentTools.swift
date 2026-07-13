import Foundation
import ConnorGraphAgent
import ConnorGraphCore

public enum CloudKnowledgePublishingPrompt {
    public static let instruction = """
    You are producing remote Cloud Knowledge inside a user-confirmed Publication Run. These rules are mandatory:
    - Raw local conversations never leave this device. Analyze them only with the user's selected local model. Send only structured knowledge operations through cloud tools.
    - Keep L2 recent operational state separate from L3 reusable knowledge and L4 stable entities/relations.
    - Before every semantic group of writes, search the combined committed + current-run staged view. Use cloud_kb_recent_context for L2 and cloud_kb_knowledge_context for L3/L4. Later conversations must search again so they see earlier staged changes.
    - If a search summary is insufficient, read or expand records before deciding.
    - Every candidate must resolve to exactly one decision: skip_duplicate, revise_existing, reuse_identity, record_temporal_change, record_conflict, or create_new.
    - Every write must cite the search_context_id returned by a relevant successful search. Search contexts cannot cross knowledge bases, runs, layers, sequences, or semantic groups.
    - Use tools incrementally. Never emit or upload a package containing the original conversation. Never invent identity IDs, revision IDs, owner IDs, run IDs, schema versions, or security context.
    - Do not promote ordinary transient facts to L3. Do not create an L4 entity merely because a noun appears.
    - Validate the Publication Run before asking the user to commit it.
    """
}

public actor CloudKnowledgeToolExecutor {
    private let coordinator: CloudKnowledgePublicationCoordinator
    private let searchClient: CloudKnowledgeSearchClient
    public init(coordinator: CloudKnowledgePublicationCoordinator) { self.coordinator = coordinator; self.searchClient = coordinator.makeSearchClient() }

    public func execute(toolName: String, arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        switch toolName {
        case "cloud_kb_recent_context": return try await search(arguments, channel: .recentContext, layers: [.l2], toolName: toolName, context: context)
        case "cloud_kb_knowledge_context": return try await search(arguments, channel: .knowledgeContext, layers: [.l3, .l4], toolName: toolName, context: context)
        case "cloud_kb_read_record", "cloud_kb_expand_entity": return try await search(arguments, channel: .writeAssist, layers: [.l3, .l4], toolName: toolName, context: context)
        case "cloud_kb_l2_update_entities": return try await write(arguments, operationType: "update_l2_entities", layer: .l2, toolName: toolName, context: context)
        case "cloud_kb_l3_update_knowledge": return try await write(arguments, operationType: "update_l3_knowledge", layer: .l3, toolName: toolName, context: context)
        case "cloud_kb_l4_update_entities": return try await write(arguments, operationType: "update_l4_entities", layer: .l4, toolName: toolName, context: context)
        case "cloud_kb_update_relations": return try await write(arguments, operationType: "update_relations", layer: .l4, toolName: toolName, context: context)
        case "cloud_kb_retract_knowledge": return try await write(arguments, operationType: "retract_knowledge", layer: parseLayer(arguments.string("layer")), toolName: toolName, context: context)
        case "cloud_kb_validate_publication":
            let result = try await coordinator.validate(); return try encodedResult(result, toolName: toolName, summary: result.valid ? "Publication Run validation passed." : "Publication Run validation found \(result.issues.count) issue(s).", context: context)
        default: throw AgentToolError.invalidArguments("unsupported cloud knowledge tool: \(toolName)")
        }
    }

    private func search(_ arguments: AgentToolArguments, channel: CloudKnowledgeSearchChannel, layers: [CloudKnowledgeLayer], toolName: String, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let query = arguments.string("query")?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else { throw AgentToolError.invalidArguments("query is required") }
        let response = try await searchClient.search(channel: channel, request: CloudKnowledgeSearchRequest(query: query, layers: layers, limit: arguments.int("limit") ?? 20))
        let lines = response.results.enumerated().map { index, hit in "\(index + 1). [\(hit.layer.rawValue)] \(hit.title ?? hit.identityID ?? hit.stableKey ?? hit.kind): \(hit.text)\(hit.staged ? " (staged)" : "")" }.joined(separator: "\n")
        let text = "Search returned \(response.results.count) result(s). search_context_id=\(response.searchContextID), base_sequence=\(response.baseSequence), staged_sequence=\(response.stagedSequence)." + (lines.isEmpty ? "" : "\n\n\(lines)")
        return try encodedResult(response, toolName: toolName, summary: text, context: context)
    }

    private func write(_ arguments: AgentToolArguments, operationType: String, layer: CloudKnowledgeLayer, toolName: String, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let searchContextID = arguments.string("search_context_id"), !searchContextID.isEmpty else { throw AgentToolError.invalidArguments("search_context_id is required") }
        guard let decisionRaw = arguments.string("decision"), let decision = CloudKnowledgeDecision(rawValue: decisionRaw) else { throw AgentToolError.invalidArguments("decision is required") }
        guard let terms = arguments.array("semantic_terms")?.compactMap(\.stringValue), !terms.isEmpty else { throw AgentToolError.invalidArguments("semantic_terms is required") }
        guard case .object(let payloadValue) = arguments.values["payload"] else { throw AgentToolError.invalidArguments("payload object is required") }
        let candidatePayload = try payloadValue.mapValues(Self.cloudValue)
        if decision == .skipDuplicate || decision == .reuseIdentity || decision == .recordConflict {
            let localDecision: [String: String] = ["decision": decision.rawValue, "status": "not_staged"]
            return try encodedResult(localDecision, toolName: toolName, summary: "Recorded local \(decision.rawValue) decision; no remote write was staged.", context: context)
        }
        let primitive = try Self.primitiveOperation(
            requestedToolOperation: operationType,
            layer: layer,
            decision: decision,
            targetIdentityID: arguments.string("target_identity_id"),
            expectedRevisionID: arguments.string("expected_revision_id"),
            candidatePayload: candidatePayload
        )
        let operation = CloudKnowledgeOperation(operationType: primitive.type, layer: layer, targetIdentityID: primitive.targetIdentityID, expectedRevisionID: primitive.expectedRevisionID, decision: decision, searchContextID: searchContextID, semanticTerms: terms, payload: primitive.payload)
        try await coordinator.stage([operation])
        return try encodedResult(operation, toolName: toolName, summary: "Staged canonical \(primitive.type) operation \(operation.operationID).", context: context)
    }

    private static func primitiveOperation(requestedToolOperation: String, layer: CloudKnowledgeLayer, decision: CloudKnowledgeDecision, targetIdentityID: String?, expectedRevisionID: String?, candidatePayload: [String: CloudKnowledgeJSONValue]) throws -> (type: String, targetIdentityID: String?, expectedRevisionID: String?, payload: [String: CloudKnowledgeJSONValue]) {
        if requestedToolOperation == "retract_knowledge" {
            guard let targetIdentityID, !targetIdentityID.isEmpty else { throw AgentToolError.invalidArguments("retract requires target_identity_id") }
            return ("retract", targetIdentityID, nil, [:])
        }
        switch decision {
        case .createNew:
            guard case .string(let kind)? = candidatePayload["kind"], !kind.isEmpty,
                  case .string(let stableKey)? = candidatePayload["stable_key"], !stableKey.isEmpty,
                  case .string(let validFrom)? = candidatePayload["valid_from"], !validFrom.isEmpty,
                  let knowledgePayload = candidatePayload["payload"]
            else { throw AgentToolError.invalidArguments("create_new payload requires kind, stable_key, valid_from and payload") }
            var timeline: [String: CloudKnowledgeJSONValue] = ["layer": .string(layer.rawValue), "kind": .string(kind), "stable_key": .string(stableKey), "valid_from": .string(validFrom), "payload": knowledgePayload]
            for key in ["valid_to", "confidence", "source_identity_id", "predicate", "target_identity_id"] { if let value = candidatePayload[key] { timeline[key] = value } }
            return ("create", nil, nil, timeline)
        case .reviseExisting, .recordTemporalChange:
            guard let targetIdentityID, !targetIdentityID.isEmpty, let expectedRevisionID, !expectedRevisionID.isEmpty else { throw AgentToolError.invalidArguments("revise requires target_identity_id and expected_revision_id") }
            guard case .string(let validFrom)? = candidatePayload["valid_from"], !validFrom.isEmpty, let knowledgePayload = candidatePayload["payload"] else { throw AgentToolError.invalidArguments("revise payload requires valid_from and payload") }
            var timeline: [String: CloudKnowledgeJSONValue] = ["expected_revision_id": .string(expectedRevisionID), "valid_from": .string(validFrom), "payload": knowledgePayload]
            for key in ["valid_to", "confidence", "source_identity_id", "predicate", "target_identity_id"] { if let value = candidatePayload[key] { timeline[key] = value } }
            return ("revise", targetIdentityID, expectedRevisionID, timeline)
        case .skipDuplicate, .reuseIdentity, .recordConflict:
            throw AgentToolError.invalidArguments("non-writing decision must not be converted to an operation")
        }
    }

    private func parseLayer(_ raw: String?) -> CloudKnowledgeLayer { CloudKnowledgeLayer(rawValue: raw ?? "") ?? .l3 }
    private static func cloudValue(_ value: SendableJSONValue) throws -> CloudKnowledgeJSONValue {
        switch value { case .string(let v): .string(v); case .int(let v): .int(v); case .double(let v): .double(v); case .bool(let v): .bool(v); case .object(let v): .object(try v.mapValues(cloudValue)); case .array(let v): .array(try v.map(cloudValue)); case .null: .null }
    }
    private func encodedResult<T: Encodable>(_ value: T, toolName: String, summary: String, context: AgentToolExecutionContext) throws -> AgentToolResult {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        return AgentToolResult(toolCallID: context.toolCallID, toolName: toolName, contentText: summary, contentJSON: String(data: try encoder.encode(value), encoding: .utf8))
    }
}

public struct CloudKnowledgeAgentTool: AgentTool {
    public var name: String; public var description: String; public var permission: AgentPermissionCapability = .externalNetwork
    public var inputSchema: AgentToolInputSchema; private let executor: CloudKnowledgeToolExecutor
    public init(name: String, description: String, inputSchema: AgentToolInputSchema, executor: CloudKnowledgeToolExecutor) { self.name = name; self.description = description; self.inputSchema = inputSchema; self.executor = executor }
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult { try await executor.execute(toolName: name, arguments: arguments, context: context) }
}

public extension AgentToolRegistry {
    mutating func registerCloudKnowledgePublicationTools(executor: CloudKnowledgeToolExecutor) {
        let searchSchema = AgentToolInputSchema.closedObject(properties: ["query": .string(description: "Semantic query for existing committed and staged knowledge."), "limit": .integer(description: "Maximum results, 1 through 100.")], required: ["query", "limit"])
        let writeSchema = AgentToolInputSchema.object(properties: [
            "search_context_id": .string(description: "Relevant search context returned by a preceding cloud search."),
            "decision": .stringEnumeration(values: CloudKnowledgeDecision.allCases.map(\.rawValue), description: "Required post-search decision."),
            "semantic_terms": .array(items: .string(description: "Term covered by the search."), description: "Semantic terms for trace validation."),
            "target_identity_id": .string(description: "Existing identity returned by search, when applicable."),
            "expected_revision_id": .string(description: "Existing revision returned by search, when applicable."),
            "payload": .object(properties: [:], required: [])
        ], required: ["search_context_id", "decision", "semantic_terms", "payload"])
        register(CloudKnowledgeAgentTool(name: "cloud_kb_recent_context", description: "Search combined committed and current-run staged L2 recent operational knowledge. Returns a mandatory search_context_id for covered L2 writes.", inputSchema: searchSchema, executor: executor))
        register(CloudKnowledgeAgentTool(name: "cloud_kb_knowledge_context", description: "Search combined committed and current-run staged L3/L4 durable knowledge and entities. Returns a mandatory search_context_id.", inputSchema: searchSchema, executor: executor))
        register(CloudKnowledgeAgentTool(name: "cloud_kb_read_record", description: "Read more detail for a knowledge record through write-assist search without exposing provenance or raw conversations.", inputSchema: searchSchema, executor: executor))
        register(CloudKnowledgeAgentTool(name: "cloud_kb_expand_entity", description: "Expand an entity neighborhood through write-assist search before an L4 decision.", inputSchema: searchSchema, executor: executor))
        for (name, description) in [("cloud_kb_l2_update_entities", "Stage L2 operational entity changes."), ("cloud_kb_l3_update_knowledge", "Stage L3 reusable knowledge changes."), ("cloud_kb_l4_update_entities", "Stage L4 stable entity changes."), ("cloud_kb_update_relations", "Stage temporal relation changes."), ("cloud_kb_retract_knowledge", "Stage a governed retract operation.")] { register(CloudKnowledgeAgentTool(name: name, description: description + " Security context is injected locally and cannot be supplied by the model.", inputSchema: writeSchema, executor: executor)) }
        register(CloudKnowledgeAgentTool(name: "cloud_kb_validate_publication", description: "Validate all staged operations before user preview and commit.", inputSchema: .closedObject(properties: [:], required: []), executor: executor))
    }
}
