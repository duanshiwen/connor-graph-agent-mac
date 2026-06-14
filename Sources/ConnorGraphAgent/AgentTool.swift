import Foundation
import ConnorGraphCore

public indirect enum AgentToolInputSchema: Sendable, Equatable {
    case string(description: String)
    case integer(description: String)
    case number(description: String)
    case boolean(description: String)
    case array(items: AgentToolInputSchema, description: String)
    case object(properties: [String: AgentToolInputSchema], required: [String])

    public var jsonObject: [String: Any] {
        switch self {
        case .string(let description):
            return ["type": "string", "description": description]
        case .integer(let description):
            return ["type": "integer", "description": description]
        case .number(let description):
            return ["type": "number", "description": description]
        case .boolean(let description):
            return ["type": "boolean", "description": description]
        case .array(let items, let description):
            return ["type": "array", "description": description, "items": items.jsonObject]
        case .object(let properties, let required):
            return [
                "type": "object",
                "properties": properties.mapValues { $0.jsonObject },
                "required": required
            ]
        }
    }
}

public struct AgentToolDefinition: Sendable, Equatable {
    public var name: String
    public var description: String
    public var inputSchema: AgentToolInputSchema

    public init(name: String, description: String, inputSchema: AgentToolInputSchema) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

public struct AgentToolArguments: Sendable, Equatable {
    public var values: [String: SendableJSONValue]

    public init(values: [String: SendableJSONValue] = [:]) {
        self.values = values
    }

    public init(json: String) throws {
        let data = Data(json.utf8)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw AgentToolError.invalidArguments("Expected JSON object")
        }
        self.values = try dictionary.mapValues { try SendableJSONValue(any: $0) }
    }

    public func string(_ key: String) -> String? {
        if case .string(let value) = values[key] { return value }
        return nil
    }

    public func int(_ key: String) -> Int? {
        if case .int(let value) = values[key] { return value }
        return nil
    }

    public func bool(_ key: String) -> Bool? {
        if case .bool(let value) = values[key] { return value }
        return nil
    }

    public func array(_ key: String) -> [SendableJSONValue]? {
        if case .array(let value) = values[key] { return value }
        return nil
    }
}

public extension SendableJSONValue {
    var objectValue: [String: SendableJSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }
}

public enum SendableJSONValue: Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: SendableJSONValue])
    case array([SendableJSONValue])
    case null

    public init(any: Any) throws {
        switch any {
        case let value as String:
            self = .string(value)
        case let value as Int:
            self = .int(value)
        case let value as Double:
            self = .double(value)
        case let value as Bool:
            self = .bool(value)
        case let value as [String: Any]:
            self = .object(try value.mapValues { try SendableJSONValue(any: $0) })
        case let value as [Any]:
            self = .array(try value.map { try SendableJSONValue(any: $0) })
        case _ as NSNull:
            self = .null
        default:
            throw AgentToolError.invalidArguments("Unsupported JSON value: \(type(of: any))")
        }
    }
}

public struct AgentToolCall: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var runID: String?
    public var sessionID: String?
    public var name: String
    public var argumentsJSON: String

    public init(id: String = UUID().uuidString, runID: String? = nil, sessionID: String? = nil, name: String, argumentsJSON: String) {
        self.id = id
        self.runID = runID
        self.sessionID = sessionID
        self.name = name
        self.argumentsJSON = argumentsJSON
    }
}

public struct AgentToolResult: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var runID: String?
    public var sessionID: String?
    public var toolCallID: String
    public var toolName: String
    public var contentText: String
    public var contentJSON: String?
    public var citations: [String]
    public var createdAt: Date
    public var error: String?

    public init(
        id: String = UUID().uuidString,
        runID: String? = nil,
        sessionID: String? = nil,
        toolCallID: String,
        toolName: String,
        contentText: String,
        contentJSON: String? = nil,
        citations: [String] = [],
        createdAt: Date = Date(),
        error: String? = nil
    ) {
        self.id = id
        self.runID = runID
        self.sessionID = sessionID
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.contentText = contentText
        self.contentJSON = contentJSON
        self.citations = citations
        self.createdAt = createdAt
        self.error = error
    }
}

public struct AgentToolFailure: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var runID: String
    public var sessionID: String
    public var toolCallID: String
    public var toolName: String
    public var message: String

    public init(id: String = UUID().uuidString, runID: String, sessionID: String, toolCallID: String, toolName: String, message: String) {
        self.id = id
        self.runID = runID
        self.sessionID = sessionID
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.message = message
    }
}

public struct AgentToolExecutionContext: Sendable {
    public var runID: String
    public var sessionID: String
    public var groupID: String
    public var userPrompt: String
    public var toolCallID: String
    public var policyEngine: AgentPolicyEngine
    public var approvedCapabilities: Set<AgentPermissionCapability>

    public init(
        runID: String,
        sessionID: String,
        groupID: String,
        userPrompt: String,
        toolCallID: String,
        policyEngine: AgentPolicyEngine
    ) {
        self.init(
            runID: runID,
            sessionID: sessionID,
            groupID: groupID,
            userPrompt: userPrompt,
            toolCallID: toolCallID,
            policyEngine: policyEngine,
            approvedCapabilities: []
        )
    }

    public init(
        runID: String,
        sessionID: String,
        groupID: String,
        userPrompt: String,
        toolCallID: String,
        policyEngine: AgentPolicyEngine,
        approvedCapabilities: Set<AgentPermissionCapability>
    ) {
        self.runID = runID
        self.sessionID = sessionID
        self.groupID = groupID
        self.userPrompt = userPrompt
        self.toolCallID = toolCallID
        self.policyEngine = policyEngine
        self.approvedCapabilities = approvedCapabilities
    }

    public func approving(_ capability: AgentPermissionCapability) -> AgentToolExecutionContext {
        var copy = self
        copy.approvedCapabilities.insert(capability)
        return copy
    }
}

public protocol AgentTool: Sendable {
    var name: String { get }
    var description: String { get }
    var permission: AgentPermissionCapability { get }
    var inputSchema: AgentToolInputSchema { get }

    func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult
}

public enum AgentToolError: Error, Equatable, Sendable, CustomStringConvertible {
    case unknownTool(String)
    case invalidArguments(String)
    case permissionDenied(String)
    case permissionNeedsApproval(AgentPermissionRequest)

    public var description: String {
        switch self {
        case .unknownTool(let name): return "Unknown tool: \(name)"
        case .invalidArguments(let message): return "Invalid arguments: \(message)"
        case .permissionDenied(let message): return "Permission denied: \(message)"
        case .permissionNeedsApproval(let request): return "Permission needs approval: \(request.capability.rawValue)"
        }
    }
}

public struct AgentToolRegistry: Sendable {
    private var tools: [String: any AgentTool]

    public init(tools: [any AgentTool] = []) {
        self.tools = [:]
        for tool in tools { self.tools[tool.name] = tool }
    }

    public mutating func register(_ tool: any AgentTool) {
        tools[tool.name] = tool
    }

    public func definition(named name: String) -> AgentToolDefinition? {
        guard let tool = tools[name] else { return nil }
        return AgentToolDefinition(name: tool.name, description: tool.description, inputSchema: tool.inputSchema)
    }

    public func permission(named name: String) -> AgentPermissionCapability? {
        tools[name]?.permission
    }

    public var definitions: [AgentToolDefinition] {
        tools.keys.sorted().compactMap { definition(named: $0) }
    }

    public func execute(_ call: AgentToolCall, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let tool = tools[call.name] else {
            throw AgentToolError.unknownTool(call.name)
        }
        if !context.approvedCapabilities.contains(tool.permission) {
            let decision = await context.policyEngine.evaluate(
                capability: tool.permission,
                runID: context.runID,
                sessionID: context.sessionID,
                toolName: tool.name,
                payloadJSON: call.argumentsJSON
            )
            switch decision.outcome {
            case .approved:
                break
            case .needsApproval:
                throw AgentToolError.permissionNeedsApproval(AgentPermissionRequest(
                    id: decision.requestID,
                    runID: context.runID,
                    sessionID: context.sessionID,
                    capability: tool.permission,
                    toolName: tool.name,
                    payloadJSON: call.argumentsJSON
                ))
            case .denied:
                throw AgentToolError.permissionDenied(decision.reason)
            }
        }
        let arguments = try AgentToolArguments(json: call.argumentsJSON)
        var result = try await tool.execute(arguments: arguments, context: context)
        result.runID = context.runID
        result.sessionID = context.sessionID
        return result
    }
}
