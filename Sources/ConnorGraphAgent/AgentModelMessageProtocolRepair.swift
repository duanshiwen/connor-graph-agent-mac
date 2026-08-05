import Foundation

/// Send-time safety net that enforces the OpenAI-compatible tool-calling
/// message protocol before a request reaches a provider: an assistant message
/// with `tool_calls` must be followed contiguously by tool messages responding
/// to every `tool_call_id`. Providers such as DeepSeek reject violations with
/// 400 "insufficient tool messages following tool_calls message".
///
/// The repair is conservative and idempotent:
/// - Real tool results that were pushed below an interleaved non-tool message
///   (for example an attachment-context user message inside a parallel batch)
///   are promoted back into the contiguous run.
/// - Calls that genuinely have no recorded result in the turn receive a clearly
///   marked placeholder tool message instead of being left dangling.
public enum AgentModelMessageProtocolRepair {

    /// Prefix used by placeholder results for tool calls whose result is
    /// missing and cannot be recovered from the same turn.
    public static let interruptedToolResultPrefix = "[TRUSTED RUNTIME REPAIR] Tool result unavailable"

    public static func repairing(_ messages: [AgentModelMessage]) -> [AgentModelMessage] {
        var result = messages
        var index = 0
        while index < result.count {
            guard result[index].role == .assistant,
                  let calls = result[index].toolCalls,
                  !calls.isEmpty else {
                index += 1
                continue
            }

            let runStart = index + 1
            var runEnd = runStart
            var coveredIDs = Set<String>()
            while runEnd < result.count, result[runEnd].role == .tool {
                if let id = result[runEnd].toolCallID {
                    coveredIDs.insert(id)
                }
                runEnd += 1
            }

            let expectedIDs = Set(calls.map(\.id))
            var missing = expectedIDs.subtracting(coveredIDs)
            guard !missing.isEmpty else {
                index = runEnd
                continue
            }

            // Promote real results that appear later in the same turn so the
            // contiguous run is restored instead of duplicating a call id with a
            // placeholder. Stop at the next assistant tool-calls turn; tool
            // messages beyond it belong to a different model turn.
            var promoted: [AgentModelMessage] = []
            var scan = runEnd
            while scan < result.count {
                let candidate = result[scan]
                if candidate.role == .assistant, candidate.toolCalls?.isEmpty == false {
                    break
                }
                if candidate.role == .tool, let id = candidate.toolCallID, missing.contains(id) {
                    promoted.append(candidate)
                    result.remove(at: scan)
                    missing.remove(id)
                    if missing.isEmpty { break }
                    continue
                }
                scan += 1
            }

            let insertionPoint = runEnd
            for (offset, promotedMessage) in promoted.enumerated() {
                result.insert(promotedMessage, at: insertionPoint + offset)
            }
            var placeholderOffset = promoted.count
            for call in calls where missing.contains(call.id) {
                result.insert(placeholderResult(for: call), at: insertionPoint + placeholderOffset)
                placeholderOffset += 1
            }
            index = insertionPoint + promoted.count + missing.count
        }
        return result
    }

    private static func placeholderResult(for call: AgentToolCall) -> AgentModelMessage {
        AgentModelMessage(
            role: .tool,
            content: "\(interruptedToolResultPrefix) (tool=\(call.name), callID=\(call.id)) because execution was interrupted before a result was recorded. Do not assume this call succeeded or produced side effects; re-issue the call if the task still requires it.",
            toolCallID: call.id,
            name: call.name
        )
    }
}
