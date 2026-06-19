import Foundation
import ConnorGraphCore

public struct TimeAnalyzeRangesTool: AgentTool {
    public var name: String { "time_analyze_ranges" }
    public var description: String { "Analyze time ranges: signed start-to-start differences and pairwise overlaps." }
    public var permission: AgentPermissionCapability { .computeScientific }
    public var inputSchema: AgentToolInputSchema {
        .object(properties: [
            "ranges": .array(items: .object(properties: [
                "id": .string(description: "Range ID"),
                "start": .string(description: "ISO-8601 start timestamp"),
                "end": .string(description: "ISO-8601 end timestamp")
            ], required: ["id", "start", "end"]), description: "Ranges to analyze")
        ], required: ["ranges"])
    }

    public init() {}

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let ranges = try parseRanges(arguments: arguments)
        let result = TimeRangeAnalyzer().analyze(ranges: ranges)
        return AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: "Analyzed \(ranges.count) time ranges",
            contentJSON: try MailJSON.encode(result)
        )
    }

    private func parseRanges(arguments: AgentToolArguments) throws -> [TimeAnalysisRange] {
        let formatter = ISO8601DateFormatter()
        guard let rawRanges = arguments.array("ranges") else {
            throw AgentToolError.invalidArguments("ranges is required")
        }
        return try rawRanges.map { value in
            guard let object = value.objectValue,
                  let id = object["id"]?.stringValue,
                  let startString = object["start"]?.stringValue,
                  let endString = object["end"]?.stringValue,
                  let start = formatter.date(from: startString),
                  let end = formatter.date(from: endString)
            else {
                throw AgentToolError.invalidArguments("Each range requires id, start, and end ISO-8601 timestamps")
            }
            return TimeAnalysisRange(id: id, start: start, end: end)
        }
    }
}

public extension AgentToolRegistry {
    mutating func registerTimeAnalysisTool() {
        register(TimeAnalyzeRangesTool())
    }
}
