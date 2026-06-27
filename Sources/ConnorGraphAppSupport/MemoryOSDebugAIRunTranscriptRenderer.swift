import Foundation
import ConnorGraphCore

public enum MemoryOSDebugAIRunTranscriptRenderer {
    public static func render(_ result: MemoryOSCLIDebugAIRunResult, maxContentCharacters: Int = 12_000) -> String {
        var lines: [String] = []
        lines.append("Memory OS Debug AI Run")
        lines.append("======================")
        lines.append("Command: \(result.command)")
        if let requestedKind = result.requestedKind { lines.append("Requested kind: \(requestedKind)") }
        lines.append("Requested limit: \(result.requestedLimit)")
        lines.append("Status: \(result.status)")
        lines.append("")

        guard !result.queueRuns.isEmpty else {
            lines.append("No runnable background AI jobs were found.")
            lines.append("")
            lines.append("Tip: enqueue jobs first, e.g. `swift run connor memory pipeline plan-l1` or `plan-l2`.")
            return lines.joined(separator: "\n")
        }

        for (index, run) in result.queueRuns.enumerated() {
            lines.append("[Queue Run \(index + 1)]")
            lines.append("-------------")
            lines.append("Queue item: \(run.queueItemID)")
            lines.append("Kind: \(run.kind)")
            lines.append("Run ID: \(run.runID ?? "<not persisted>")")
            lines.append("Model: \(run.modelID ?? "<unknown>")")
            lines.append("Status: \(run.status)")
            lines.append("Messages: \(run.messageCount)")
            lines.append("Tool calls: \(run.toolCallCount)")
            if let summary = run.projectionSummary {
                lines.append("Projection: accepted=\(summary.accepted) artifact=\(summary.artifactID) nodes=\(summary.nodeCount) statements=\(summary.statementCount) entities=\(summary.entityCount) beliefs=\(summary.beliefCount) issues=\(summary.issues.count)")
                for issue in summary.issues {
                    lines.append("  - issue[\(issue.code)]: \(issue.message)")
                }
            }
            lines.append("")

            lines.append("[Messages]")
            lines.append("----------")
            for message in run.messages.sorted(by: { $0.sequence < $1.sequence }) {
                var labelParts = ["#\(message.sequence)", message.role.rawValue]
                if let toolName = message.toolName, !toolName.isEmpty { labelParts.append(toolName) }
                let label = labelParts.joined(separator: " | ")
                lines.append("\(label):")
                lines.append(capped(message.content, max: maxContentCharacters))
                lines.append("")
            }

            lines.append("[Tool Calls]")
            lines.append("------------")
            if run.toolCalls.isEmpty {
                lines.append("<none>")
            } else {
                for call in run.toolCalls.sorted(by: { $0.iteration < $1.iteration }) {
                    lines.append("iteration \(call.iteration) | \(call.toolName) | \(call.status.rawValue)")
                    lines.append("Arguments:")
                    lines.append(capped(call.argumentsJSON, max: maxContentCharacters))
                    if let resultJSON = call.resultJSON, !resultJSON.isEmpty {
                        lines.append("Result:")
                        lines.append(capped(resultJSON, max: maxContentCharacters))
                    }
                    if let errorMessage = call.errorMessage, !errorMessage.isEmpty {
                        lines.append("Error: \(errorMessage)")
                    }
                    lines.append("")
                }
            }

            if let runID = run.runID {
                lines.append("[Trace persisted]")
                lines.append("-----------------")
                lines.append("Messages: swift run connor memory run \(runID) messages")
                lines.append("Tool calls: swift run connor memory run \(runID) tool-calls")
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func capped(_ value: String, max: Int) -> String {
        guard value.count > max else { return value }
        let index = value.index(value.startIndex, offsetBy: max)
        return String(value[..<index]) + "\n... <truncated \(value.count - max) chars>"
    }
}
