import Foundation
import ConnorGraphCore

public enum AgentProgressUpdateCapabilityPolicy {
    public static func supportsModelManagedProgressUpdates(modelID: String?) -> Bool {
        guard let modelID else { return false }
        let normalized = modelID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let modelName = normalized.split(separator: "/").last,
              modelName.hasPrefix("gpt-") else {
            return false
        }
        let versionAndVariant = modelName.dropFirst("gpt-".count)
        let version = versionAndVariant.prefix { $0.isNumber || $0 == "." }
        let components = version.split(separator: ".", omittingEmptySubsequences: false)
        guard let major = components.first.flatMap({ Int($0) }) else { return false }
        let minor = components.count > 1 ? Int(components[1]) ?? 0 : 0
        return major > 5 || (major == 5 && minor >= 5)
    }

    public static func systemPromptSection(modelID: String?, toolIsAvailable: Bool) -> String? {
        guard toolIsAvailable, supportsModelManagedProgressUpdates(modelID: modelID) else { return nil }
        return AgentInstructionSection.conversationalProgressUpdateInstruction
    }

    public static func modelVisibleToolDefinitions(
        _ definitions: [AgentToolDefinition],
        modelID: String?
    ) -> [AgentToolDefinition] {
        guard !supportsModelManagedProgressUpdates(modelID: modelID) else { return definitions }
        return definitions.filter { $0.name != ShareProgressUpdateTool.toolName }
    }
}

public struct ShareProgressUpdateTool: AgentTool {
    public static let toolName = "share_progress_update"

    public var name: String { Self.toolName }
    public var description: String {
        "Temporarily display a user-facing progress update as an assistant message without ending the current run. The update is not returned as model context and is removed after the final response, so keep the final response self-contained."
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
