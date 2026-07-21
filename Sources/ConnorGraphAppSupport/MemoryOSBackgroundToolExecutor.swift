import Foundation
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphStore

public struct MemoryOSBackgroundToolExecutionContext: Sendable, Equatable {
    public var runID: String
    public var iteration: Int
    public var allowedToolNames: Set<String>

    public init(runID: String, iteration: Int, allowedToolNames: Set<String> = MemoryOSBackgroundToolExecutor.defaultAllowedToolNames) {
        self.runID = runID
        self.iteration = iteration
        self.allowedToolNames = allowedToolNames
    }
}

public enum MemoryOSBackgroundToolExecutionError: Error, Sendable, Equatable, CustomStringConvertible {
    case toolNotAllowed(String)
    case invalidArguments(String)
    case toolExecutionFailed(String)

    public var description: String {
        switch self {
        case .toolNotAllowed(let name): "toolNotAllowed: \(name)"
        case .invalidArguments(let message): "invalidArguments: \(message)"
        case .toolExecutionFailed(let message): "toolExecutionFailed: \(message)"
        }
    }
}

private final class MemoryOSBackgroundContextCursorStore: @unchecked Sendable {
    private let lock = NSLock()
    private var deliveredByKey: [String: Set<String>] = [:]

    func response(
        runID: String,
        queryKey: String,
        query: String,
        requestedLimit: Int,
        candidates: [MemoryOSContextToolRecord],
        maxResponseCharacters: Int
    ) throws -> MemoryOSContextToolResponse {
        lock.lock()
        defer { lock.unlock() }

        let key = "\(runID)|\(queryKey)"
        var delivered = deliveredByKey[key] ?? []
        let target = candidates.prefix(requestedLimit).filter { !delivered.contains(Self.cursorID(for: $0)) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var selected: [MemoryOSContextToolRecord] = []
        var capacityPartial = false

        for record in target {
            let tentative = selected + [record]
            let response = MemoryOSContextToolResponse(
                query: query,
                requestedLimit: requestedLimit,
                returnedCount: tentative.count,
                cumulativeReturnedCount: delivered.count + tentative.count,
                hasMore: candidates.count > requestedLimit ? true : nil,
                partial: false,
                records: tentative
            )
            if try encoder.encode(response).count > maxResponseCharacters {
                capacityPartial = true
                break
            }
            selected = tentative
        }

        delivered.formUnion(selected.map(Self.cursorID))
        deliveredByKey[key] = delivered
        return MemoryOSContextToolResponse(
            query: query,
            requestedLimit: requestedLimit,
            returnedCount: selected.count,
            cumulativeReturnedCount: delivered.count,
            hasMore: candidates.count > requestedLimit || capacityPartial ? true : nil,
            partial: capacityPartial,
            records: selected
        )
    }

    private static func cursorID(for record: MemoryOSContextToolRecord) -> String {
        ([record.recordID] + record.path.map(\.recordID)).joined(separator: ">")
    }
}

public struct MemoryOSBackgroundToolExecutor: @unchecked Sendable {
    public static let defaultAllowedToolNames: Set<String> = [
        "memory_os_recent_context",
        "memory_os_knowledge_context",
        "memory_os_search",
        "memory_os_read_record",
        "memory_os_read_provenance",
        "memory_os_expand_l4",
        "memory_os_l4_find_entity",
        "memory_os_l4_neighbors",
        "memory_os_l2_update_entities",
        "memory_os_update_current_user_profile",
        "memory_os_l3_update_beliefs",
        "memory_os_l4_update_entities"
    ]

    public var facade: AppMemoryOSFacade
    public var contextToolConfiguration: MemoryOSContextToolConfiguration
    private let contextCursorStore: MemoryOSBackgroundContextCursorStore

    public init(
        facade: AppMemoryOSFacade,
        contextToolConfiguration: MemoryOSContextToolConfiguration = .init()
    ) {
        self.facade = facade
        self.contextToolConfiguration = contextToolConfiguration
        self.contextCursorStore = MemoryOSBackgroundContextCursorStore()
    }

    public func execute(_ call: MemoryOSBackgroundToolCall, context: MemoryOSBackgroundToolExecutionContext) throws -> MemoryOSBackgroundToolResult {
        guard context.allowedToolNames.contains(call.name) else {
            throw MemoryOSBackgroundToolExecutionError.toolNotAllowed(call.name)
        }
        let args = try Arguments(json: call.argumentsJSON)
        switch call.name {
        case "memory_os_recent_context", "memory_os_knowledge_context":
            let rawQuery = try args.requiredString("query")
            let terms = rawQuery.split { $0 == ";" || $0 == "\u{FF1B}" }.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard !terms.isEmpty else {
                throw MemoryOSBackgroundToolExecutionError.toolExecutionFailed("query contained no valid search terms")
            }
            let isRecent = call.name == "memory_os_recent_context"
            let requestedLimit = max(contextToolConfiguration.minimumResultLimit, args.int("limit") ?? contextToolConfiguration.defaultResultLimit)
            let depth = isRecent ? 1 : max(1, min(args.int("depth") ?? 1, contextToolConfiguration.maxDepth))
            let query = terms.joined(separator: " ")
            let layers: [MemoryOSRetrievalLayer] = isRecent ? [.l1, .l2] : [.l3, .l4]
            let hits = try facade.searchMemoryOS(.init(text: query, layers: layers, limit: requestedLimit + 1, depth: depth))
            var candidates = hits.map(MemoryOSLayeredContextSupport.record)
            if !isRecent {
                for hit in hits where hit.layer == .l4 && hit.canExpandDepth {
                    let entity = hit.title.isEmpty ? (hit.entityRefs.first ?? hit.recordID) : hit.title
                    candidates += MemoryOSLayeredContextSupport.records(
                        from: try facade.expandMemoryOSL4(entityName: entity, depth: depth, limit: requestedLimit + 1)
                    )
                }
                candidates.sort(by: Self.contextRecordPrecedes)
            }
            let queryKey = "\(query.lowercased())|\(layers.map(\.rawValue).joined(separator: ","))|\(depth)"
            let response = try contextCursorStore.response(
                runID: context.runID,
                queryKey: queryKey,
                query: query,
                requestedLimit: requestedLimit,
                candidates: candidates,
                maxResponseCharacters: contextToolConfiguration.maxResponseCharacters
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let jsonString = String(data: try encoder.encode(response), encoding: .utf8) ?? "{}"
            let citations = response.records.flatMap { [$0.recordID] + $0.path.map(\.recordID) }.reduce(into: [String]()) {
                if !$0.contains($1) { $0.append($1) }
            }
            return MemoryOSBackgroundToolResult(
                callID: call.id,
                name: call.name,
                contentJSON: jsonString,
                contentText: jsonString,
                citations: citations
            )

        case "memory_os_search":
            let query = try args.requiredString("query")
            let layers = args.stringArray("layers") ?? ["L2", "L3", "L4"]
            let limit = args.int("limit") ?? 20
            let retrievalLayers = layers.compactMap { MemoryOSRetrievalLayer(rawValue: $0.uppercased()) }
            let hits = try facade.searchMemoryOS(MemoryOSRetrievalQuery(text: query, layers: retrievalLayers.isEmpty ? [.l2, .l3, .l4] : retrievalLayers, limit: limit))
            let json = facade.store.json(hits)
            let readableText: String
            if hits.isEmpty {
                readableText = "Returned 0 Memory OS hits for \"\(query)\"."
            } else {
                let header = "Returned \(hits.count) Memory OS hits for \"\(query)\"."
                let body = hits.enumerated().map { i, hit -> String in
                    var parts = ["\(i + 1). [\(hit.layer.rawValue)] \(hit.title)"]
                    if !hit.summary.isEmpty { parts.append("   Summary: \(hit.summary)") }
                    if !hit.matchedText.isEmpty && hit.matchedText != hit.summary { parts.append("   Matched: \(hit.matchedText)") }
                    return parts.joined(separator: "\n")
                }.joined(separator: "\n\n")
                readableText = "\(header)\n\n\(body)"
            }
            return MemoryOSBackgroundToolResult(callID: call.id, name: call.name, contentJSON: json, contentText: readableText, citations: hits.map(\.recordID))

        case "memory_os_read_record":
            let layer = try args.requiredString("layer")
            let recordID = try args.requiredString("recordID")
            let json = try facade.readMemoryOSRecordJSON(layer: layer, recordID: recordID)
            return MemoryOSBackgroundToolResult(callID: call.id, name: call.name, contentJSON: json, contentText: "Read \(layer.uppercased()) record \(recordID).", citations: [recordID])

        case "memory_os_read_provenance":
            let provenanceObjectID = try args.requiredString("provenanceObjectID")
            let spanID = args.string("spanID")
            let json = try facade.readMemoryOSProvenanceJSON(provenanceObjectID: provenanceObjectID, spanID: spanID)
            return MemoryOSBackgroundToolResult(callID: call.id, name: call.name, contentJSON: json, contentText: "Read L0 provenance \(provenanceObjectID).", citations: [provenanceObjectID] + [spanID].compactMap { $0 })

        case "memory_os_expand_l4":
            let entityName = try args.requiredString("entityName")
            let depth = args.int("depth") ?? 5
            let limit = args.int("limit") ?? 200
            let hits = try facade.expandMemoryOSL4(entityName: entityName, depth: depth, limit: limit)
            if hits.isEmpty {
                return MemoryOSBackgroundToolResult(callID: call.id, name: call.name, contentJSON: "{}", contentText: "No L4 entity found matching '\(entityName)'.", citations: [])
            }
            let header = "Expanded L4 entity '\(entityName)' to depth \(depth): \(hits.count) hit(s)."
            let body = hits.enumerated().map { i, hit -> String in
                return "\(i + 1). \(hit.sourceEntityID) --[\(hit.predicate)]--> \(hit.relatedEntityID ?? "(self)") | \(hit.text) (depth: \(hit.depth))"
            }.joined(separator: "\n")
            return MemoryOSBackgroundToolResult(callID: call.id, name: call.name, contentJSON: facade.store.json(hits), contentText: "\(header)\n\n\(body)", citations: hits.map(\.recordID))

        case "memory_os_l4_find_entity":
            let text = try args.requiredString("text")
            let limit = args.int("limit") ?? 20
            let graph = try facade.findMemoryOSL4Entity(text: text, limit: limit)
            let readableText: String
            if graph.nodes.isEmpty {
                readableText = "Found 0 L4 entity candidates for \"\(text)\"."
            } else {
                let header = "Found \(graph.nodes.count) L4 entity candidate(s) for \"\(text)\"."
                let body = graph.nodes.enumerated().map { i, node -> String in
                    return "\(i + 1). [\(node.kind)] \(node.title): \(node.summary.isEmpty ? "(no summary)" : node.summary)"
                }.joined(separator: "\n")
                readableText = "\(header)\n\n\(body)"
            }
            return MemoryOSBackgroundToolResult(callID: call.id, name: call.name, contentJSON: facade.store.json(graph), contentText: readableText, citations: [])

        case "memory_os_l4_neighbors":
            let entityID = try args.requiredString("entityID")
            let direction = args.string("direction").flatMap { MemoryOSGraphDirection(rawValue: $0) } ?? .both
            let predicates = args.stringArray("predicates") ?? []
            let limit = args.int("limit") ?? 100
            let graph = try facade.queryMemoryOSL4Neighbors(entityID: entityID, direction: direction, predicates: predicates, limit: limit)
            let nodeMap = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })
            let readableText: String
            if graph.edges.isEmpty {
                readableText = "L4 neighbors for \(entityID): 0 edges."
            } else {
                let header = "L4 neighbors for \(entityID): \(graph.edges.count) edge(s)."
                let body = graph.edges.enumerated().map { i, edge -> String in
                    let sourceName = nodeMap[edge.sourceID]?.title ?? edge.sourceID
                    let targetName = nodeMap[edge.targetID]?.title ?? edge.targetID
                    return "\(i + 1). \(sourceName) --[\(edge.predicate)]--> \(targetName)"
                }.joined(separator: "\n")
                readableText = "\(header)\n\n\(body)"
            }
            return MemoryOSBackgroundToolResult(callID: call.id, name: call.name, contentJSON: facade.store.json(graph), contentText: readableText, citations: [entityID])

        case "memory_os_l2_update_entities":
            let requestData = try JSONSerialization.data(withJSONObject: args.jsonCompatible(), options: [.sortedKeys])
            let request = try JSONDecoder().decode(MemoryOSL2UpdateEntitiesRequest.self, from: requestData)
            let result = try facade.updateMemoryOSL2Entities(request)
            let resultData = try JSONEncoder().encode(result)
            let resultJSON = String(data: resultData, encoding: .utf8) ?? "{}"
            return MemoryOSBackgroundToolResult(callID: call.id, name: call.name, contentJSON: resultJSON, contentText: "Updated \(result.updatedEntities.count) L2 entit(ies).", citations: [])

        case "memory_os_update_current_user_profile":
            let facts = try args.requiredArray("facts")
            let now = Date()
            let anchor = try facade.ensureCurrentUserAnchor(now: now)
            var statementIDs: [String] = []
            var artifactIDs: [String] = []
            var acceptanceModes: [String] = []
            for (index, factValue) in facts.enumerated() {
                guard let factObj = factValue as? [String: Any],
                      let statement = factObj["statement"] as? String, !statement.isEmpty,
                      let factType = factObj["factType"] as? String, !factType.isEmpty,
                      let rawRelation = factObj["relation"] as? String, !rawRelation.isEmpty else {
                    throw MemoryOSBackgroundToolExecutionError.invalidArguments("facts[\(index)] must have statement, factType, and relation")
                }
                let predicate = MemoryOSCanonicalizer.canonicalizeGraphPredicate(rawRelation) ?? .relatedTo
                let normalizedFactType = MemoryOSCanonicalizer.canonicalizeL2FactType(factType) ?? factType
                let artifactJSON = try Self.buildCurrentUserFactJSON(statement: statement, factType: normalizedFactType, predicate: predicate, anchor: anchor, now: now)
                let summary = try facade.projectAndRecordLLMArtifact(rawContent: artifactJSON, modelID: "memory_os_update_current_user_profile", processingRunID: context.runID, artifactType: "memory_os_current_user_fact_update", schemaName: "MemoryOSL1UnifiedProjectionOutput", now: now)
                artifactIDs.append(summary.artifactID)
                guard summary.accepted else {
                    throw MemoryOSBackgroundToolExecutionError.invalidArguments("Current user fact rejected: \(summary.issues.map(\.message).joined(separator: "; "))")
                }
                statementIDs.append(contentsOf: try facade.l2StatementIDs(sourceArtifactID: summary.artifactID))
                acceptanceModes.append(summary.acceptanceMode)
            }
            let payload: [String: Any] = ["accepted": true, "statementCount": statementIDs.count, "artifactCount": artifactIDs.count, "acceptanceModes": acceptanceModes]
            let resultData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            let resultJSON = String(data: resultData, encoding: .utf8) ?? "{}"
            return MemoryOSBackgroundToolResult(callID: call.id, name: call.name, contentJSON: resultJSON, contentText: "Updated current_user profile with \(statementIDs.count) statement(s).", citations: statementIDs + artifactIDs)

        case "memory_os_l3_update_beliefs":
            let beliefsArray = try args.requiredArray("beliefs")
            let beliefs = try JSONDecoder().decode([MemoryOSL3BeliefInput].self, from: try JSONSerialization.data(withJSONObject: beliefsArray, options: [.sortedKeys]))
            let result = try facade.writeMemoryOSL3Beliefs(beliefs)
            let resultData = try JSONEncoder().encode(result)
            let resultJSON = String(data: resultData, encoding: .utf8) ?? "{}"
            return MemoryOSBackgroundToolResult(callID: call.id, name: call.name, contentJSON: resultJSON, contentText: "Created \(result.createdBeliefCount) L3 belief(s).", citations: [])

        case "memory_os_l4_update_entities":
            let entitiesArray = args.array("entities") ?? []
            let relationsArray = args.array("relations") ?? []
            let entities = try JSONDecoder().decode([MemoryOSL4EntityInput].self, from: try JSONSerialization.data(withJSONObject: entitiesArray, options: [.sortedKeys]))
            let relations = try JSONDecoder().decode([MemoryOSL4RelationInput].self, from: try JSONSerialization.data(withJSONObject: relationsArray, options: [.sortedKeys]))
            let result = try facade.writeMemoryOSL4Entities(entities: entities, relations: relations)
            let resultData = try JSONEncoder().encode(result)
            let resultJSON = String(data: resultData, encoding: .utf8) ?? "{}"
            return MemoryOSBackgroundToolResult(callID: call.id, name: call.name, contentJSON: resultJSON, contentText: "Created \(result.createdEntityCount) L4 entit(ies) and \(result.createdRelationCount) relation(s).", citations: [])

        default:
            throw MemoryOSBackgroundToolExecutionError.toolNotAllowed(call.name)
        }
    }

    private static func contextRecordPrecedes(_ lhs: MemoryOSContextToolRecord, _ rhs: MemoryOSContextToolRecord) -> Bool {
        switch (lhs.updatedAt, rhs.updatedAt) {
        case let (left?, right?) where left != right: return left > right
        case (_?, nil): return true
        case (nil, _?): return false
        default: break
        }
        if lhs.retrievalScore != rhs.retrievalScore { return lhs.retrievalScore > rhs.retrievalScore }
        return lhs.recordID < rhs.recordID
    }

    private static func buildCurrentUserFactJSON(statement: String, factType: String, predicate: GraphPredicate, anchor: MemoryOSEntity, now: Date) throws -> String {
        let localID = "current_user"
        var statementMetadata: [String: String] = [
            "l2_fact_type": factType,
            "person_role": "current_user",
            "person_resolution": "resolved",
            "identity_anchor": "current_user",
            "identity_anchor_id": anchor.id,
            "source_stage": "background_pipeline"
        ]
        if factType == "profile_preference" {
            statementMetadata["profile_dimension"] = "fact_statement"
        }
        let output = MemoryOSL1UnifiedProjectionOutput(
            operationalEntities: [GraphStructuredExtractedEntity(
                localID: localID,
                name: "Current User",
                entityKind: .personObject,
                scope: .personal,
                aliases: [],
                summary: "The human currently operating this Connor installation.",
                confidence: 0.99,
                evidenceSpanIDs: [],
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
                explicitID: "current-user-fact-\(UUID().uuidString)",
                subjectLocalID: localID,
                predicate: predicate,
                objectLocalID: localID,
                statementText: statement,
                confidence: 0.9,
                validAt: now,
                referenceTime: now,
                evidenceSpanIDs: [],
                metadata: statementMetadata
            )],
            evidenceSpans: [],
            knowledgeCandidates: [],
            conceptEntities: [],
            conceptRelations: [],
            promotionDecisions: [],
            warnings: [],
            metadata: [
                "schema_purpose": "current_user_fact_update",
                "person_role": "current_user",
                "identity_anchor_id": anchor.id
            ]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(output)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

private struct Arguments {
    var values: [String: Any]

    init(json: String) throws {
        guard let data = json.data(using: .utf8) else { throw MemoryOSBackgroundToolExecutionError.invalidArguments("Invalid UTF-8") }
        let object = try JSONSerialization.jsonObject(with: data)
        guard let values = object as? [String: Any] else { throw MemoryOSBackgroundToolExecutionError.invalidArguments("Expected JSON object") }
        self.values = values
    }

    func string(_ key: String) -> String? {
        values[key] as? String
    }

    func requiredString(_ key: String) throws -> String {
        guard let value = string(key), !value.isEmpty else { throw MemoryOSBackgroundToolExecutionError.invalidArguments("Missing required string: \(key)") }
        return value
    }

    func int(_ key: String) -> Int? {
        if let value = values[key] as? Int { return value }
        if let value = values[key] as? NSNumber { return value.intValue }
        if let value = values[key] as? String { return Int(value) }
        return nil
    }

    func stringArray(_ key: String) -> [String]? {
        if let values = values[key] as? [String] { return values }
        if let values = values[key] as? [Any] { return values.compactMap { $0 as? String } }
        if let value = values[key] as? String { return value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
        return nil
    }

    func requiredArray(_ key: String) throws -> [Any] {
        guard let values = values[key] as? [Any], !values.isEmpty else {
            throw MemoryOSBackgroundToolExecutionError.invalidArguments("Missing required array: \(key)")
        }
        return values
    }

    func array(_ key: String) -> [Any]? {
        values[key] as? [Any]
    }

    func jsonCompatible() -> [String: Any] {
        values
    }
}
