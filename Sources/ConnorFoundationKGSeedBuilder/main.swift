import Foundation
import SQLite3
import ConnorGraphAppSupport
import ConnorGraphCore
import ConnorGraphStore

struct FoundationKGSeedBuildReport: Codable {
    var inputPath: String
    var outputPath: String
    var manifestPath: String
    var nodesImported: Int
    var edgesImported: Int
    var externalIDsImported: Int
    var aliasesLoaded: Int
    var skippedEdges: Int
    var builtAt: String
}

struct Arguments {
    var input: String?
    var output: String?
    var manifest: String?
    var limitNodes: Int?
    var limitEdges: Int?
    var limitExternalIDs: Int?

    init(_ args: [String]) {
        var index = 0
        while index < args.count {
            let arg = args[index]
            func nextValue() -> String? {
                guard index + 1 < args.count else { return nil }
                index += 1
                return args[index]
            }
            switch arg {
            case "--input": input = nextValue()
            case "--output": output = nextValue()
            case "--manifest": manifest = nextValue()
            case "--limit-nodes": limitNodes = nextValue().flatMap(Int.init)
            case "--limit-edges": limitEdges = nextValue().flatMap(Int.init)
            case "--limit-external-ids": limitExternalIDs = nextValue().flatMap(Int.init)
            default: break
            }
            index += 1
        }
    }
}

let arguments = Arguments(Array(CommandLine.arguments.dropFirst()))
guard let input = arguments.input, let output = arguments.output, let manifest = arguments.manifest else {
    print("usage: ConnorFoundationKGSeedBuilder --input <foundation-kg-output-dir> --output <sqlite-path> --manifest <manifest-json> [--limit-nodes N] [--limit-edges N] [--limit-external-ids N]")
    Foundation.exit(2)
}

let report = try FoundationKGSeedBuilder.build(input: URL(fileURLWithPath: input), output: URL(fileURLWithPath: output), manifest: URL(fileURLWithPath: manifest), limitNodes: arguments.limitNodes, limitEdges: arguments.limitEdges, limitExternalIDs: arguments.limitExternalIDs)
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
print(String(decoding: try encoder.encode(report), as: UTF8.self))

enum FoundationKGSeedBuilder {
    static func build(input: URL, output: URL, manifest: URL, limitNodes: Int?, limitEdges: Int?, limitExternalIDs: Int?) throws -> FoundationKGSeedBuildReport {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: output.path) { try fileManager.removeItem(at: output) }
        let store = try SQLiteMemoryOSStore(path: output.path)
        try store.migrate()
        let builtAt = Date()
        let writer = try FoundationKGSeedSQLiteWriter(path: output.path)

        let aliases = try loadAliases(input.appendingPathComponent("aliases.jsonl"))
        let propertyNames = try loadPropertyNames(input.appendingPathComponent("properties.jsonl"))
        var entityNames: [String: String] = [:]
        var entityIDs = Set<String>()
        var nodesImported = 0
        var edgesImported = 0
        var skippedEdges = 0
        var externalIDsImported = 0

        try writer.exec("PRAGMA foreign_keys = OFF;")
        try writer.exec("PRAGMA synchronous = NORMAL;")
        try writer.exec("BEGIN IMMEDIATE TRANSACTION;")
        do {
            try forEachJSONL(input.appendingPathComponent("nodes.jsonl"), as: FoundationKGNodeRecord.self, limit: limitNodes) { node in
                let entity = FoundationKGMemoryOSMapper.mapEntity(node, supplementalAliases: aliases[node.id] ?? [], builtAt: builtAt)
                try writer.insert(entity: entity)
                entityNames[node.id] = entity.name
                entityIDs.insert(node.id)
                nodesImported += 1
            }

            try forEachJSONL(input.appendingPathComponent("edges.jsonl"), as: FoundationKGEdgeRecord.self, limit: limitEdges) { edge in
                guard entityIDs.contains(edge.sourceID) else {
                    skippedEdges += 1
                    return
                }
                let targetID = edge.targetID ?? edge.value ?? ""
                let statement = FoundationKGMemoryOSMapper.mapEdgeStatement(
                    edge,
                    sourceName: entityNames[edge.sourceID] ?? edge.sourceID,
                    propertyName: propertyNames[edge.predicate],
                    targetName: entityNames[targetID],
                    targetExists: entityIDs.contains(targetID),
                    builtAt: builtAt
                )
                if let statement {
                    try writer.insert(statement: statement)
                    edgesImported += 1
                } else {
                    skippedEdges += 1
                }
            }

            try forEachJSONL(input.appendingPathComponent("external_ids.jsonl"), as: FoundationKGExternalIDRecord.self, limit: limitExternalIDs) { externalID in
                guard entityIDs.contains(externalID.nodeID) else { return }
                let statement = FoundationKGMemoryOSMapper.mapExternalIDStatement(
                    externalID,
                    sourceName: entityNames[externalID.nodeID] ?? externalID.nodeID,
                    propertyName: propertyNames[externalID.property],
                    builtAt: builtAt
                )
                try writer.insert(statement: statement)
                externalIDsImported += 1
            }

            try writer.insertBuiltinDataset(
                id: FoundationKGMemoryOSMapper.builtinDatasetID,
                kind: "foundation_kg",
                version: FoundationKGMemoryOSMapper.sourceVersion,
                installedAt: builtAt,
                manifest: ["input_path": input.path],
                stats: [
                    "nodes_imported": String(nodesImported),
                    "edges_imported": String(edgesImported),
                    "external_ids_imported": String(externalIDsImported),
                    "aliases_loaded": String(aliases.values.reduce(0) { $0 + $1.count }),
                    "skipped_edges": String(skippedEdges)
                ]
            )
            try writer.exec("COMMIT;")
        } catch {
            try? writer.exec("ROLLBACK;")
            throw error
        }
        try writer.exec("PRAGMA wal_checkpoint(TRUNCATE);")
        try writer.exec("VACUUM;")

        let report = FoundationKGSeedBuildReport(
            inputPath: input.path,
            outputPath: output.path,
            manifestPath: manifest.path,
            nodesImported: nodesImported,
            edgesImported: edgesImported,
            externalIDsImported: externalIDsImported,
            aliasesLoaded: aliases.values.reduce(0) { $0 + $1.count },
            skippedEdges: skippedEdges,
            builtAt: ISO8601DateFormatter().string(from: builtAt)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: manifest)
        return report
    }

    static func loadAliases(_ url: URL) throws -> [String: [String]] {
        var aliases: [String: [String]] = [:]
        struct AliasRecord: Decodable { var node_id: String; var alias: String }
        try forEachJSONL(url, as: AliasRecord.self, limit: nil) { row in
            aliases[row.node_id, default: []].append(row.alias)
        }
        return aliases
    }

    static func loadPropertyNames(_ url: URL) throws -> [String: String] {
        var names: [String: String] = [:]
        try forEachJSONL(url, as: FoundationKGNodeRecord.self, limit: nil) { node in
            names[node.id] = FoundationKGMemoryOSMapper.mapEntity(node).name
        }
        return names
    }

    static func forEachJSONL<T: Decodable>(_ url: URL, as type: T.Type, limit: Int?, body: (T) throws -> Void) throws {
        let data = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        var count = 0
        for line in data.split(separator: "\n", omittingEmptySubsequences: true) {
            if let limit, count >= limit { break }
            let value = try decoder.decode(T.self, from: Data(line.utf8))
            try body(value)
            count += 1
        }
    }
}

final class FoundationKGSeedSQLiteWriter {
    private var db: OpaquePointer?
    private let encoder = JSONEncoder()
    private let isoFormatter = ISO8601DateFormatter()

    init(path: String) throws {
        encoder.outputFormatting = [.sortedKeys]
        guard sqlite3_open(path, &db) == SQLITE_OK else { throw error("open") }
    }

    deinit { sqlite3_close(db) }

    func exec(_ sql: String) throws {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK { throw error(sql) }
    }

    func insert(entity: MemoryOSEntity) throws {
        try prepared("""
        INSERT OR REPLACE INTO memory_l4_entities
        (id, stable_key, entity_type, name, aliases_json, summary, confidence, created_at, updated_at, valid_from, metadata_json)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """) { statement in
            bind(statement, 1, entity.id)
            bind(statement, 2, entity.stableKey)
            bind(statement, 3, entity.entityType)
            bind(statement, 4, entity.name)
            bind(statement, 5, json(entity.aliases))
            bind(statement, 6, entity.summary)
            sqlite3_bind_double(statement, 7, entity.confidence)
            bind(statement, 8, iso(entity.createdAt))
            bind(statement, 9, iso(entity.updatedAt))
            bind(statement, 10, entity.validFrom.map(iso))
            bind(statement, 11, json(entity.metadata))
            try step(statement)
        }
        for alias in entity.aliases {
            try prepared("""
            INSERT OR REPLACE INTO memory_l4_entity_aliases(id, entity_id, alias, normalized_alias, created_at, metadata_json)
            VALUES (?, ?, ?, ?, ?, '{}')
            """) { statement in
                bind(statement, 1, "\(entity.id):alias:\(alias)")
                bind(statement, 2, entity.id)
                bind(statement, 3, alias)
                bind(statement, 4, alias.lowercased())
                bind(statement, 5, iso(entity.createdAt))
                try step(statement)
            }
        }
        try prepared("""
        INSERT INTO memory_l4_entities_fts(entity_id, entity_type, name, aliases, summary)
        VALUES (?, ?, ?, ?, ?)
        """) { statement in
            bind(statement, 1, entity.id)
            bind(statement, 2, entity.entityType)
            bind(statement, 3, entity.name)
            bind(statement, 4, entity.aliases.joined(separator: " "))
            bind(statement, 5, entity.summary)
            try step(statement)
        }
    }

    func insert(statement entityStatement: MemoryOSEntityStatement) throws {
        try prepared("""
        INSERT OR REPLACE INTO memory_l4_entity_statements
        (id, entity_id, predicate, object_entity_id, text, assertion_kind, confidence, valid_at, committed_at, evidence_span_ids_json, source_artifact_id, metadata_json)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """) { statement in
            bind(statement, 1, entityStatement.id)
            bind(statement, 2, entityStatement.entityID)
            bind(statement, 3, entityStatement.predicate)
            bind(statement, 4, entityStatement.objectEntityID)
            bind(statement, 5, entityStatement.text)
            bind(statement, 6, entityStatement.assertionKind.rawValue)
            sqlite3_bind_double(statement, 7, entityStatement.confidence)
            bind(statement, 8, iso(entityStatement.validAt))
            bind(statement, 9, iso(entityStatement.committedAt))
            bind(statement, 10, json(entityStatement.evidenceSpanIDs))
            bind(statement, 11, entityStatement.sourceArtifactID)
            bind(statement, 12, json(entityStatement.metadata))
            try step(statement)
        }
        try prepared("""
        INSERT INTO memory_l4_statements_fts(statement_id, predicate, text)
        VALUES (?, ?, ?)
        """) { statement in
            bind(statement, 1, entityStatement.id)
            bind(statement, 2, entityStatement.predicate)
            bind(statement, 3, entityStatement.text)
            try step(statement)
        }
    }

    func insertBuiltinDataset(id: String, kind: String, version: String, installedAt: Date, manifest: [String: String], stats: [String: String]) throws {
        try prepared("""
        INSERT OR REPLACE INTO memory_builtin_datasets
        (id, kind, version, installed_at, manifest_json, stats_json)
        VALUES (?, ?, ?, ?, ?, ?)
        """) { statement in
            bind(statement, 1, id)
            bind(statement, 2, kind)
            bind(statement, 3, version)
            bind(statement, 4, iso(installedAt))
            bind(statement, 5, json(manifest))
            bind(statement, 6, json(stats))
            try step(statement)
        }
    }

    private func prepared<T>(_ sql: String, _ body: (OpaquePointer?) throws -> T) throws -> T {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw error(sql) }
        defer { sqlite3_finalize(statement) }
        return try body(statement)
    }

    private func step(_ statement: OpaquePointer?) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else { throw error("step") }
    }

    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ value: String?) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_text(statement, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }

    private func json<T: Encodable>(_ value: T) -> String {
        guard let data = try? encoder.encode(value) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    private func iso(_ date: Date) -> String { isoFormatter.string(from: date) }

    private func error(_ context: String) -> NSError {
        let message = db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "unknown"
        return NSError(domain: "FoundationKGSeedSQLiteWriter", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(context): \(message)"])
    }
}

