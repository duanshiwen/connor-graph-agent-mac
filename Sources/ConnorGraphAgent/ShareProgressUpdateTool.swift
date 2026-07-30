import Foundation
import ConnorGraphCore

public struct ShareProgressUpdateTool: AgentTool {
    public static let toolName = "share_progress_update"

    public var name: String { Self.toolName }
    public var description: String {
        "Temporarily display a user-facing progress update without ending the current run. This message will be deleted after the final response and will not remain in later conversation history. Continue working, then include every material result the user needs in a complete, self-contained final response."
    }
    public var permission: AgentPermissionCapability { .readSession }
    public var inputSchema: AgentToolInputSchema {
        .closedObject(
            properties: [
                "message": .string(description: "A concise, natural update written for the user. Describe the meaningful outcome or what is happening next; do not narrate tool names or raw operations.")
            ],
            required: ["message"]
        )
    }

    public init() {}

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let rawMessage = arguments.string("message") else {
            throw AgentToolError.invalidArguments("message is required")
        }
        let message = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            throw AgentToolError.invalidArguments("message must not be empty")
        }
        guard message.count <= 4_000 else {
            throw AgentToolError.invalidArguments("message must not exceed 4000 characters")
        }

        var assistantMessage = AgentMessage(
            role: .assistant,
            content: message
        )
        assistantMessage.runID = context.runID
        assistantMessage.sessionID = context.sessionID
        var result = AgentToolResult(
            runID: context.runID,
            sessionID: context.sessionID,
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: "Progress update displayed successfully. Continue the current run.",
            contentJSON: LocalToolJSON.encode([
                "status": "success",
                "displayedToUser": true,
                "continueRun": true
            ])
        )
        result.assistantMessage = assistantMessage
        return result
    }
}

public extension AgentToolRegistry {
    mutating func registerShareProgressUpdateTool() {
        register(ShareProgressUpdateTool())
    }
}
