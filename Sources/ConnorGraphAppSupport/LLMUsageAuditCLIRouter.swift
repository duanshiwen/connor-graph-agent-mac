import Foundation
import ConnorGraphAgent

public enum LLMUsageAuditCLIError: Error, LocalizedError {
    case invalidArgument(String)
    case recordNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .invalidArgument(let value): return "Invalid llm-audit argument: \(value)"
        case .recordNotFound(let id): return "LLM audit record not found: \(id)"
        }
    }
}

public enum LLMUsageAuditCLIRouter {
    public static let usage = "connor llm-audit [summary|list|show <id>|top] [--kind <kind>] [--model <model>] [--status succeeded|failed|cancelled] [--since 24h|7d|ISO-8601] [--limit N] [--group-by operation|kind|model|tool] [--json]"

    public static func route(args: [String], storagePaths: AppStoragePaths, encoder: JSONEncoder) throws -> String {
        let json = args.contains("--json")
        let values = args.filter { $0 != "--json" }
        let command = values.first?.hasPrefix("--") == false ? (values.first ?? "overview") : "overview"
        let commandArgs = command == "overview" ? values : Array(values.dropFirst())
        let query = LLMUsageAuditQueryService(store: FileLLMUsageAuditStore(storagePaths: storagePaths))
        let since = try option("--since", in: commandArgs).map(parseSince)

        switch command {
        case "overview", "summary":
            let summary = query.summary(since: since)
            if json { return try encode(summary, encoder: encoder) }
            let recent = query.list(filter: LLMUsageAuditFilter(since: since, limit: 10))
            return renderOverview(summary: summary, recent: recent)
        case "list":
            let filter = try makeFilter(args: commandArgs, since: since)
            let records = query.list(filter: filter)
            return json ? try encode(records, encoder: encoder) : renderList(records)
        case "show":
            guard let id = commandArgs.first, !id.hasPrefix("--") else { throw LLMUsageAuditCLIError.invalidArgument("missing record id") }
            guard let record = query.record(id: id) else { throw LLMUsageAuditCLIError.recordNotFound(id) }
            return json ? try encode(record, encoder: encoder) : renderDetail(record)
        case "top":
            let group = option("--group-by", in: commandArgs) ?? "operation"
            let limit = try intOption("--limit", in: commandArgs) ?? 10
            let records = query.list(filter: try makeFilter(args: commandArgs, since: since, defaultLimit: Int.max))
            let rows = try topRows(records: records, groupBy: group, limit: limit)
            return json ? try encode(rows, encoder: encoder) : renderTop(rows, groupBy: group)
        case "help", "--help": return usage
        default: throw LLMUsageAuditCLIError.invalidArgument(command)
        }
    }

    private static func makeFilter(args: [String], since: Date?, defaultLimit: Int = 50) throws -> LLMUsageAuditFilter {
        let kind = try option("--kind", in: args).map {
            guard let value = AgentLLMRequestKind(rawValue: $0) else { throw LLMUsageAuditCLIError.invalidArgument("--kind \($0)") }
            return value
        }
        let status = try option("--status", in: args).map {
            guard let value = LLMUsageAuditStatus(rawValue: $0) else { throw LLMUsageAuditCLIError.invalidArgument("--status \($0)") }
            return value
        }
        return LLMUsageAuditFilter(
            requestKind: kind,
            model: option("--model", in: args),
            status: status,
            since: since,
            limit: try intOption("--limit", in: args) ?? defaultLimit
        )
    }

    private static func option(_ name: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: name), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }

    private static func intOption(_ name: String, in args: [String]) throws -> Int? {
        guard let raw = option(name, in: args) else { return nil }
        guard let value = Int(raw), value > 0 else { throw LLMUsageAuditCLIError.invalidArgument("\(name) \(raw)") }
        return value
    }

    private static func parseSince(_ raw: String) throws -> Date {
        let now = Date()
        if raw.hasSuffix("h"), let hours = Double(raw.dropLast()) { return now.addingTimeInterval(-hours * 3_600) }
        if raw.hasSuffix("d"), let days = Double(raw.dropLast()) { return now.addingTimeInterval(-days * 86_400) }
        if let date = ISO8601DateFormatter().date(from: raw) { return date }
        throw LLMUsageAuditCLIError.invalidArgument("--since \(raw)")
    }

    private static func renderOverview(summary: LLMUsageAuditSummary, recent: [LLMUsageAuditRecord]) -> String {
        var lines = [
            "LLM Usage Audit",
            "Calls: \(summary.calls)  Success: \(percent(summary.successRate))  Failed: \(summary.failed)  Cancelled: \(summary.cancelled)",
            "Tokens: \(summary.totalTokens)  Input: \(summary.promptTokens)  Output: \(summary.completionTokens)  Cache read: \(summary.cacheReadInputTokens)",
            "Coverage: \(summary.calls - summary.unmeteredCalls)/\(summary.calls) calls metered  Estimated input: \(summary.estimatedInputTokens)",
            "Unclassified: \(summary.unclassifiedCalls)\(summary.unclassifiedCalls > 0 ? "  ACTION REQUIRED" : "")",
            "",
            "Top operations by token:",
            summary.byOperation.prefix(5).map { "\($0.key): \($0.totalTokens) tokens / \($0.calls) calls" }.joined(separator: "\n")
        ]
        lines.append(contentsOf: ["", "Recent calls:", renderList(recent)])
        return lines.joined(separator: "\n")
    }

    private static func renderList(_ records: [LLMUsageAuditRecord]) -> String {
        guard !records.isEmpty else { return "No LLM audit records found." }
        var lines = ["TIME                 STATUS     TOKENS   KIND                               MODEL                    OPERATION"]
        lines += records.map { record in
            "\(timestamp(record.startedAt))  \(pad(record.status.rawValue, 10)) \(pad(record.totalTokens.map(String.init) ?? "n/a", 8)) \(pad(record.requestKind.rawValue, 34)) \(pad(record.modelID, 24)) \(record.operation ?? "-")"
        }
        return lines.joined(separator: "\n")
    }

    private static func renderDetail(_ record: LLMUsageAuditRecord) -> String {
        let tools = record.relatedToolNames.isEmpty ? "-" : record.relatedToolNames.joined(separator: ", ")
        return [
            "ID: \(record.id)", "Time: \(timestamp(record.startedAt))", "Duration: \(record.durationMilliseconds) ms",
            "Status: \(record.status.rawValue)", "Kind: \(record.requestKind.rawValue)", "Initiator: \(record.initiator.rawValue)",
            "Operation: \(record.operation ?? "-")", "Model: \(record.modelID)", "Provider: \(record.providerID ?? record.providerMode ?? "-")",
            "Connection: \(record.connectionID ?? "-")", "Session: \(record.sessionID ?? "-")", "Run: \(record.runID ?? "-")", "Background job: \(record.backgroundJobID ?? "-")",
            "Tokens: \(record.totalTokens.map(String.init) ?? "n/a") (input \(record.promptTokens.map(String.init) ?? "n/a"), output \(record.completionTokens.map(String.init) ?? "n/a"))",
            "Cache: create \(record.cacheCreationInputTokens.map(String.init) ?? "n/a"), read \(record.cacheReadInputTokens.map(String.init) ?? "n/a"), uncached input \(record.uncachedInputTokens.map(String.init) ?? "n/a")",
            "Request shape: \(record.messageCount) messages, \(record.toolDefinitionCount) tool definitions, \(record.inputCharacterCount) characters, images \(record.containsImages)",
            "Related tools: \(tools)", "Finish: \(record.finishReason ?? "-")", "Error: \(record.errorMessage ?? "-")"
        ].joined(separator: "\n")
    }

    public struct TopRow: Codable, Sendable, Equatable {
        public var key: String
        public var calls: Int
        public var totalTokens: Int
        public var averageTokens: Int
        public var failed: Int
    }

    private static func topRows(records: [LLMUsageAuditRecord], groupBy: String, limit: Int) throws -> [TopRow] {
        guard ["operation", "kind", "model", "tool"].contains(groupBy) else { throw LLMUsageAuditCLIError.invalidArgument("--group-by \(groupBy)") }
        return topRowsUnchecked(records: records, groupBy: groupBy, limit: limit)
    }

    private static func topRowsUnchecked(records: [LLMUsageAuditRecord], groupBy: String, limit: Int) -> [TopRow] {
        var groups: [String: [LLMUsageAuditRecord]] = [:]
        for record in records {
            let keys: [String]
            switch groupBy {
            case "kind": keys = [record.requestKind.rawValue]
            case "model": keys = [record.modelID]
            case "tool": keys = record.relatedToolNames.isEmpty ? ["(no related tool)"] : record.relatedToolNames
            default: keys = [record.operation ?? "(unclassified operation)"]
            }
            for key in keys { groups[key, default: []].append(record) }
        }
        let rows = groups.map { key, values -> TopRow in
            let tokens = values.compactMap(\.totalTokens).reduce(0, +)
            return TopRow(key: key, calls: values.count, totalTokens: tokens, averageTokens: values.isEmpty ? 0 : tokens / values.count, failed: values.filter { $0.status == .failed }.count)
        }.sorted { $0.totalTokens == $1.totalTokens ? $0.calls > $1.calls : $0.totalTokens > $1.totalTokens }
        return limit > 0 ? Array(rows.prefix(limit)) : rows
    }

    private static func renderTop(_ rows: [TopRow], groupBy: String) -> String {
        guard !rows.isEmpty else { return "No LLM audit records found." }
        var lines = ["TOKENS      CALLS   AVG      FAILED  \(groupBy.uppercased())"]
        lines += rows.map { "\(pad(String($0.totalTokens), 11)) \(pad(String($0.calls), 7)) \(pad(String($0.averageTokens), 8)) \(pad(String($0.failed), 7)) \($0.key)" }
        if groupBy == "tool" { lines.append("Note: tool rows show tokens from related requests; a request associated with multiple tools appears in each relevant row.") }
        return lines.joined(separator: "\n")
    }

    private static func pad(_ value: String, _ width: Int) -> String { String(value.prefix(width)).padding(toLength: width, withPad: " ", startingAt: 0) }
    private static func percent(_ value: Double) -> String { String(format: "%.1f%%", value * 100) }
    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
    private static func encode<T: Encodable>(_ value: T, encoder: JSONEncoder) throws -> String { String(decoding: try encoder.encode(value), as: UTF8.self) }
}
