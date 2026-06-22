import Foundation
import ConnorGraphAgent
import ConnorGraphCore

public struct MemoryOSDashboardSummaryTool: AgentTool {
    public let name = "memory_os_dashboard_summary"
    public let description = "Read the production Connor Memory OS operational dashboard summary. This is the supported memory read surface for L0-L4 health and counts."
    public let permission: AgentPermissionCapability = .readGraph
    public let inputSchema = AgentToolInputSchema.object(properties: [:], required: [])

    private let facade: AppMemoryOSFacade

    public init(facade: AppMemoryOSFacade) {
        self.facade = facade
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let summary = try facade.operationalSummary()
        let snapshot = summary.dashboardSnapshot
        let payload: [String: Any] = [
            "healthStatus": snapshot.healthStatus.rawValue,
            "l0ProvenanceObjectCount": snapshot.l0ProvenanceObjectCount,
            "l1PendingCaptureCount": snapshot.l1PendingCaptureCount,
            "l1PendingQueueCount": snapshot.l1PendingQueueCount,
            "l1DeadLetterCount": snapshot.l1DeadLetterCount,
            "l2StatementCount": snapshot.l2StatementCount,
            "l2ConflictCount": snapshot.l2ConflictCount,
            "l3BeliefCount": snapshot.l3BeliefCount,
            "l4EntityCount": snapshot.l4EntityCount,
            "expiredLeaseCount": summary.expiredLeaseCount
        ]
        let json = try Self.renderJSON(payload)
        return AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: "Memory OS health: \(snapshot.healthStatus.rawValue). L0 objects: \(snapshot.l0ProvenanceObjectCount), L1 pending: \(snapshot.l1PendingCaptureCount), L2 statements: \(snapshot.l2StatementCount), L3 beliefs: \(snapshot.l3BeliefCount), L4 entities: \(snapshot.l4EntityCount).",
            contentJSON: json,
            citations: []
        )
    }

    private static func renderJSON(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

public struct MemoryOSIngestObservationTool: AgentTool {
    public let name = "memory_os_ingest_observation"
    public let description = "Archive an evidence-backed observation into Connor Memory OS L0 provenance and L1 capture. This replaces legacy graph staging/candidate-write tools."
    public let permission: AgentPermissionCapability = .proposeGraphWrite
    public let inputSchema = AgentToolInputSchema.object(properties: [
        "title": .string(description: "Short human-readable observation title."),
        "content": .string(description: "Raw observed content to archive as provenance."),
        "sourceID": .string(description: "Optional external source/message id."),
        "sessionID": .string(description: "Optional session id. Defaults to current session."),
        "role": .string(description: "Optional source role such as user, assistant, tool, external. Defaults to tool.")
    ], required: ["title", "content"])

    private let facade: AppMemoryOSFacade

    public init(facade: AppMemoryOSFacade) {
        self.facade = facade
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let title = arguments.string("title"), !title.isEmpty else {
            throw AgentToolError.invalidArguments("title is required")
        }
        guard let content = arguments.string("content"), !content.isEmpty else {
            throw AgentToolError.invalidArguments("content is required")
        }
        let sourceID = arguments.string("sourceID") ?? context.toolCallID
        let sessionID = arguments.string("sessionID") ?? context.sessionID
        let role = arguments.string("role") ?? "tool"
        let result = try facade.ingestChatMessage(
            messageID: sourceID,
            sessionID: sessionID,
            role: role,
            content: content,
            occurredAt: Date(),
            metadata: ["title": title, "toolCallID": context.toolCallID, "runID": context.runID]
        )
        let provenanceObjectID = result.provenanceObject?.id ?? ""
        let spanID = result.span?.id ?? ""
        let captureEventID = result.captureEvent?.id ?? ""
        let decisionAction = String(describing: result.decision.action)
        let payload: [String: Any] = [
            "decision": decisionAction,
            "decisionReason": result.decision.reason,
            "provenanceObjectID": provenanceObjectID,
            "spanID": spanID,
            "captureEventID": captureEventID
        ]
        let json = try Self.renderJSON(payload)
        let citations = [provenanceObjectID, spanID, captureEventID].filter { !$0.isEmpty }
        return AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: "Memory OS ingestion decision: \(decisionAction). Provenance object: \(provenanceObjectID.isEmpty ? "none" : provenanceObjectID).",
            contentJSON: json,
            citations: citations
        )
    }

    private static func renderJSON(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

public extension AgentToolRegistry {
    mutating func registerMemoryOSTools(facade: AppMemoryOSFacade) {
        register(MemoryOSDashboardSummaryTool(facade: facade))
        register(MemoryOSIngestObservationTool(facade: facade))
    }
}
