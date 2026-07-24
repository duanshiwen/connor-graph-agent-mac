import Foundation

public enum MCPJSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: MCPJSONValue])
    case array([MCPJSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([MCPJSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: MCPJSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var objectValue: [String: MCPJSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    public var arrayValue: [MCPJSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }
}

public enum MCPJSONRPCID: Codable, Sendable, Equatable {
    case string(String)
    case number(Int)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self = .number(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        }
    }
}

public struct MCPJSONRPCError: Codable, Sendable, Equatable {
    public var code: Int
    public var message: String
    public var data: MCPJSONValue?

    public init(code: Int, message: String, data: MCPJSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
}

public struct MCPJSONRPCMessage: Codable, Sendable, Equatable {
    public var jsonrpc: String
    public var id: MCPJSONRPCID?
    public var method: String?
    public var params: MCPJSONValue?
    public var result: MCPJSONValue?
    public var error: MCPJSONRPCError?

    public init(
        jsonrpc: String = "2.0",
        id: MCPJSONRPCID? = nil,
        method: String? = nil,
        params: MCPJSONValue? = nil,
        result: MCPJSONValue? = nil,
        error: MCPJSONRPCError? = nil
    ) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.method = method
        self.params = params
        self.result = result
        self.error = error
    }
}

public protocol MCPClientTransport: Sendable {
    func send(_ message: MCPJSONRPCMessage) async throws -> MCPJSONRPCMessage?
    func close() async throws
}

public struct MCPImplementationInfo: Codable, Sendable, Equatable {
    public var name: String
    public var version: String

    public init(name: String, version: String) {
        self.name = name
        self.version = version
    }
}

public struct MCPInitializeResult: Sendable, Equatable {
    public var protocolVersion: String
    public var capabilities: MCPJSONValue
    public var serverInfo: MCPImplementationInfo

    public init(protocolVersion: String, capabilities: MCPJSONValue, serverInfo: MCPImplementationInfo) {
        self.protocolVersion = protocolVersion
        self.capabilities = capabilities
        self.serverInfo = serverInfo
    }
}

public struct MCPToolDefinition: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    public var description: String
    public var inputSchema: MCPJSONValue

    public init(name: String, description: String = "", inputSchema: MCPJSONValue = .object([:])) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

public struct MCPToolContent: Sendable, Equatable {
    public var type: String
    public var text: String?

    public init(type: String, text: String? = nil) {
        self.type = type
        self.text = text
    }
}

public struct MCPToolCallResult: Sendable, Equatable {
    public var content: [MCPToolContent]
    public var isError: Bool

    public init(content: [MCPToolContent], isError: Bool = false) {
        self.content = content
        self.isError = isError
    }
}

public enum MCPJSONRPCClientError: Error, Sendable, Equatable, CustomStringConvertible {
    case missingResponse(String)
    case missingResult(String)
    case invalidResult(String)
    case serverError(code: Int, message: String)

    public var description: String {
        switch self {
        case .missingResponse(let method): "missingResponse: \(method)"
        case .missingResult(let method): "missingResult: \(method)"
        case .invalidResult(let method): "invalidResult: \(method)"
        case .serverError(let code, let message): "serverError: \(code) \(message)"
        }
    }
}

public actor MCPJSONRPCClient<Transport: MCPClientTransport> {
    private var transport: Transport
    private var clientName: String
    private var clientVersion: String
    private var protocolVersion: String
    private var nextID: Int = 1

    public init(
        transport: Transport,
        clientName: String,
        clientVersion: String,
        protocolVersion: String = "2025-06-18"
    ) {
        self.transport = transport
        self.clientName = clientName
        self.clientVersion = clientVersion
        self.protocolVersion = protocolVersion
    }

    public func initialize() async throws -> MCPInitializeResult {
        let result = try await request(method: "initialize", params: .object([
            "protocolVersion": .string(protocolVersion),
            "capabilities": .object([:]),
            "clientInfo": .object([
                "name": .string(clientName),
                "version": .string(clientVersion)
            ])
        ]))
        let parsed = try parseInitializeResult(result)
        _ = try await transport.send(MCPJSONRPCMessage(method: "notifications/initialized"))
        return parsed
    }

    public func listTools() async throws -> [MCPToolDefinition] {
        var tools: [MCPToolDefinition] = []
        var seenNames: Set<String> = []
        var seenCursors: Set<String> = []
        var cursor: String?
        repeat {
            let params: MCPJSONValue = cursor.map { .object(["cursor": .string($0)]) } ?? .object([:])
            let result = try await request(method: "tools/list", params: params)
            guard let object = result.objectValue,
                  let toolValues = object["tools"]?.arrayValue else {
                throw MCPJSONRPCClientError.invalidResult("tools/list")
            }
            for value in toolValues {
                let object = value.objectValue ?? [:]
                let tool = MCPToolDefinition(
                    name: object["name"]?.stringValue ?? "",
                    description: object["description"]?.stringValue ?? "",
                    inputSchema: object["inputSchema"] ?? .object([:])
                )
                if seenNames.insert(tool.name).inserted { tools.append(tool) }
            }
            cursor = object["nextCursor"]?.stringValue
            if let cursor, !seenCursors.insert(cursor).inserted {
                throw MCPJSONRPCClientError.invalidResult("tools/list nextCursor cycle")
            }
        } while cursor != nil
        return tools
    }

    public func callTool(name: String, arguments: MCPJSONValue = .object([:])) async throws -> MCPToolCallResult {
        let result = try await request(method: "tools/call", params: .object([
            "name": .string(name),
            "arguments": arguments
        ]))
        return try parseToolCallResult(result)
    }

    public func shutdown() async throws {
        try await transport.close()
    }

    private func request(method: String, params: MCPJSONValue) async throws -> MCPJSONValue {
        let id = MCPJSONRPCID.number(nextID)
        nextID += 1
        guard let response = try await transport.send(MCPJSONRPCMessage(id: id, method: method, params: params)) else {
            throw MCPJSONRPCClientError.missingResponse(method)
        }
        if let error = response.error {
            throw MCPJSONRPCClientError.serverError(code: error.code, message: error.message)
        }
        guard let result = response.result else {
            throw MCPJSONRPCClientError.missingResult(method)
        }
        return result
    }

    private func parseInitializeResult(_ value: MCPJSONValue) throws -> MCPInitializeResult {
        guard let object = value.objectValue,
              let version = object["protocolVersion"]?.stringValue,
              let serverInfoObject = object["serverInfo"]?.objectValue else {
            throw MCPJSONRPCClientError.invalidResult("initialize")
        }
        return MCPInitializeResult(
            protocolVersion: version,
            capabilities: object["capabilities"] ?? .object([:]),
            serverInfo: MCPImplementationInfo(
                name: serverInfoObject["name"]?.stringValue ?? "unknown",
                version: serverInfoObject["version"]?.stringValue ?? "unknown"
            )
        )
    }

    private func parseToolCallResult(_ value: MCPJSONValue) throws -> MCPToolCallResult {
        guard let object = value.objectValue else { throw MCPJSONRPCClientError.invalidResult("tools/call") }
        let contents = object["content"]?.arrayValue?.map { item -> MCPToolContent in
            let object = item.objectValue ?? [:]
            return MCPToolContent(type: object["type"]?.stringValue ?? "unknown", text: object["text"]?.stringValue)
        } ?? []
        return MCPToolCallResult(content: contents, isError: object["isError"]?.boolValue ?? false)
    }
}

public actor MockMCPClientTransport: MCPClientTransport {
    public private(set) var sent: [MCPJSONRPCMessage] = []
    public private(set) var didClose = false
    private var responses: [MCPJSONRPCMessage]

    public init(responses: [MCPJSONRPCMessage] = []) {
        self.responses = responses
    }

    public func send(_ message: MCPJSONRPCMessage) async throws -> MCPJSONRPCMessage? {
        sent.append(message)
        if message.id == nil { return nil }
        guard !responses.isEmpty else { return nil }
        return responses.removeFirst()
    }

    public func close() async throws {
        didClose = true
    }
}
