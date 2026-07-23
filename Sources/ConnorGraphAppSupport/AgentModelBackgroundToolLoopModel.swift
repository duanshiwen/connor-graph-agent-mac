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
            metadata: metadata
        )
    }

    public static func agentMessage(_ message: MemoryOSBackgroundLoopMessage) -> AgentModelMessage {
        AgentModelMessage(
            id: message.id,
            role: agentRole(message.role),
            content: message.content,
            toolCallID: message.toolCallID,
            name: message.toolName,
            toolCalls: message.toolCalls?.map { AgentToolCall(id: $0.id, name: $0.name, argumentsJSON: $0.argumentsJSON) }
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
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let schema = schemaValue(from: object)
        else {
            return .closedObject(properties: [:], required: [])
        }
        return schema
    }

    private static func schemaValue(from object: [String: Any]) -> AgentToolInputSchema? {
        let description = object["description"] as? String ?? ""
        let type = object["type"] as? String
        let isNullable = (object["type"] as? [String])?.contains("null") == true
        let concreteType = type ?? (object["type"] as? [String])?.first(where: { $0 != "null" })
        let schema: AgentToolInputSchema?
        switch concreteType {
        case "string":
            if let values = object["enum"] as? [String] {
                schema = .stringEnumeration(values: values, description: description)
            } else {
                schema = .string(description: description)
            }
        case "integer": schema = .integer(description: description)
        case "number": schema = .number(description: description)
        case "boolean": schema = .boolean(description: description)
        case "array":
            guard let items = object["items"] as? [String: Any], let itemSchema = schemaValue(from: items) else { return nil }
            schema = .array(items: itemSchema, description: description)
        case "object":
            let rawProperties = object["properties"] as? [String: Any] ?? [:]
            var properties: [String: AgentToolInputSchema] = [:]
            for (key, value) in rawProperties {
                guard let child = value as? [String: Any], let childSchema = schemaValue(from: child) else { return nil }
                properties[key] = childSchema
            }
            let required = object["required"] as? [String] ?? []
            schema = object["additionalProperties"] as? Bool == false
                ? .closedObject(properties: properties, required: required)
                : .object(properties: properties, required: required)
        default: return nil
        }
        guard let schema else { return nil }
        return isNullable ? .nullable(schema) : schema
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
