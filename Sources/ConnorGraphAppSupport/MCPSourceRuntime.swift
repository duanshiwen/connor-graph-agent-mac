import Foundation
import ConnorGraphAgent
import ConnorGraphCore

public struct MCPSourceToolDescriptor: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public var sourceID: String
    public var name: String
    public var rawName: String
    public var description: String
    public var inputSchema: MCPJSONValue
    public var requiredCapabilities: [AgentPermissionCapability]

    public init(
        sourceID: String,
        name: String,
        rawName: String,
        description: String,
        inputSchema: MCPJSONValue,
        requiredCapabilities: [AgentPermissionCapability]
    ) {
        self.sourceID = sourceID
        self.name = name
        self.rawName = rawName
        self.description = description
        self.inputSchema = inputSchema
        self.requiredCapabilities = requiredCapabilities
    }
}

public struct MCPSourceToolInvocation: Sendable, Equatable {
    public var sourceID: String
    public var rawToolName: String
    public var prefixedToolName: String
    public var permissionRequest: AgentPermissionRequest
    public var toolCall: AgentToolCall
    public var result: AgentToolResult
    public var events: [AgentEvent]

    public init(
        sourceID: String,
        rawToolName: String,
        prefixedToolName: String,
        permissionRequest: AgentPermissionRequest,
        toolCall: AgentToolCall,
        result: AgentToolResult,
        events: [AgentEvent]
    ) {
        self.sourceID = sourceID
        self.rawToolName = rawToolName
        self.prefixedToolName = prefixedToolName
        self.permissionRequest = permissionRequest
        self.toolCall = toolCall
        self.result = result
        self.events = events
    }
}

public enum MCPSourceRuntimeError: Error, Sendable, Equatable, CustomStringConvertible {
    case sourceNotEnabled(String)
    case invalidPrefixedToolName(String)
    case sourcePrefixMismatch(expected: String, actual: String)

    public var description: String {
        switch self {
        case .sourceNotEnabled(let sourceID): "sourceNotEnabled: \(sourceID)"
        case .invalidPrefixedToolName(let name): "invalidPrefixedToolName: \(name)"
        case .sourcePrefixMismatch(let expected, let actual): "sourcePrefixMismatch: expected \(expected), actual \(actual)"
        }
    }
}

public actor MCPSourceRuntime<Transport: MCPClientTransport> {
    public var configuration: MCPSourceRuntimeConfiguration
    private var client: MCPJSONRPCClient<Transport>
    private let encoder: JSONEncoder

    public init(configuration: MCPSourceRuntimeConfiguration, client: MCPJSONRPCClient<Transport>) {
        self.configuration = configuration
        self.client = client
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
    }

    public func discoverToolCatalog() async throws -> [MCPSourceToolDescriptor] {
        _ = try await client.initialize()
        let tools = try await client.listTools()
        return tools.map { tool in
            MCPSourceToolDescriptor(
                sourceID: configuration.sourceID,
                name: "\(configuration.toolNamePrefix).\(tool.name)",
                rawName: tool.name,
                description: tool.description,
                inputSchema: tool.inputSchema,
                requiredCapabilities: configuration.allowedCapabilities
            )
        }
    }

    public func callTool(name prefixedToolName: String, arguments: MCPJSONValue, runID: String, sessionID: String) async throws -> MCPSourceToolInvocation {
        guard configuration.status == .enabled else {
            throw MCPSourceRuntimeError.sourceNotEnabled(configuration.sourceID)
        }
        let rawName = try rawToolName(from: prefixedToolName)
        let argumentsJSON = try jsonString(arguments)
        let permissionRequest = AgentPermissionRequest(
            runID: runID,
            sessionID: sessionID,
            capability: .externalNetwork,
            toolName: prefixedToolName,
            payloadJSON: argumentsJSON
        )
        let toolCall = AgentToolCall(
            runID: runID,
            sessionID: sessionID,
            name: prefixedToolName,
            argumentsJSON: argumentsJSON
        )
        let mcpResult = try await client.callTool(name: rawName, arguments: arguments)
        let contentText = mcpResult.content.compactMap(\.text).joined(separator: "\n")
        let result = AgentToolResult(
            runID: runID,
            sessionID: sessionID,
            toolCallID: toolCall.id,
            toolName: prefixedToolName,
            contentText: contentText,
            contentJSON: try? jsonString(.object([
                "sourceID": .string(configuration.sourceID),
                "rawToolName": .string(rawName),
                "isError": .bool(mcpResult.isError)
            ])),
            error: mcpResult.isError ? contentText : nil
        )
        return MCPSourceToolInvocation(
            sourceID: configuration.sourceID,
            rawToolName: rawName,
            prefixedToolName: prefixedToolName,
            permissionRequest: permissionRequest,
            toolCall: toolCall,
            result: result,
            events: [
                .permissionRequested(permissionRequest),
                .toolStarted(toolCall),
                .toolFinished(result)
            ]
        )
    }

    public func shutdown() async throws {
        try await client.shutdown()
    }

    private func rawToolName(from prefixedToolName: String) throws -> String {
        let components = prefixedToolName.split(separator: ".", maxSplits: 1).map(String.init)
        guard components.count == 2 else { throw MCPSourceRuntimeError.invalidPrefixedToolName(prefixedToolName) }
        guard components[0] == configuration.toolNamePrefix else {
            throw MCPSourceRuntimeError.sourcePrefixMismatch(expected: configuration.toolNamePrefix, actual: components[0])
        }
        return components[1]
    }

    private func jsonString(_ value: MCPJSONValue) throws -> String {
        String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}
