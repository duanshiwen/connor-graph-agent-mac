import Foundation
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphStore

public struct MemoryOSL2FindEntitiesTool: AgentTool {
    public let name = "memory_os_l2_find_entities"
    public let description = "Find Memory OS L2 working-memory entities by exact name or alias. Provide possible names/aliases in one string separated by comma, Chinese comma, dunhao, semicolon, or newline. Returns only LLM-relevant entity name, aliases, type, summary, statement text, relation, and connected entity."
    public let permission: AgentPermissionCapability = .readGraph
    public let inputSchema = AgentToolInputSchema.object(properties: [
        "names": .string(description: "Possible entity names or aliases separated by comma, Chinese comma, dunhao, semicolon, or newline. Exact name/alias matching; no limit parameter.")
    ], required: ["names"])

    private let facade: AppMemoryOSFacade

    public init(facade: AppMemoryOSFacade) { self.facade = facade }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let names = arguments.string("names"), !names.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentToolError.invalidArguments("names is required")
        }
        let result = try facade.findMemoryOSL2Entities(MemoryOSL2FindEntitiesRequest(names: names))
        let json = try Self.renderJSON(result)
        return AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: result.matches.isEmpty ? result.message : "Found \(result.matches.count) Memory OS L2 entity match(es).",
            contentJSON: json,
            citations: []
        )
    }

    private static func renderJSON<T: Encodable>(_ object: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(object)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

public struct MemoryOSL2UpdateEntitiesTool: AgentTool {
    public let name = "memory_os_l2_update_entities"
    public let description = "Update Memory OS L2 entity-centered working memory. Use this for concise entity summaries and useful statements. Do not provide evidence or internal IDs; L0 remains the provenance layer."
    public let permission: AgentPermissionCapability = .proposeGraphWrite
    public let inputSchema = AgentToolInputSchema.object(properties: [
        "entities": .array(items: .object(properties: [
            "name": .string(description: "Entity display name."),
            "type": .string(description: "Entity type such as entity, person_object, work_object, life_object, event, place, artifact, document, concept, metric, or time_expression. Defaults to entity if omitted."),
            "aliases": .string(description: "Optional aliases separated by comma, Chinese comma, dunhao, semicolon, or newline."),
            "summary": .string(description: "Optional concise summary."),
            "statements": .array(items: .object(properties: [
                "text": .string(description: "Complete natural-language L2 statement. Preserve important original wording and negation."),
                "relation": .string(description: "Optional GraphPredicate raw value. Defaults to RELATED_TO. Lowercase snake_case is normalized, e.g. related_to -> RELATED_TO; invalid values are rejected."),
                "connectedEntity": .string(description: "Optional connected entity name."),
                "connectedEntityType": .string(description: "Optional connected entity type."),
                "factType": .string(description: "Optional L2 fact type. Allowed values: profile_preference, project_state, task_commitment, calendar_time, communication, source_document, decision, implementation, environment_config, relationship, other. Leave empty when unknown."),
                "polarity": .string(description: "Optional polarity such as affirm, exclude, reject, cancel, defer, supersede, or unknown."),
                "originalPhrase": .string(description: "Optional original phrase to preserve user wording, especially for negative decisions.")
            ], required: ["text"]), description: "Statements associated with this entity.")
        ], required: ["name"]), description: "Entities to update in one batch.")
    ], required: ["entities"])

    private let facade: AppMemoryOSFacade

    public init(facade: AppMemoryOSFacade) { self.facade = facade }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let request = try Self.decodeRequest(arguments)
        let result = try facade.updateMemoryOSL2Entities(request)
        let json = try Self.renderJSON(result)
        return AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: "Updated \(result.updatedEntities.count) Memory OS L2 entit(ies).",
            contentJSON: json,
            citations: []
        )
    }

    private static func decodeRequest(_ arguments: AgentToolArguments) throws -> MemoryOSL2UpdateEntitiesRequest {
        guard let entities = arguments.array("entities") else {
            throw AgentToolError.invalidArguments("entities is required")
        }
        let object = SendableJSONValue.object(["entities": .array(entities)])
        let data = try JSONSerialization.data(withJSONObject: object.jsonCompatibleObject(), options: [])
        return try JSONDecoder().decode(MemoryOSL2UpdateEntitiesRequest.self, from: data)
    }

    private static func renderJSON<T: Encodable>(_ object: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(object)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

private extension SendableJSONValue {
    func jsonCompatibleObject() -> Any {
        switch self {
        case .string(let value): value
        case .int(let value): value
        case .double(let value): value
        case .bool(let value): value
        case .object(let object): object.mapValues { $0.jsonCompatibleObject() }
        case .array(let array): array.map { $0.jsonCompatibleObject() }
        case .null: NSNull()
        }
    }
}

public struct MemoryOSContextTool: AgentTool {
    public let name = "memory_os_context"
    public let description = "Build a commercial-grade Memory OS context package for the AI by orchestrating L0-L4 retrieval, optional L4 graph expansion, deterministic organization, verbalization, diagnostics, and budget reporting. Prefer this over low-level memory_os_search when answering user questions from memory."
    public let permission: AgentPermissionCapability = .readGraph
    public let inputSchema = AgentToolInputSchema.object(properties: [
        "query": .string(description: "Natural-language memory context query."),
        "taskIntent": .string(description: "auto, answerQuestion, planWork, verifyClaim, explainRelationship, listInstances, currentUserPersonalization, etc. Defaults to auto."),
        "subjectHints": .array(items: .string(description: "Entity, project, person, or concept hint."), description: "Optional subject hints."),
        "layers": .array(items: .string(description: "Layer name: L0, L1, L2, L3 or L4."), description: "Optional Memory OS layers. Defaults to all layers."),
        "requireEvidence": .boolean(description: "Whether evidence should be required and diagnostics exposed. Defaults to false."),
        "graphDepth": .number(description: "Optional L4 graph expansion depth. Defaults to 1, capped at 5."),
        "maxContextCharacters": .number(description: "Maximum contextText characters. Defaults to commercial policy."),
        "outputMode": .string(description: "compact, balanced, evidenceHeavy, or graphHeavy. Defaults to balanced."),
        "language": .string(description: "zhHans, en, or bilingual. Defaults to zhHans.")
    ], required: ["query"])

    private let facade: AppMemoryOSFacade

    public init(facade: AppMemoryOSFacade) { self.facade = facade }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let queryText = arguments.string("query")?.trimmingCharacters(in: .whitespacesAndNewlines), !queryText.isEmpty else {
            throw AgentToolError.invalidArguments("query is required")
        }
        let intent = arguments.string("taskIntent").flatMap(MemoryOSTaskIntent.init(rawValue:)) ?? .auto
        let layers = parseLayers(arguments.array("layers"))
        let subjectHints = parseStringArray(arguments.array("subjectHints"))
        let graphDepth = max(0, min(arguments.int("graphDepth") ?? 1, 5))
        let budget = budget(maxContextCharacters: arguments.int("maxContextCharacters"))
        let request = MemoryOSContextRequest(
            query: queryText,
            taskIntent: intent,
            subjectHints: subjectHints,
            layers: layers,
            evidencePolicy: MemoryOSEvidencePolicy(required: arguments.bool("requireEvidence") ?? false),
            graphPolicy: MemoryOSGraphExpansionPolicy(enabled: graphDepth > 0, maxDepth: graphDepth, maxEdgesPerSeed: 8, expansionStrategy: graphDepth > 0 ? .mixed : .none),
            budget: budget,
            outputMode: arguments.string("outputMode").flatMap(MemoryOSContextOutputMode.init(rawValue:)) ?? .balanced,
            referenceTime: Date(),
            language: arguments.string("language").flatMap(MemoryOSContextLanguage.init(rawValue:)) ?? .zhHans
        )
        let package = try facade.memoryOSContext(request)
        let json = try Self.renderJSON(package)
        return AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: "Memory OS context package returned \(package.blocks.count) block(s), \(package.entities.count) entity card(s), and \(package.relations.count) relation card(s).",
            contentJSON: json,
            citations: package.blocks.flatMap(\.recordIDs) + package.entities.map(\.entityID) + package.relations.map(\.id) + package.evidence.map(\.evidenceRef)
        )
    }

    private func parseLayers(_ values: [SendableJSONValue]?) -> [MemoryOSRetrievalLayer] {
        guard let values else { return MemoryOSRetrievalLayer.allCases }
        let parsed = values.compactMap { $0.stringValue }.compactMap(MemoryOSRetrievalLayer.init(rawValue:))
        return parsed.isEmpty ? MemoryOSRetrievalLayer.allCases : parsed
    }

    private func parseStringArray(_ values: [SendableJSONValue]?) -> [String] {
        values?.compactMap { $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } ?? []
    }

    private func budget(maxContextCharacters: Int?) -> MemoryOSContextBudget {
        var budget = MemoryOSContextBudget.commercialDefault
        if let maxContextCharacters { budget.maxContextCharacters = max(500, min(maxContextCharacters, 50_000)) }
        return budget
    }

    private static func renderJSON(_ object: MemoryOSContextPackage) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(object)
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
        let profile = try facade.currentUserProfileContext(limit: limit, focus: focus)
        let rows = profile.hits.map(Self.row)
        let diagnostics = profile.diagnostics.map { diagnostic -> [String: Any] in
            [
                "id": diagnostic.id,
                "kind": diagnostic.kind,
                "severity": diagnostic.severity,
                "message": diagnostic.message,
                "candidateRecordIDs": diagnostic.candidateRecordIDs
            ]
        }
        let payload: [String: Any] = [
            "currentUserMarker": profile.currentUserMarker,
            "resolvedCurrentUserEntityIDs": profile.resolvedCurrentUserEntityIDs,
            "hitCount": rows.count,
            "hits": rows,
            "diagnostics": diagnostics,
            "scopePolicy": profile.scopePolicy,
            "identityPolicy": "Use current_user as the stable internal role marker. Never substitute generic user concepts, display names, aliases, or full-text search hits for the current user identity anchor."
        ]
        let json = try Self.renderJSON(payload)
        return AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: "Retrieved current_user profile context with \(rows.count) scoped Memory OS hit(s).",
            contentJSON: json,
            citations: profile.hits.map(\.recordID)
        )
    }

    private static func row(_ hit: MemoryOSRetrievalHit) -> [String: Any] {
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

    private static func renderJSON(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

public struct MemoryOSUpdateCurrentUserProfileTool: AgentTool {
    public let name = "memory_os_update_current_user_profile"
    public let description = "Append evidence-backed current-user profile observations to Connor Memory OS. Ensures the protected current_user Person anchor, archives provenance, and projects scoped L2/L4 profile facts without using generic user search terms."
    public let permission: AgentPermissionCapability = .proposeGraphWrite
    public let inputSchema = AgentToolInputSchema.object(properties: [
        "observations": .array(items: .object(properties: [
            "profileDimension": .string(description: "Profile dimension such as preference, habit, stable_trait, communication_preference, knowledge_background, emotional_support_preference, goal, constraint, personal_context, or interaction_guidance."),
            "statement": .string(description: "Evidence-backed profile statement about the current user."),
            "evidence": .string(description: "Quoted or summarized evidence supporting the statement."),
            "confidence": .number(description: "Confidence from 0.0 to 1.0."),
            "source": .string(description: "Evidence source such as user_explicit, observed_behavior, repeated_pattern, or assistant_inference."),
            "stability": .string(description: "one_off, emerging, or stable."),
            "sensitivity": .string(description: "normal or sensitive."),
            "validAt": .string(description: "Optional ISO8601 validity timestamp.")
        ], required: ["profileDimension", "statement", "evidence"]), description: "Current user profile observations to append."),
        "mode": .string(description: "append_observations or propose_profile_facts. Defaults to propose_profile_facts."),
        "sessionID": .string(description: "Optional session id. Defaults to current session.")
    ], required: ["observations"])

    private let facade: AppMemoryOSFacade

    public init(facade: AppMemoryOSFacade) { self.facade = facade }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let observations = try parseObservations(arguments)
        guard !observations.isEmpty else { throw AgentToolError.invalidArguments("observations must not be empty") }
        let mode = arguments.string("mode") ?? "propose_profile_facts"
        let sessionID = arguments.string("sessionID") ?? context.sessionID
        let now = Date()
        let anchor = try facade.ensureCurrentUserAnchor(now: now)

        var statementIDs: [String] = []
        var provenanceIDs: [String] = []
        var artifactIDs: [String] = []
        for (index, observation) in observations.enumerated() {
            let sourceID = "current-user-profile-update:\(context.toolCallID):\(index)"
            let ingestion = try facade.ingestChatMessage(
                messageID: sourceID,
                sessionID: sessionID,
                role: "user",
                content: observation.evidence,
                occurredAt: now,
                metadata: [
                    "title": "Current user profile observation",
                    "toolCallID": context.toolCallID,
                    "runID": context.runID,
                    "memory_os_update_mode": mode,
                    "person_role": "current_user",
                    "identity_anchor_id": anchor.id,
                    "profile_dimension": observation.profileDimension,
                    "evidence_quality": observation.source,
                    "stability": observation.stability,
                    "sensitivity": observation.sensitivity
                ]
            )
            if let provenanceID = ingestion.provenanceObject?.id { provenanceIDs.append(provenanceID) }
            let spanID = ingestion.span?.id ?? "span-current-user-profile-\(context.toolCallID)-\(index)"
            let artifactJSON = try Self.currentUserProfileArtifactJSON(observation: observation, anchor: anchor, spanID: spanID, now: now)
            let summary = try facade.projectAndRecordLLMArtifact(
                rawContent: artifactJSON,
                modelID: "memory_os_update_current_user_profile",
                processingRunID: context.runID,
                artifactType: "memory_os_current_user_profile_update",
                schemaName: "MemoryOSL1UnifiedProjectionOutput",
                now: now
            )
            artifactIDs.append(summary.artifactID)
            guard summary.accepted else {
                throw AgentToolError.invalidArguments("Current user profile update rejected: \(summary.issues.map(\.message).joined(separator: "; "))")
            }
            statementIDs.append(contentsOf: try facade.l2StatementIDs(sourceArtifactID: summary.artifactID))
        }

        let payload: [String: Any] = [
            "accepted": true,
            "mode": mode,
            "currentUserMarker": "current_user",
            "currentUserEntityID": anchor.id,
            "statementIDs": statementIDs,
            "provenanceObjectIDs": provenanceIDs,
            "artifactIDs": artifactIDs,
            "scopePolicy": "append_only_evidence_backed_current_user_anchor"
        ]
        let json = try Self.renderJSON(payload)
        return AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: "Updated current_user profile with \(statementIDs.count) scoped Memory OS statement(s).",
            contentJSON: json,
            citations: statementIDs + provenanceIDs + artifactIDs
        )
    }

    private struct Observation {
        var profileDimension: String
        var statement: String
        var evidence: String
        var confidence: Double
        var source: String
        var stability: String
        var sensitivity: String
        var validAt: Date?
    }

    private func parseObservations(_ arguments: AgentToolArguments) throws -> [Observation] {
        guard let values = arguments.array("observations") else { throw AgentToolError.invalidArguments("observations is required") }
        return try values.enumerated().map { index, value in
            guard let object = value.objectValue else { throw AgentToolError.invalidArguments("observations[\(index)] must be an object") }
            guard let dimension = object["profileDimension"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !dimension.isEmpty else { throw AgentToolError.invalidArguments("observations[\(index)].profileDimension is required") }
            guard let statement = object["statement"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !statement.isEmpty else { throw AgentToolError.invalidArguments("observations[\(index)].statement is required") }
            guard let evidence = object["evidence"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !evidence.isEmpty else { throw AgentToolError.invalidArguments("observations[\(index)].evidence is required") }
            let confidence: Double
            switch object["confidence"] {
            case .double(let value): confidence = value
            case .int(let value): confidence = Double(value)
            default: confidence = 0.8
            }
            let validAt: Date?
            if let raw = object["validAt"]?.stringValue, !raw.isEmpty {
                validAt = ISO8601DateFormatter().date(from: raw)
            } else {
                validAt = nil
            }
            return Observation(
                profileDimension: dimension,
                statement: statement,
                evidence: evidence,
                confidence: max(0.0, min(confidence, 1.0)),
                source: object["source"]?.stringValue ?? "user_explicit",
                stability: object["stability"]?.stringValue ?? "emerging",
                sensitivity: object["sensitivity"]?.stringValue ?? "normal",
                validAt: validAt
            )
        }
    }

    private static func currentUserProfileArtifactJSON(observation: Observation, anchor: MemoryOSEntity, spanID: String, now: Date) throws -> String {
        let predicate = predicate(for: observation.profileDimension)
        let localID = "current_user"
        let output = MemoryOSL1UnifiedProjectionOutput(
            operationalEntities: [GraphStructuredExtractedEntity(
                localID: localID,
                name: "Current User",
                entityKind: .personObject,
                scope: .personal,
                aliases: [],
                summary: "The human currently operating this Connor installation.",
                confidence: 0.99,
                evidenceSpanIDs: [spanID],
                metadata: [
                    "stable_key": "current_user",
                    "person_role": "current_user",
                    "role": "current_user",
                    "identity_anchor_id": anchor.id,
                    "identity_scope": "local_app_owner",
                    "system_owned": "true",
                    "protected_identity_anchor": "true"
                ]
            )],
            operationalStatements: [GraphStructuredExtractedStatement(
                explicitID: "current-user-profile-\(UUID().uuidString)",
                subjectLocalID: localID,
                predicate: predicate,
                objectLocalID: localID,
                statementText: observation.statement,
                confidence: observation.confidence,
                validAt: observation.validAt ?? now,
                referenceTime: now,
                evidenceSpanIDs: [spanID],
                metadata: [
                    "l2_fact_type": "profile_preference",
                    "person_role": "current_user",
                    "person_resolution": "resolved",
                    "identity_anchor": "current_user",
                    "identity_anchor_id": anchor.id,
                    "profile_dimension": observation.profileDimension,
                    "evidence_quality": observation.source,
                    "stability": observation.stability,
                    "sensitivity": observation.sensitivity,
                    "source_stage": "current_user_profile_update_tool"
                ]
            )],
            evidenceSpans: [GraphStructuredEvidenceSpan(id: spanID, text: observation.evidence)],
            knowledgeCandidates: [],
            conceptEntities: [],
            conceptRelations: [],
            promotionDecisions: [],
            warnings: [],
            confidence: observation.confidence,
            metadata: [
                "schema_purpose": "current_user_profile_update",
                "person_role": "current_user",
                "identity_anchor_id": anchor.id
            ]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(output)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func predicate(for dimension: String) -> GraphPredicate {
        switch dimension {
        case "preference", "communication_preference", "interaction_guidance", "emotional_support_preference": return .prefers
        case "dislike": return .dislikes
        case "habit": return .hasHabit
        case "goal": return .hasGoal
        default: return .relatedTo
        }
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

public struct MemoryOSQueryGraphTool: AgentTool {
    public let name = "memory_os_query_graph"
    public let description = "Orchestrate Memory OS layered graph retrieval across L2 statements, L3 beliefs, L4 entity/relationship/membership queries, and optional L0 evidence tracing. Use this for graph-complete questions when one low-level graph tool is not enough."
    public let permission: AgentPermissionCapability = .readGraph
    public let inputSchema = AgentToolInputSchema.object(properties: [
        "text": .string(description: "Natural-language query or entity/class text to resolve."),
        "intent": .string(description: "auto, l2Statements, l3Beliefs, l4Entity, l4Neighbors, l4Instances, or evidence. Defaults to auto."),
        "entityID": .string(description: "Optional known L4 entity id for neighbor queries."),
        "classEntityIDs": .array(items: .string(description: "Optional L4 class ids for instance queries."), description: "Optional class ids."),
        "predicates": .array(items: .string(description: "Optional controlled L4 predicate filter."), description: "Optional predicate filters such as INSTANCE_OF or HAS_PART."),
        "direction": .string(description: "outgoing, incoming, or both for neighbor queries. Defaults to both."),
        "includeEvidence": .boolean(description: "Trace returned L2/L3 evidence to L0 provenance. Defaults to false."),
        "limit": .number(description: "Maximum graph records. Defaults to 50.")
    ], required: [])

    private let facade: AppMemoryOSFacade
    public init(facade: AppMemoryOSFacade) { self.facade = facade }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let text = arguments.string("text") ?? ""
        let intent = arguments.string("intent").flatMap(MemoryOSGraphQueryIntent.init(rawValue:)) ?? .auto
        let direction = arguments.string("direction").flatMap(MemoryOSGraphDirection.init(rawValue:)) ?? .both
        let classIDs = Self.parseStringArray(arguments.array("classEntityIDs"))
        let predicates = Self.parseStringArray(arguments.array("predicates"))
        let includeEvidence = arguments.bool("includeEvidence") ?? false
        let limit = max(1, min(arguments.int("limit") ?? 50, 500))
        let subgraph = try facade.queryMemoryOSGraph(MemoryOSGraphQuery(text: text, intent: intent, entityID: arguments.string("entityID"), classEntityIDs: classIDs, predicates: predicates, direction: direction, includeEvidence: includeEvidence, limit: limit))
        let payload = MemoryOSL4GraphToolPayload.render(subgraph: subgraph, extra: ["query": text, "intent": intent.rawValue, "entityID": arguments.string("entityID") ?? "", "classEntityIDs": classIDs, "predicates": predicates, "direction": direction.rawValue, "includeEvidence": includeEvidence])
        let json = try MemoryOSL4GraphToolPayload.renderJSON(payload)
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "Memory OS query_graph returned \(subgraph.nodes.count) node(s) and \(subgraph.edges.count) edge(s).", contentJSON: json, citations: subgraph.nodes.map(\.id) + subgraph.edges.map(\.id) + subgraph.evidenceRefs + subgraph.provenanceRefs)
    }

    private static func parseStringArray(_ values: [SendableJSONValue]?) -> [String] {
        values?.compactMap { $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } ?? []
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
    public let description = "Query Memory OS L4 graph for instances of one or more class entities using controlled L4 predicates such as INSTANCE_OF. Use this for list/all/which/有哪些/所有/列出 class membership questions after resolving the class entity id; unlike memory_os_search, this returns graph-structured instance edges."
    public let permission: AgentPermissionCapability = .readGraph
    public let inputSchema = AgentToolInputSchema.object(properties: [
        "classEntityIDs": .array(items: .string(description: "L4 class entity id such as wikidata:Q6256 or wikidata:Q3624078."), description: "Class entity ids to enumerate instances for."),
        "predicates": .array(items: .string(description: "Controlled L4 predicate raw value, usually INSTANCE_OF for instance-of."), description: "Optional predicates. Defaults to INSTANCE_OF."),
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
        let effectivePredicates = predicates.isEmpty ? [MemoryOSL4RelationPredicate.instanceOf.rawValue] : predicates
        let subgraph = try facade.queryMemoryOSL4Instances(classEntityIDs: classIDs, predicates: effectivePredicates, limit: limit)
        let payload: [String: Any] = [
            "classEntityIDs": classIDs,
            "predicates": effectivePredicates,
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
        register(MemoryOSL2FindEntitiesTool(facade: facade))
        register(MemoryOSL2UpdateEntitiesTool(facade: facade))
        register(MemoryOSGetCurrentUserProfileTool(facade: facade))
        register(MemoryOSUpdateCurrentUserProfileTool(facade: facade))
        register(MemoryOSContextTool(facade: facade))
        register(MemoryOSSearchTool(facade: facade))
        register(MemoryOSQueryGraphTool(facade: facade))
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
