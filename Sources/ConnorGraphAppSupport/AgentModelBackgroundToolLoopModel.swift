import Foundation
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphMemory

public struct AgentModelBackgroundToolLoopModel: MemoryOSBackgroundToolLoopModel, @unchecked Sendable {
    public var provider: AnyAgentModelProvider

    public var modelID: String { provider.modelID }

    public init(provider: AnyAgentModelProvider) {
        self.provider = provider
    }

    public func complete(_ request: MemoryOSBackgroundLoopModelRequest) throws -> MemoryOSBackgroundLoopModelResponse {
        let agentRequest = AgentModelRequest(
            messages: request.messages.map(Self.agentMessage),
            tools: request.availableTools.map(Self.agentToolDefinition),
            temperature: 0.2
        )
        let response = try runBlocking { try await provider.complete(agentRequest) }
        var metadata: [String: String] = [
            "model_id": provider.modelID,
            "model_supports_tool_calling": String(provider.capabilities.supportsToolCalling)
        ]
        if let rawResponseJSON = response.rawResponseJSON { metadata["raw_response_json"] = rawResponseJSON }
        if let providerMetadata = response.providerMetadata {
            metadata["provider_id"] = providerMetadata.providerID
            if let responseID = providerMetadata.responseID { metadata["provider_response_id"] = responseID }
            if let stopReason = providerMetadata.stopReason { metadata["provider_stop_reason"] = stopReason }
            metadata["provider_reasoning_encrypted_content_present"] = String(providerMetadata.reasoningEncryptedContentPresent)
        }
        if let usage = response.usage {
            metadata["prompt_tokens"] = String(usage.promptTokens)
            metadata["completion_tokens"] = String(usage.completionTokens)
            metadata["total_tokens"] = String(usage.totalTokens)
        }
        return MemoryOSBackgroundLoopModelResponse(
            assistantText: response.text ?? "",
            toolCalls: response.toolCalls.map(Self.memoryOSToolCall),
            finalArtifactJSON: Self.extractFinalArtifactJSON(from: response.text, toolCalls: response.toolCalls),
            metadata: metadata
        )
    }

    public static func agentMessage(_ message: MemoryOSBackgroundLoopMessage) -> AgentModelMessage {
        AgentModelMessage(
            id: message.id,
            role: agentRole(message.role),
            content: message.content,
            toolCallID: message.toolCallID,
            name: message.toolName
        )
    }

    public static func agentToolDefinition(_ tool: MemoryOSBackgroundToolDescriptor) -> AgentToolDefinition {
        AgentToolDefinition(
            name: tool.name,
            description: [tool.description, tool.usagePolicy].filter { !$0.isEmpty }.joined(separator: "\n\nUsage policy: "),
            inputSchema: Self.agentInputSchema(fromMemoryOSToolSchemaJSON: tool.inputSchemaJSON)
        )
    }

    public static func memoryOSToolCall(_ call: AgentToolCall) -> MemoryOSBackgroundToolCall {
        MemoryOSBackgroundToolCall(id: call.id, name: call.name, argumentsJSON: call.argumentsJSON)
    }

    private static func agentRole(_ role: MemoryOSBackgroundMessageRole) -> AgentModelMessageRole {
        switch role {
        case .system: return .system
        case .user: return .user
        case .assistant: return .assistant
        case .tool: return .tool
        }
    }

    private static func agentInputSchema(fromMemoryOSToolSchemaJSON json: String) -> AgentToolInputSchema {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return .object(properties: [:], required: [])
        }
        var properties: [String: AgentToolInputSchema] = [:]
        for (key, value) in object {
            properties[key] = schemaValue(from: value)
        }
        return .object(properties: properties, required: properties.keys.sorted())
    }

    private static func schemaValue(from value: Any) -> AgentToolInputSchema {
        if let string = value as? String {
            let normalized = string.lowercased()
            if normalized.contains("number") { return .number(description: string) }
            if normalized.contains("integer") || normalized.contains("int") { return .integer(description: string) }
            if normalized.contains("boolean") || normalized.contains("bool") { return .boolean(description: string) }
            if normalized.contains("array") { return .array(items: .string(description: "array item"), description: string) }
            return .string(description: string)
        }
        if let array = value as? [Any] {
            let description = array.compactMap { $0 as? String }.joined(separator: ",")
            return .array(items: .string(description: description.isEmpty ? "array item" : description), description: description.isEmpty ? "array" : description)
        }
        if let dictionary = value as? [String: Any] {
            var properties: [String: AgentToolInputSchema] = [:]
            for (key, value) in dictionary { properties[key] = schemaValue(from: value) }
            return .object(properties: properties, required: properties.keys.sorted())
        }
        return .string(description: String(describing: value))
    }

    private static func extractFinalArtifactJSON(from text: String?, toolCalls: [AgentToolCall]) -> String? {
        guard toolCalls.isEmpty, let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") && trimmed.hasSuffix("}") else { return nil }
        return trimmed
    }

    private func runBlocking<T>(_ operation: @escaping @Sendable () async throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let box = AgentModelBackgroundToolLoopBlockingResultBox<T>()
        Task {
            do {
                box.result = Result<T, Error>.success(try await operation())
            } catch {
                box.result = Result<T, Error>.failure(error)
            }
            semaphore.signal()
        }
        semaphore.wait()
        return try box.result!.get()
    }
}

private final class AgentModelBackgroundToolLoopBlockingResultBox<T>: @unchecked Sendable {
    var result: Result<T, Error>?
}
