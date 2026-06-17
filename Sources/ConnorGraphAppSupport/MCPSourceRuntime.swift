import Foundation
import ConnorGraphAgent
import ConnorGraphCore


public enum MCPSourceRuntimeHealthStatus: String, Codable, Sendable, Equatable, CaseIterable {
    case unknown
    case healthy
    case degraded
    case failed
}

public enum MCPSourceRuntimeLifecycleState: String, Codable, Sendable, Equatable, CaseIterable {
    case draft
    case validating
    case enabled
    case disabled
    case needsCredential
    case failed
}

public struct MCPSourceRuntimeCapabilitySnapshot: Codable, Sendable, Equatable {
    public var protocolVersion: String
    public var serverName: String
    public var serverVersion: String
    public var supportsTools: Bool
    public var supportsResources: Bool
    public var supportsPrompts: Bool
    public var supportsSampling: Bool
    public var supportsRoots: Bool
    public var supportsElicitation: Bool
    public var supportsLogging: Bool
    public var supportsProgress: Bool
    public var supportsCancellation: Bool
    public var toolCount: Int
    public var toolNames: [String]

    public init(
        protocolVersion: String,
        serverName: String,
        serverVersion: String,
        supportsTools: Bool = false,
        supportsResources: Bool = false,
        supportsPrompts: Bool = false,
        supportsSampling: Bool = false,
        supportsRoots: Bool = false,
        supportsElicitation: Bool = false,
        supportsLogging: Bool = false,
        supportsProgress: Bool = false,
        supportsCancellation: Bool = false,
        toolCount: Int = 0,
        toolNames: [String] = []
    ) {
        self.protocolVersion = protocolVersion
        self.serverName = serverName
        self.serverVersion = serverVersion
        self.supportsTools = supportsTools
        self.supportsResources = supportsResources
        self.supportsPrompts = supportsPrompts
        self.supportsSampling = supportsSampling
        self.supportsRoots = supportsRoots
        self.supportsElicitation = supportsElicitation
        self.supportsLogging = supportsLogging
        self.supportsProgress = supportsProgress
        self.supportsCancellation = supportsCancellation
        self.toolCount = toolCount
        self.toolNames = toolNames
    }

    public static func build(initialization: MCPInitializeResult, tools: [MCPToolDefinition]) -> MCPSourceRuntimeCapabilitySnapshot {
        let capabilities = initialization.capabilities.objectValue ?? [:]
        return MCPSourceRuntimeCapabilitySnapshot(
            protocolVersion: initialization.protocolVersion,
            serverName: initialization.serverInfo.name,
            serverVersion: initialization.serverInfo.version,
            supportsTools: capabilities["tools"] != nil || !tools.isEmpty,
            supportsResources: capabilities["resources"] != nil,
            supportsPrompts: capabilities["prompts"] != nil,
            supportsSampling: capabilities["sampling"] != nil,
            supportsRoots: capabilities["roots"] != nil,
            supportsElicitation: capabilities["elicitation"] != nil,
            supportsLogging: capabilities["logging"] != nil,
            supportsProgress: capabilities["progress"] != nil,
            supportsCancellation: capabilities["cancellation"] != nil,
            toolCount: tools.count,
            toolNames: tools.map(\.name).sorted()
        )
    }
}

public struct MCPSourceRuntimeHealthRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String { sourceID }
    public var sourceID: String
    public var healthStatus: MCPSourceRuntimeHealthStatus
    public var lifecycleState: MCPSourceRuntimeLifecycleState
    public var lastCheckedAt: Date
    public var lastConnectedAt: Date?
    public var lastDiscoveredAt: Date?
    public var lastErrorMessage: String?
    public var capabilitySnapshot: MCPSourceRuntimeCapabilitySnapshot?
    public var discoveredToolCount: Int
    public var auditedInvocationCount: Int

    public init(
        sourceID: String,
        healthStatus: MCPSourceRuntimeHealthStatus = .unknown,
        lifecycleState: MCPSourceRuntimeLifecycleState = .draft,
        lastCheckedAt: Date = Date(),
        lastConnectedAt: Date? = nil,
        lastDiscoveredAt: Date? = nil,
        lastErrorMessage: String? = nil,
        capabilitySnapshot: MCPSourceRuntimeCapabilitySnapshot? = nil,
        discoveredToolCount: Int = 0,
        auditedInvocationCount: Int = 0
    ) {
        self.sourceID = sourceID
        self.healthStatus = healthStatus
        self.lifecycleState = lifecycleState
        self.lastCheckedAt = lastCheckedAt
        self.lastConnectedAt = lastConnectedAt
        self.lastDiscoveredAt = lastDiscoveredAt
        self.lastErrorMessage = lastErrorMessage
        self.capabilitySnapshot = capabilitySnapshot
        self.discoveredToolCount = discoveredToolCount
        self.auditedInvocationCount = auditedInvocationCount
    }
}

public enum MCPSourceRuntimeAuditEventKind: String, Codable, Sendable, Equatable, CaseIterable {
    case discoveryStarted
    case discoveryFinished
    case toolPermissionRequested
    case toolStarted
    case toolFinished
    case toolFailed
}

public struct MCPSourceRuntimeAuditRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var sourceID: String
    public var runID: String?
    public var sessionID: String?
    public var eventKind: MCPSourceRuntimeAuditEventKind
    public var rawToolName: String?
    public var prefixedToolName: String?
    public var permissionCapability: AgentPermissionCapability?
    public var requiredCapabilities: [AgentPermissionCapability]
    public var timestamp: Date
    public var resultSummary: String?
    public var errorSummary: String?

    public init(
        id: UUID = UUID(),
        sourceID: String,
        runID: String? = nil,
        sessionID: String? = nil,
        eventKind: MCPSourceRuntimeAuditEventKind,
        rawToolName: String? = nil,
        prefixedToolName: String? = nil,
        permissionCapability: AgentPermissionCapability? = nil,
        requiredCapabilities: [AgentPermissionCapability] = [],
        timestamp: Date = Date(),
        resultSummary: String? = nil,
        errorSummary: String? = nil
    ) {
        self.id = id
        self.sourceID = sourceID
        self.runID = runID
        self.sessionID = sessionID
        self.eventKind = eventKind
        self.rawToolName = rawToolName
        self.prefixedToolName = prefixedToolName
        self.permissionCapability = permissionCapability
        self.requiredCapabilities = requiredCapabilities
        self.timestamp = timestamp
        self.resultSummary = resultSummary
        self.errorSummary = errorSummary
    }
}

public struct MCPSourceRuntimeDiscoverySnapshot: Sendable, Equatable {
    public var sourceID: String
    public var healthRecord: MCPSourceRuntimeHealthRecord
    public var catalog: [MCPSourceToolDescriptor]
    public var auditRecords: [MCPSourceRuntimeAuditRecord]

    public init(sourceID: String, healthRecord: MCPSourceRuntimeHealthRecord, catalog: [MCPSourceToolDescriptor], auditRecords: [MCPSourceRuntimeAuditRecord]) {
        self.sourceID = sourceID
        self.healthRecord = healthRecord
        self.catalog = catalog
        self.auditRecords = auditRecords
    }
}

public struct MCPSourceToolDescriptor: Codable, Sendable, Equatable, Identifiable {
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
    public var auditRecords: [MCPSourceRuntimeAuditRecord]

    public init(
        sourceID: String,
        rawToolName: String,
        prefixedToolName: String,
        permissionRequest: AgentPermissionRequest,
        toolCall: AgentToolCall,
        result: AgentToolResult,
        events: [AgentEvent],
        auditRecords: [MCPSourceRuntimeAuditRecord] = []
    ) {
        self.sourceID = sourceID
        self.rawToolName = rawToolName
        self.prefixedToolName = prefixedToolName
        self.permissionRequest = permissionRequest
        self.toolCall = toolCall
        self.result = result
        self.events = events
        self.auditRecords = auditRecords
    }
}

public enum MCPSourceRuntimeError: Error, Sendable, Equatable, CustomStringConvertible {
    case sourceNotEnabled(String)
    case invalidPrefixedToolName(String)
    case sourcePrefixMismatch(expected: String, actual: String)
    case invalidSourceToolName(String)

    public var description: String {
        switch self {
        case .sourceNotEnabled(let sourceID): "sourceNotEnabled: \(sourceID)"
        case .invalidPrefixedToolName(let name): "invalidPrefixedToolName: \(name)"
        case .sourcePrefixMismatch(let expected, let actual): "sourcePrefixMismatch: expected \(expected), actual \(actual)"
        case .invalidSourceToolName(let name): "invalidSourceToolName: \(name)"
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
        try await discoverRuntimeState().catalog
    }

    public func discoverRuntimeState(now: Date = Date()) async throws -> MCPSourceRuntimeDiscoverySnapshot {
        let discoveryStarted = MCPSourceRuntimeAuditRecord(
            sourceID: configuration.sourceID,
            eventKind: .discoveryStarted,
            requiredCapabilities: configuration.allowedCapabilities,
            timestamp: now
        )
        do {
            let initialization = try await client.initialize()
            let tools = try await client.listTools()
            let catalog = toolCatalog(from: tools)
            let capabilitySnapshot = MCPSourceRuntimeCapabilitySnapshot.build(initialization: initialization, tools: tools)
            let health = MCPSourceRuntimeHealthRecord(
                sourceID: configuration.sourceID,
                healthStatus: .healthy,
                lifecycleState: lifecycleStateForCurrentConfiguration(),
                lastCheckedAt: now,
                lastConnectedAt: now,
                lastDiscoveredAt: now,
                lastErrorMessage: nil,
                capabilitySnapshot: capabilitySnapshot,
                discoveredToolCount: catalog.count,
                auditedInvocationCount: 0
            )
            let discoveryFinished = MCPSourceRuntimeAuditRecord(
                sourceID: configuration.sourceID,
                eventKind: .discoveryFinished,
                requiredCapabilities: configuration.allowedCapabilities,
                timestamp: now,
                resultSummary: "Discovered \(catalog.count) MCP tools from \(initialization.serverInfo.name)."
            )
            return MCPSourceRuntimeDiscoverySnapshot(
                sourceID: configuration.sourceID,
                healthRecord: health,
                catalog: catalog,
                auditRecords: [discoveryStarted, discoveryFinished]
            )
        } catch {
            let health = MCPSourceRuntimeHealthRecord(
                sourceID: configuration.sourceID,
                healthStatus: .failed,
                lifecycleState: .failed,
                lastCheckedAt: now,
                lastErrorMessage: String(describing: error),
                discoveredToolCount: 0,
                auditedInvocationCount: 0
            )
            let failed = MCPSourceRuntimeAuditRecord(
                sourceID: configuration.sourceID,
                eventKind: .discoveryFinished,
                requiredCapabilities: configuration.allowedCapabilities,
                timestamp: now,
                errorSummary: String(describing: error)
            )
            return MCPSourceRuntimeDiscoverySnapshot(
                sourceID: configuration.sourceID,
                healthRecord: health,
                catalog: [],
                auditRecords: [discoveryStarted, failed]
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
        let permissionAudit = MCPSourceRuntimeAuditRecord(
            sourceID: configuration.sourceID,
            runID: runID,
            sessionID: sessionID,
            eventKind: .toolPermissionRequested,
            rawToolName: rawName,
            prefixedToolName: prefixedToolName,
            permissionCapability: .externalNetwork,
            requiredCapabilities: configuration.allowedCapabilities
        )
        let startedAudit = MCPSourceRuntimeAuditRecord(
            sourceID: configuration.sourceID,
            runID: runID,
            sessionID: sessionID,
            eventKind: .toolStarted,
            rawToolName: rawName,
            prefixedToolName: prefixedToolName,
            requiredCapabilities: configuration.allowedCapabilities
        )
        let mcpResult = try await client.callTool(name: rawName, arguments: arguments)
        let contentText = mcpResult.content.compactMap(\.text).joined(separator: "\n")
        let finishedAudit = MCPSourceRuntimeAuditRecord(
            sourceID: configuration.sourceID,
            runID: runID,
            sessionID: sessionID,
            eventKind: mcpResult.isError ? .toolFailed : .toolFinished,
            rawToolName: rawName,
            prefixedToolName: prefixedToolName,
            requiredCapabilities: configuration.allowedCapabilities,
            resultSummary: mcpResult.isError ? nil : contentText,
            errorSummary: mcpResult.isError ? contentText : nil
        )
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
            ],
            auditRecords: [permissionAudit, startedAudit, finishedAudit]
        )
    }

    public func shutdown() async throws {
        try await client.shutdown()
    }

    private func toolCatalog(from tools: [MCPToolDefinition]) -> [MCPSourceToolDescriptor] {
        tools.map { tool in
            MCPSourceToolDescriptor(
                sourceID: configuration.sourceID,
                name: Self.exposedToolName(sourceID: configuration.sourceID, rawToolName: tool.name),
                rawName: tool.name,
                description: tool.description,
                inputSchema: tool.inputSchema,
                requiredCapabilities: configuration.allowedCapabilities
            )
        }
    }

    private func lifecycleStateForCurrentConfiguration() -> MCPSourceRuntimeLifecycleState {
        switch configuration.status {
        case .draft: .draft
        case .enabled: configuration.credentialRequirement == .none ? .enabled : .enabled
        case .disabled: .disabled
        case .needsReview: .validating
        case .deprecated: .disabled
        }
    }

    private func rawToolName(from prefixedToolName: String) throws -> String {
        if prefixedToolName.hasPrefix("mcp__") {
            let prefix = "mcp__\(configuration.sourceID)__"
            guard prefixedToolName.hasPrefix(prefix) else {
                throw MCPSourceRuntimeError.sourcePrefixMismatch(expected: prefix, actual: prefixedToolName)
            }
            let raw = String(prefixedToolName.dropFirst(prefix.count))
            guard !raw.isEmpty else { throw MCPSourceRuntimeError.invalidPrefixedToolName(prefixedToolName) }
            return raw
        }

        // Backward compatibility for existing persisted catalogs/tests that used source.tool.
        let components = prefixedToolName.split(separator: ".", maxSplits: 1).map(String.init)
        guard components.count == 2 else { throw MCPSourceRuntimeError.invalidPrefixedToolName(prefixedToolName) }
        guard components[0] == configuration.toolNamePrefix else {
            throw MCPSourceRuntimeError.sourcePrefixMismatch(expected: configuration.toolNamePrefix, actual: components[0])
        }
        return components[1]
    }

    public nonisolated static func exposedToolName(sourceID: String, rawToolName: String) -> String {
        "mcp__\(sanitizeToolNameComponent(sourceID))__\(sanitizeToolNameComponent(rawToolName))"
    }

    public nonisolated static func sanitizeToolNameComponent(_ value: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        let mapped = value.map { allowed.contains($0) ? $0 : "_" }
        let collapsed = String(mapped).replacingOccurrences(of: "__+", with: "_", options: .regularExpression)
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    private func jsonString(_ value: MCPJSONValue) throws -> String {
        String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}
