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

    public var description: String {
        switch self {
        case .toolNotAllowed(let name): "toolNotAllowed: \(name)"
        case .invalidArguments(let message): "invalidArguments: \(message)"
        }
    }
}

public struct MemoryOSBackgroundToolExecutor: @unchecked Sendable {
    public static let defaultAllowedToolNames: Set<String> = [
        "memory_os_search",
        "memory_os_read_record",
        "memory_os_read_provenance",
        "memory_os_trace_evidence",
        "memory_os_expand_l4",
        "memory_os_l4_find_entity",
        "memory_os_l4_neighbors"
    ]

    public var facade: AppMemoryOSFacade

    public init(facade: AppMemoryOSFacade) {
        self.facade = facade
    }

    public func execute(_ call: MemoryOSBackgroundToolCall, context: MemoryOSBackgroundToolExecutionContext) throws -> MemoryOSBackgroundToolResult {
        guard context.allowedToolNames.contains(call.name) else {
            throw MemoryOSBackgroundToolExecutionError.toolNotAllowed(call.name)
        }
        let args = try Arguments(json: call.argumentsJSON)
        switch call.name {
        case "memory_os_search":
            let query = try args.requiredString("query")
            let layers = args.stringArray("layers") ?? ["L2", "L3", "L4"]
            let limit = args.int("limit") ?? 20
            let retrievalLayers = layers.compactMap { MemoryOSRetrievalLayer(rawValue: $0.uppercased()) }
            let hits = try facade.searchMemoryOS(MemoryOSRetrievalQuery(text: query, layers: retrievalLayers.isEmpty ? [.l2, .l3, .l4] : retrievalLayers, limit: limit))
            let json = facade.store.json(hits)
            return MemoryOSBackgroundToolResult(callID: call.id, name: call.name, contentJSON: json, contentText: "Returned \(hits.count) Memory OS hits for \"\(query)\".", citations: hits.map(\.recordID))

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

        case "memory_os_trace_evidence":
            let spanIDs = args.stringArray("spanIDs") ?? []
            let statementIDs = args.stringArray("statementIDs") ?? []
            let beliefIDs = args.stringArray("beliefIDs") ?? []
            let limit = args.int("limit") ?? 100
            let graph = try facade.traceMemoryOSEvidence(spanIDs: spanIDs, statementIDs: statementIDs, beliefIDs: beliefIDs, limit: limit)
            return MemoryOSBackgroundToolResult(callID: call.id, name: call.name, contentJSON: facade.store.json(graph), contentText: "Traced evidence graph.", citations: spanIDs + statementIDs + beliefIDs)

        case "memory_os_expand_l4":
            let entityID = try args.requiredString("entityID")
            let depth = args.int("depth") ?? 1
            let limit = args.int("limit") ?? 20
            let hits = try facade.expandMemoryOSL4(entityID: entityID, depth: depth, limit: limit)
            return MemoryOSBackgroundToolResult(callID: call.id, name: call.name, contentJSON: facade.store.json(hits), contentText: "Expanded L4 entity \(entityID) to depth \(depth).", citations: [entityID] + hits.map(\.recordID))

        case "memory_os_l4_find_entity":
            let text = try args.requiredString("text")
            let limit = args.int("limit") ?? 20
            let graph = try facade.findMemoryOSL4Entity(text: text, limit: limit)
            return MemoryOSBackgroundToolResult(callID: call.id, name: call.name, contentJSON: facade.store.json(graph), contentText: "Found L4 entity candidates for \"\(text)\".", citations: [])

        case "memory_os_l4_neighbors":
            let entityID = try args.requiredString("entityID")
            let direction = args.string("direction").flatMap { MemoryOSGraphDirection(rawValue: $0) } ?? .both
            let predicates = args.stringArray("predicates") ?? []
            let limit = args.int("limit") ?? 100
            let graph = try facade.queryMemoryOSL4Neighbors(entityID: entityID, direction: direction, predicates: predicates, limit: limit)
            return MemoryOSBackgroundToolResult(callID: call.id, name: call.name, contentJSON: facade.store.json(graph), contentText: "Read L4 neighbors for \(entityID).", citations: [entityID])

        default:
            throw MemoryOSBackgroundToolExecutionError.toolNotAllowed(call.name)
        }
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
}
