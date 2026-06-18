import Foundation
import ConnorGraphAgent
import ConnorGraphCore

public struct MCPToolRoute: Sendable, Equatable {
    public var exposedToolName: String
    public var sourceID: String
    public var rawToolName: String

    public init(exposedToolName: String, sourceID: String, rawToolName: String) {
        self.exposedToolName = exposedToolName
        self.sourceID = sourceID
        self.rawToolName = rawToolName
    }
}

public enum MCPToolRegistryBridgeError: Error, Sendable, Equatable, CustomStringConvertible {
    case unknownMCPTool(String)
    case missingSource(String)
    case invalidArguments(String)

    public var description: String {
        switch self {
        case .unknownMCPTool(let name): "unknownMCPTool: \(name)"
        case .missingSource(let sourceID): "missingSource: \(sourceID)"
        case .invalidArguments(let message): "invalidArguments: \(message)"
        }
    }
}

public struct MCPToolRegistryBridge: Sendable {
    public var routes: [String: MCPToolRoute]

    public init(routes: [String: MCPToolRoute] = [:]) {
        self.routes = routes
    }

    public static func buildRoutes(catalog: [MCPSourceToolDescriptor]) -> [String: MCPToolRoute] {
        Dictionary(uniqueKeysWithValues: catalog.map { descriptor in
            let exposedName = descriptor.name.hasPrefix("mcp__")
                ? descriptor.name
                : MCPSourceRuntime<MockMCPClientTransport>.exposedToolName(sourceID: descriptor.sourceID, rawToolName: descriptor.rawName)
            return (exposedName, MCPToolRoute(exposedToolName: exposedName, sourceID: descriptor.sourceID, rawToolName: descriptor.rawName))
        })
    }

    public func registerTools(
        catalog: [MCPSourceToolDescriptor],
        into registry: inout AgentToolRegistry,
        router: MCPToolRouting
    ) {
        for descriptor in catalog {
            let exposedName = descriptor.name.hasPrefix("mcp__")
                ? descriptor.name
                : MCPSourceRuntime<MockMCPClientTransport>.exposedToolName(sourceID: descriptor.sourceID, rawToolName: descriptor.rawName)
            registry.register(MCPRoutedAgentTool(
                descriptor: MCPSourceToolDescriptor(
                    sourceID: descriptor.sourceID,
                    name: exposedName,
                    rawName: descriptor.rawName,
                    description: descriptor.description,
                    inputSchema: descriptor.inputSchema,
                    requiredCapabilities: descriptor.requiredCapabilities,
                    governancePolicy: descriptor.governancePolicy,
                    definitionFingerprint: descriptor.definitionFingerprint,
                    integrityStatus: descriptor.integrityStatus
                ),
                router: router
            ))
        }
    }

    public static func agentSchema(from value: MCPJSONValue) -> AgentToolInputSchema {
        guard let object = value.objectValue else { return .object(properties: [:], required: []) }
        let type = object["type"]?.stringValue ?? "object"
        let description = object["description"]?.stringValue ?? ""
        switch type {
        case "string": return .string(description: description)
        case "integer": return .integer(description: description)
        case "number": return .number(description: description)
        case "boolean": return .boolean(description: description)
        case "array":
            return .array(items: agentSchema(from: object["items"] ?? .object([:])), description: description)
        case "object":
            let propertiesObject = object["properties"]?.objectValue ?? [:]
            let properties = propertiesObject.mapValues { agentSchema(from: $0) }
            let required = object["required"]?.arrayValue?.compactMap(\.stringValue) ?? []
            return .object(properties: properties, required: required)
        default:
            return .object(properties: [:], required: [])
        }
    }
}

public protocol MCPToolRouting: Sendable {
    func callMCPTool(
        exposedToolName: String,
        sourceID: String,
        rawToolName: String,
        arguments: MCPJSONValue,
        context: AgentToolExecutionContext
    ) async throws -> AgentToolResult
}

public struct MCPRoutedAgentTool: AgentTool {
    public var descriptor: MCPSourceToolDescriptor
    public var router: MCPToolRouting

    public init(descriptor: MCPSourceToolDescriptor, router: MCPToolRouting) {
        self.descriptor = descriptor
        self.router = router
    }

    public var name: String { descriptor.name }

    public var description: String {
        let base = descriptor.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "MCP source `\(descriptor.sourceID)` tool `\(descriptor.rawName)`."
        return base.isEmpty ? prefix : "\(prefix) \(base)"
    }

    public var permission: AgentPermissionCapability {
        descriptor.requiredCapabilities.first ?? .externalNetwork
    }

    public var inputSchema: AgentToolInputSchema {
        MCPToolRegistryBridge.agentSchema(from: descriptor.inputSchema)
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        try await router.callMCPTool(
            exposedToolName: descriptor.name,
            sourceID: descriptor.sourceID,
            rawToolName: descriptor.rawName,
            arguments: MCPJSONValue(agentArguments: arguments),
            context: context
        )
    }
}

public extension MCPJSONValue {
    init(agentArguments: AgentToolArguments) {
        self = .object(agentArguments.values.mapValues { MCPJSONValue(sendableJSONValue: $0) })
    }

    init(sendableJSONValue value: SendableJSONValue) {
        switch value {
        case .string(let string): self = .string(string)
        case .int(let int): self = .number(Double(int))
        case .double(let double): self = .number(double)
        case .bool(let bool): self = .bool(bool)
        case .object(let object): self = .object(object.mapValues { MCPJSONValue(sendableJSONValue: $0) })
        case .array(let array): self = .array(array.map { MCPJSONValue(sendableJSONValue: $0) })
        case .null: self = .null
        }
    }
}
