import Foundation
import ConnorGraphCore

public indirect enum AgentToolInputSchema: Sendable, Equatable {
    case string(description: String)
    case stringEnumeration(values: [String], description: String)
    case integer(description: String)
    case number(description: String)
    case boolean(description: String)
    case array(items: AgentToolInputSchema, description: String)
    case object(properties: [String: AgentToolInputSchema], required: [String])
    case closedObject(properties: [String: AgentToolInputSchema], required: [String])
    case nullable(AgentToolInputSchema)

    public var isOpenAIStrictCompatible: Bool {
        switch self {
        case .string, .stringEnumeration, .integer, .number, .boolean:
            return true
        case .array(let items, _), .nullable(let items):
            return items.isOpenAIStrictCompatible
        case .object:
            return false
        case .closedObject(let properties, let required):
            return Set(required) == Set(properties.keys) && properties.values.allSatisfy(\.isOpenAIStrictCompatible)
        }
    }

    public var jsonObject: [String: Any] {
        switch self {
        case .string(let description):
            return ["type": "string", "description": description]
        case .stringEnumeration(let values, let description):
            return ["type": "string", "enum": values, "description": description]
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
        case .closedObject(let properties, let required):
            return [
                "type": "object",
                "properties": properties.mapValues { $0.jsonObject },
                "required": required,
                "additionalProperties": false
            ]
        case .nullable(let wrapped):
            var object = wrapped.jsonObject
            if let type = object["type"] as? String {
                object["type"] = [type, "null"]
            } else if let types = object["type"] as? [String], !types.contains("null") {
                object["type"] = types + ["null"]
            }
            return object
        }
    }
}

public struct AgentToolSchemaValidationIssue: Sendable, Equatable, CustomStringConvertible {
    public var toolName: String
    public var path: String
    public var message: String

    public init(toolName: String, path: String, message: String) {
        self.toolName = toolName
        self.path = path
        self.message = message
    }

    public var description: String { "\(toolName) \(path): \(message)" }
}

public extension AgentToolInputSchema {
    func validationIssues(toolName: String, path: String = "$") -> [AgentToolSchemaValidationIssue] {
        switch self {
        case .string, .integer, .number, .boolean:
            return []
        case .stringEnumeration(let values, _):
            return values.isEmpty
                ? [AgentToolSchemaValidationIssue(toolName: toolName, path: "\(path).enum", message: "must contain at least one value")]
                : []
        case .array(let items, _):
            return items.validationIssues(toolName: toolName, path: "\(path).items")
        case .nullable(let wrapped):
            return wrapped.validationIssues(toolName: toolName, path: path)
        case let .object(properties, required), let .closedObject(properties, required):
            var issues: [AgentToolSchemaValidationIssue] = []
            let duplicateRequired = Dictionary(grouping: required, by: { $0 }).filter { $0.value.count > 1 }.keys.sorted()
            for name in duplicateRequired {
                issues.append(AgentToolSchemaValidationIssue(
                    toolName: toolName,
                    path: "\(path).required",
                    message: "contains duplicate property \(name)"
                ))
            }
            for name in Set(required).subtracting(properties.keys).sorted() {
                issues.append(AgentToolSchemaValidationIssue(
                    toolName: toolName,
                    path: "\(path).required",
                    message: "references missing property \(name)"
                ))
            }
            for name in properties.keys.sorted() {
                issues.append(contentsOf: properties[name]!.validationIssues(
                    toolName: toolName,
                    path: "\(path).properties.\(name)"
                ))
            }
            return issues
        }
    }

    func argumentValidationIssues(_ value: SendableJSONValue, path: String = "$") -> [String] {
        switch (self, value) {
        case (.string, .string), (.integer, .int), (.number, .int), (.number, .double), (.boolean, .bool):
            return []
        case let (.stringEnumeration(values, _), .string(value)):
            return values.contains(value) ? [] : ["\(path) must be one of: \(values.joined(separator: ", "))"]
        case let (.array(items, _), .array(values)):
            return values.enumerated().flatMap { index, value in
                items.argumentValidationIssues(value, path: "\(path)[\(index)]")
            }
        case let (.object(properties, required), .object(values)):
            return Self.objectArgumentValidationIssues(
                properties: properties,
                required: required,
                values: values,
                rejectsUnknownProperties: false,
                path: path
            )
        case let (.closedObject(properties, required), .object(values)):
            return Self.objectArgumentValidationIssues(
                properties: properties,
                required: required,
                values: values,
                rejectsUnknownProperties: true,
                path: path
            )
        case (.nullable, .null):
            return []
        case let (.nullable(wrapped), value):
            return wrapped.argumentValidationIssues(value, path: path)
        default:
            return ["\(path) must be \(expectedTypeDescription)"]
        }
    }

    private static func objectArgumentValidationIssues(
        properties: [String: AgentToolInputSchema],
        required: [String],
        values: [String: SendableJSONValue],
        rejectsUnknownProperties: Bool,
        path: String
    ) -> [String] {
        var issues = required.filter { values[$0] == nil }.sorted().map { "\(path).\($0) is required" }
        if rejectsUnknownProperties {
            issues += Set(values.keys).subtracting(properties.keys).sorted().map { "\(path).\($0) is not supported" }
        }
        for key in Set(values.keys).intersection(properties.keys).sorted() {
            issues += properties[key]!.argumentValidationIssues(values[key]!, path: "\(path).\(key)")
        }
        return issues
    }

    private var expectedTypeDescription: String {
        switch self {
        case .string: "a string"
        case .stringEnumeration: "a supported string value"
        case .integer: "an integer"
        case .number: "a number"
        case .boolean: "a boolean"
        case .array: "an array"
        case .object, .closedObject: "an object"
        case .nullable(let wrapped): "null or \(wrapped.expectedTypeDescription)"
        }
    }
}

public struct AgentToolDefinition: Sendable, Equatable {
    public var name: String
    public var description: String
    public var inputSchema: AgentToolInputSchema
    public var inputExamples: [[String: SendableJSONValue]]

    public init(name: String, description: String, inputSchema: AgentToolInputSchema, inputExamples: [[String: SendableJSONValue]] = []) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.inputExamples = inputExamples
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

    public func iso8601Date(_ key: String) throws -> Date? {
        guard let value = string(key) else { return nil }
        guard let date = ISO8601DateFormatter().date(from: value) else {
            throw AgentToolError.invalidArguments("\(key) must be a valid ISO-8601 timestamp")
        }
        return date
    }
}

public extension SendableJSONValue {
    var jsonCompatibleObject: Any {
        switch self {
        case .string(let value): value
        case .int(let value): value
        case .double(let value): value
        case .bool(let value): value
        case .object(let value): value.mapValues(\.jsonCompatibleObject)
        case .array(let value): value.map(\.jsonCompatibleObject)
        case .null: NSNull()
        }
    }

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
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else if value.doubleValue.rounded(.towardZero) == value.doubleValue {
                self = .int(value.intValue)
            } else {
                self = .double(value.doubleValue)
            }
        case let value as Bool:
            self = .bool(value)
        case let value as Int:
            self = .int(value)
        case let value as Double:
            self = .double(value)
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
    public var currentUserMessageID: String?
    public var toolCallID: String
    public var policyEngine: AgentPolicyEngine
    public var approvedCapabilities: Set<AgentPermissionCapability>

    public init(
        runID: String,
        sessionID: String,
        groupID: String,
        userPrompt: String,
        toolCallID: String,
        policyEngine: AgentPolicyEngine,
        currentUserMessageID: String? = nil
    ) {
        self.init(
            runID: runID,
            sessionID: sessionID,
            groupID: groupID,
            userPrompt: userPrompt,
            toolCallID: toolCallID,
            policyEngine: policyEngine,
            approvedCapabilities: [],
            currentUserMessageID: currentUserMessageID
        )
    }

    public init(
        runID: String,
        sessionID: String,
        groupID: String,
        userPrompt: String,
        toolCallID: String,
        policyEngine: AgentPolicyEngine,
        approvedCapabilities: Set<AgentPermissionCapability>,
        currentUserMessageID: String? = nil
    ) {
        self.runID = runID
        self.sessionID = sessionID
        self.groupID = groupID
        self.userPrompt = userPrompt
        self.currentUserMessageID = currentUserMessageID
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
    var inputExamples: [[String: SendableJSONValue]] { get }

    func preflight(call: AgentToolCall, context: AgentToolExecutionContext) async throws
    func approvalPayloadJSON(for call: AgentToolCall, context: AgentToolExecutionContext) async -> String
    func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult
}

public extension AgentTool {
    var inputExamples: [[String: SendableJSONValue]] { [] }

    func preflight(call: AgentToolCall, context: AgentToolExecutionContext) async throws {}

    func approvalPayloadJSON(for call: AgentToolCall, context: AgentToolExecutionContext) async -> String {
        call.argumentsJSON
    }
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

public struct AgentToolDuplicateRegistration: Sendable, Equatable {
    public var name: String
    public var replacedDescription: String
    public var replacementDescription: String

    public init(name: String, replacedDescription: String, replacementDescription: String) {
        self.name = name
        self.replacedDescription = replacedDescription
        self.replacementDescription = replacementDescription
    }
}

public struct AgentToolRegistry: Sendable {
    private var tools: [String: any AgentTool]
    public private(set) var duplicateRegistrations: [AgentToolDuplicateRegistration]

    public init(tools: [any AgentTool] = []) {
        self.tools = [:]
        self.duplicateRegistrations = []
        for tool in tools { register(tool) }
    }

    public mutating func register(_ tool: any AgentTool) {
        if let existing = tools[tool.name] {
            duplicateRegistrations.append(AgentToolDuplicateRegistration(name: tool.name, replacedDescription: existing.description, replacementDescription: tool.description))
        }
        tools[tool.name] = tool
    }

    public func definition(named name: String) -> AgentToolDefinition? {
        guard let tool = tools[name] else { return nil }
        return AgentToolDefinition(name: tool.name, description: tool.description, inputSchema: tool.inputSchema, inputExamples: tool.inputExamples)
    }

    public func permission(named name: String) -> AgentPermissionCapability? {
        tools[name]?.permission
    }

    public var definitions: [AgentToolDefinition] {
        tools.keys.sorted().compactMap { definition(named: $0) }
    }

    public var schemaValidationIssues: [AgentToolSchemaValidationIssue] {
        definitions.flatMap { definition in
            definition.inputSchema.validationIssues(toolName: definition.name)
        }
    }

    public func execute(_ call: AgentToolCall, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let tool = tools[call.name] else {
            throw AgentToolError.unknownTool(call.name)
        }
        let arguments = try AgentToolArguments(json: call.argumentsJSON)
        let argumentObject = SendableJSONValue.object(arguments.values)
        let argumentIssues = tool.inputSchema.argumentValidationIssues(argumentObject)
        guard argumentIssues.isEmpty else {
            throw AgentToolError.invalidArguments(argumentIssues.joined(separator: "; "))
        }
        try await tool.preflight(call: call, context: context)
        var executionContext = context
        if !context.approvedCapabilities.contains(tool.permission) {
            let approvalPayloadJSON = await tool.approvalPayloadJSON(for: call, context: context)
            let decision = await context.policyEngine.evaluate(
                capability: tool.permission,
                runID: context.runID,
                sessionID: context.sessionID,
                toolName: tool.name,
                payloadJSON: approvalPayloadJSON
            )
            switch decision.outcome {
            case .approved:
                executionContext = context.approving(tool.permission)
            case .needsApproval:
                throw AgentToolError.permissionNeedsApproval(AgentPermissionRequest(
                    id: decision.requestID,
                    runID: context.runID,
                    sessionID: context.sessionID,
                    capability: tool.permission,
                    toolName: tool.name,
                    payloadJSON: approvalPayloadJSON
                ))
            case .denied:
                throw AgentToolError.permissionDenied(decision.reason)
            }
        }
        var result = try await tool.execute(arguments: arguments, context: executionContext)
        result.runID = context.runID
        result.sessionID = context.sessionID
        return result
    }
}
