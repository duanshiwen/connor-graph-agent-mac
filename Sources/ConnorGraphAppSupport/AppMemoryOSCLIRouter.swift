import Foundation
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphStore

public enum AppMemoryOSCLIRouter {
    public static func route(args: [String], inspector: AppMemoryOSCLIInspector, encoder: JSONEncoder) throws -> String {
        let command = args.first ?? "status"
        switch command {
        case "status":
            return try encode(try inspector.status(), encoder: encoder)
        case "stats":
            return try encode(try inspector.stats(), encoder: encoder)
        case "layers":
            return try encode(try inspector.layers(), encoder: encoder)
        case "l0":
            return try routeL0(args: Array(args.dropFirst()), inspector: inspector, encoder: encoder)
        case "l1":
            return try routeL1(args: Array(args.dropFirst()), inspector: inspector, encoder: encoder)
        case "l2":
            return try routeL2(args: Array(args.dropFirst()), inspector: inspector, encoder: encoder)
        case "l3":
            return try routeL3(args: Array(args.dropFirst()), inspector: inspector, encoder: encoder)
        case "l4":
            return try routeL4(args: Array(args.dropFirst()), inspector: inspector, encoder: encoder)
        case "read":
            let values = Array(args.dropFirst())
            guard values.count >= 2 else { return try encode(MemoryOSCLIError(error: "missing_layer_or_id", usage: "connor memory read <layer> <id>"), encoder: encoder) }
            guard let record = try inspector.read(layer: values[0], id: values[1]) else {
                return try encode(MemoryOSCLIError(error: "record_not_found", usage: "connor memory read <layer> <id>"), encoder: encoder)
            }
            return try encode(record, encoder: encoder)
        case "search":
            guard let query = args.dropFirst().first, !query.hasPrefix("--") else {
                return try encode(MemoryOSCLIError(error: "missing_query", usage: "connor memory search <query> [--layers L2,L3,L4] [--limit N]"), encoder: encoder)
            }
            return try encode(try inspector.search(query: query, layers: optionValue("--layers", in: args).map(splitCSV) ?? [], limit: intOption("--limit", in: args, default: 20)), encoder: encoder)
        case "search-index":
            return try routeSearchIndex(args: Array(args.dropFirst()), inspector: inspector, encoder: encoder)
        case "query-graph":
            let values = Array(args.dropFirst())
            let text = values.first.flatMap { $0.hasPrefix("--") ? nil : $0 } ?? ""
            let intent = optionValue("--intent", in: args).flatMap(MemoryOSGraphQueryIntent.init(rawValue:)) ?? .auto
            let direction = optionValue("--direction", in: args).flatMap(MemoryOSGraphDirection.init(rawValue:)) ?? .both
            return try encode(
                try inspector.queryGraph(
                    text: text,
                    intent: intent,
                    entityID: optionValue("--entity", in: args),
                    classEntityIDs: optionValue("--class", in: args).map(splitCSV) ?? [],
                    predicates: optionValue("--predicate", in: args).map(splitCSV) ?? [],
                    direction: direction,
                    includeEvidence: args.contains("--include-evidence"),
                    limit: intOption("--limit", in: args, default: 50)
                ),
                encoder: encoder
            )
        case "trace":
            return try routeTrace(args: Array(args.dropFirst()), inspector: inspector, encoder: encoder)
        case "queue":
            return try encode(try inspector.queue(limit: intOption("--limit", in: args, default: 20), status: optionValue("--status", in: args), kind: optionValue("--kind", in: args)), encoder: encoder)
        case "runs":
            return try encode(try inspector.runs(limit: intOption("--limit", in: args, default: 20)), encoder: encoder)
        case "run":
            return try routeRun(args: Array(args.dropFirst()), inspector: inspector, encoder: encoder)
        case "debug-reset-foundation-kg":
            return try encode(try debugResetFoundationKG(), encoder: encoder)
        case "pipeline":
            return try routePipeline(args: Array(args.dropFirst()), inspector: inspector, encoder: encoder)
        default:
            return try encode(MemoryOSCLIError(error: "unknown_memory_command", usage: "connor memory status|search|query-graph|l0|l1|l2|l3|l4|trace|search-index|queue|runs|run|pipeline"), encoder: encoder)
        }
    }

    public static func makeLiveInspector() throws -> AppMemoryOSCLIInspector {
        let paths = try AppStoragePaths.live()
        try paths.ensureDirectoryHierarchy()
        if let builtinURL = builtinFoundationKGDatabaseURLFromEnvironment() {
            _ = try FoundationKGBuiltinBootstrapper.ensureBuiltinDatabaseIfNeeded(memoryOSDatabaseURL: paths.memoryOSDatabaseURL, builtinDatabaseURL: builtinURL)
        }
        let store = try SQLiteMemoryOSStore(path: paths.memoryOSDatabaseURL.path)
        try store.migrate()
        try AppMemoryOSFacade(store: store).ensureCurrentUserAnchor()
        let isExplicitSearchIndexRebuild = CommandLine.arguments.dropFirst().elementsEqual(["memory", "search-index", "rebuild"])
        let searchKernel = isExplicitSearchIndexRebuild
            ? try AppMemoryOSSearchKernelFactory.makeLiveWithoutRebuild(paths: paths)
            : try AppMemoryOSSearchKernelFactory.makeLiveIfHealthy(paths: paths)
        return AppMemoryOSCLIInspector(store: store, databasePath: paths.memoryOSDatabaseURL.path, searchKernel: searchKernel)
    }

    private static func routeL0(args: [String], inspector: AppMemoryOSCLIInspector, encoder: JSONEncoder) throws -> String {
        switch args.first ?? "objects" {
        case "objects": return try encode(try inspector.listL0Objects(limit: intOption("--limit", in: args, default: 20)), encoder: encoder)
        case "spans": return try encode(try inspector.listL0Spans(limit: intOption("--limit", in: args, default: 20)), encoder: encoder)
        default: return try encode(MemoryOSCLIError(error: "unknown_l0_command", usage: "connor memory l0 objects|spans"), encoder: encoder)
        }
    }

    private static func routeL1(args: [String], inspector: AppMemoryOSCLIInspector, encoder: JSONEncoder) throws -> String {
        switch args.first ?? "pending" {
        case "pending": return try encode(try inspector.listL1Pending(limit: intOption("--limit", in: args, default: 20)), encoder: encoder)
        default: return try encode(MemoryOSCLIError(error: "unknown_l1_command", usage: "connor memory l1 pending"), encoder: encoder)
        }
    }

    private static func routeL2(args: [String], inspector: AppMemoryOSCLIInspector, encoder: JSONEncoder) throws -> String {
        switch args.first ?? "statements" {
        case "statements": return try encode(try inspector.listL2Statements(limit: intOption("--limit", in: args, default: 20)), encoder: encoder)
        case "pending-knowledge": return try encode(try inspector.listL2PendingKnowledge(limit: intOption("--limit", in: args, default: 20)), encoder: encoder)
        case "find":
            let text = args.dropFirst().first.flatMap { $0.hasPrefix("--") ? nil : $0 } ?? ""
            return try encode(
                try inspector.findL2Statements(
                    text: text,
                    subjectID: optionValue("--subject", in: args),
                    predicates: optionValue("--predicate", in: args).map(splitCSV) ?? [],
                    limit: intOption("--limit", in: args, default: 50)
                ),
                encoder: encoder
            )
        default: return try encode(MemoryOSCLIError(error: "unknown_l2_command", usage: "connor memory l2 statements|pending-knowledge|find [text] [--subject id] [--predicate p1,p2] [--limit N]"), encoder: encoder)
        }
    }

    private static func routeL3(args: [String], inspector: AppMemoryOSCLIInspector, encoder: JSONEncoder) throws -> String {
        switch args.first ?? "beliefs" {
        case "beliefs": return try encode(try inspector.listL3Beliefs(limit: intOption("--limit", in: args, default: 20)), encoder: encoder)
        case "expand":
            let text = args.dropFirst().first.flatMap { $0.hasPrefix("--") ? nil : $0 } ?? ""
            return try encode(
                try inspector.expandL3Belief(
                    beliefID: optionValue("--belief", in: args),
                    topic: optionValue("--topic", in: args),
                    text: text,
                    limit: intOption("--limit", in: args, default: 20)
                ),
                encoder: encoder
            )
        default: return try encode(MemoryOSCLIError(error: "unknown_l3_command", usage: "connor memory l3 beliefs|expand [text] [--belief id] [--topic topic] [--limit N]"), encoder: encoder)
        }
    }

    private static func routeL4(args: [String], inspector: AppMemoryOSCLIInspector, encoder: JSONEncoder) throws -> String {
        switch args.first ?? "entities" {
        case "entities":
            return try encode(try inspector.listL4Entities(limit: intOption("--limit", in: args, default: 20)), encoder: encoder)
        case "predicates":
            return try encode(inspector.listL4Predicates(), encoder: encoder)
        case "find":
            guard let text = args.dropFirst().first, !text.hasPrefix("--") else {
                return try encode(MemoryOSCLIError(error: "missing_entity_query", usage: "connor memory l4 find <text> [--limit N]"), encoder: encoder)
            }
            return try encode(try inspector.findL4Entity(text: text, limit: intOption("--limit", in: args, default: 20)), encoder: encoder)
        case "neighbors":
            guard let entityID = args.dropFirst().first, !entityID.hasPrefix("--") else {
                return try encode(MemoryOSCLIError(error: "missing_entity_id", usage: "connor memory l4 neighbors <entity-id> [--direction outgoing|incoming|both] [--predicate INSTANCE_OF,HAS_PART] [--limit N]"), encoder: encoder)
            }
            let direction = optionValue("--direction", in: args).flatMap(MemoryOSGraphDirection.init(rawValue:)) ?? .both
            return try encode(try inspector.listL4Neighbors(entityID: entityID, direction: direction, predicates: optionValue("--predicate", in: args).map(splitCSV) ?? [], limit: intOption("--limit", in: args, default: 100)), encoder: encoder)
        case "instances":
            guard let classIDs = args.dropFirst().first, !classIDs.hasPrefix("--") else {
                return try encode(MemoryOSCLIError(error: "missing_class_entity_ids", usage: "connor memory l4 instances <class-id[,class-id...]> [--predicate INSTANCE_OF] [--limit N]"), encoder: encoder)
            }
            return try encode(
                try inspector.listL4Instances(
                    classEntityIDs: splitCSV(classIDs),
                    predicates: optionValue("--predicate", in: args).map(splitCSV) ?? [MemoryOSL4RelationPredicate.instanceOf.rawValue],
                    limit: intOption("--limit", in: args, default: 100)
                ),
                encoder: encoder
            )
        default:
            return try encode(MemoryOSCLIError(error: "unknown_l4_command", usage: "connor memory l4 entities|predicates|find|neighbors|instances"), encoder: encoder)
        }
    }

    private static func routeSearchIndex(args: [String], inspector: AppMemoryOSCLIInspector, encoder: JSONEncoder) throws -> String {
        switch args.first ?? "stats" {
        case "stats": return try encode(try inspector.searchIndexStats(), encoder: encoder)
        case "verify": return try encode(try inspector.verifySearchIndex(), encoder: encoder)
        case "rebuild": return try encode(try inspector.rebuildSearchIndex(), encoder: encoder)
        default: return try encode(MemoryOSCLIError(error: "unknown_search_index_command", usage: "connor memory search-index stats|verify|rebuild"), encoder: encoder)
        }
    }

    private static func routeTrace(args: [String], inspector: AppMemoryOSCLIInspector, encoder: JSONEncoder) throws -> String {
        switch args.first ?? "evidence" {
        case "evidence":
            return try encode(
                try inspector.traceEvidence(
                    spanIDs: optionValue("--span", in: args).map(splitCSV) ?? [],
                    statementIDs: optionValue("--statement", in: args).map(splitCSV) ?? [],
                    beliefIDs: optionValue("--belief", in: args).map(splitCSV) ?? [],
                    limit: intOption("--limit", in: args, default: 100)
                ),
                encoder: encoder
            )
        default: return try encode(MemoryOSCLIError(error: "unknown_trace_command", usage: "connor memory trace evidence [--span id[,id]] [--statement id[,id]] [--belief id[,id]] [--limit N]"), encoder: encoder)
        }
    }

    private static func routeRun(args: [String], inspector: AppMemoryOSCLIInspector, encoder: JSONEncoder) throws -> String {
        guard let runID = args.first, !runID.hasPrefix("--") else {
            return try encode(MemoryOSCLIError(error: "missing_run_id", usage: "connor memory run <run-id> [messages|tool-calls]"), encoder: encoder)
        }
        switch args.dropFirst().first ?? "messages" {
        case "messages":
            return try encode(try inspector.runMessages(runID: runID), encoder: encoder)
        case "tool-calls":
            return try encode(try inspector.runToolCalls(runID: runID), encoder: encoder)
        default:
            return try encode(MemoryOSCLIError(error: "unknown_run_command", usage: "connor memory run <run-id> [messages|tool-calls]"), encoder: encoder)
        }
    }

    private static func routePipeline(args: [String], inspector: AppMemoryOSCLIInspector, encoder: JSONEncoder) throws -> String {
        switch args.first ?? "policy" {
        case "policy": return try encode(inspector.pipelinePolicy(), encoder: encoder)
        case "plan-l1", "plan-l1-knowledge": return try encode(try inspector.planL1(), encoder: encoder)
        case "plan-l2", "plan-l2-knowledge": return try encode(try inspector.planL2(), encoder: encoder)
        default: return try encode(MemoryOSCLIError(error: "unknown_pipeline_command", usage: "connor memory pipeline policy|plan-l1-knowledge|plan-l2-knowledge"), encoder: encoder)
        }
    }

    private static func debugResetFoundationKG() throws -> [String: String] {
        guard let builtinURL = builtinFoundationKGDatabaseURLFromEnvironment() else {
            return ["error": "missing_builtin_foundation_kg", "usage": "Set CONNOR_BUILTIN_FOUNDATION_KG_SQLITE=/path/to/FoundationKG-Builtin-L4.sqlite"]
        }
        let paths = try AppStoragePaths.live()
        try paths.ensureDirectoryHierarchy()
        try FoundationKGBuiltinBootstrapper.resetToBuiltinDatabase(memoryOSDatabaseURL: paths.memoryOSDatabaseURL, builtinDatabaseURL: builtinURL)
        let store = try SQLiteMemoryOSStore(path: paths.memoryOSDatabaseURL.path)
        try store.migrate()
        let entityCount = try store.query(sql: "SELECT COUNT(*) FROM memory_l4_entities;").first?.first ?? "0"
        let statementCount = try store.query(sql: "SELECT COUNT(*) FROM memory_l4_entity_statements;").first?.first ?? "0"
        return [
            "status": "reset",
            "database_path": paths.memoryOSDatabaseURL.path,
            "builtin_path": builtinURL.path,
            "l4_entities": entityCount,
            "l4_statements": statementCount
        ]
    }

    private static func builtinFoundationKGDatabaseURLFromEnvironment() -> URL? {
        if let path = ProcessInfo.processInfo.environment["CONNOR_BUILTIN_FOUNDATION_KG_SQLITE"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        if let bundled = FoundationKGBuiltinBootstrapper.builtinDatabaseURL() { return bundled }
        let developmentResource = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/ConnorGraphAgentMac/Resources/FoundationKG/FoundationKG-Builtin-L4.sqlite")
        if FileManager.default.fileExists(atPath: developmentResource.path) { return developmentResource }
        return nil
    }

    private static func encode<T: Encodable>(_ value: T, encoder: JSONEncoder) throws -> String {
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    private static func optionValue(_ name: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: name), args.indices.contains(args.index(after: index)) else { return nil }
        return args[args.index(after: index)]
    }

    private static func intOption(_ name: String, in args: [String], default defaultValue: Int) -> Int {
        optionValue(name, in: args).flatMap(Int.init) ?? defaultValue
    }

    private static func splitCSV(_ value: String) -> [String] {
        value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

public struct MemoryOSCLIError: Codable, Sendable, Equatable {
    public var error: String
    public var usage: String
}
