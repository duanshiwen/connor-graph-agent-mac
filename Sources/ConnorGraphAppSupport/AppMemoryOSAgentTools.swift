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
            "l1RetryScheduledCount": snapshot.l1RetryScheduledCount,
            "l1ExpiredLeaseCount": snapshot.l1ExpiredLeaseCount,
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

public struct MemoryOSProjectStructuredArtifactTool: AgentTool {
    public let name = "memory_os_project_structured_artifact"
    public let description = "Validate and project a GraphStructuredExtractionOutput JSON artifact into Connor Memory OS L2/L3/L4. The artifact is persisted and audited before projection; rejected artifacts do not write projections."
    public let permission: AgentPermissionCapability = .proposeGraphWrite
    public let inputSchema = AgentToolInputSchema.object(properties: [
        "rawContent": .string(description: "Raw GraphStructuredExtractionOutput JSON to validate and project."),
        "modelID": .string(description: "Model identifier that produced the artifact."),
        "processingRunID": .string(description: "Optional processing run id for audit correlation.")
    ], required: ["rawContent", "modelID"])

    private let facade: AppMemoryOSFacade

    public init(facade: AppMemoryOSFacade) { self.facade = facade }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let rawContent = arguments.string("rawContent"), !rawContent.isEmpty else {
            throw AgentToolError.invalidArguments("rawContent is required")
        }
        guard let modelID = arguments.string("modelID"), !modelID.isEmpty else {
            throw AgentToolError.invalidArguments("modelID is required")
        }
        let runID = arguments.string("processingRunID") ?? context.runID
        let summary = try facade.projectAndRecordLLMArtifact(rawContent: rawContent, modelID: modelID, processingRunID: runID)
        let payload: [String: Any] = [
            "artifactID": summary.artifactID,
            "accepted": summary.accepted,
            "nodeCount": summary.nodeCount,
            "statementCount": summary.statementCount,
            "entityCount": summary.entityCount,
            "entityStatementCount": summary.entityStatementCount,
            "beliefCount": summary.beliefCount,
            "issueCount": summary.issues.count
        ]
        let json = try Self.renderJSON(payload)
        return AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: summary.accepted ? "Memory OS projected artifact \(summary.artifactID): \(summary.statementCount) statements, \(summary.entityCount) entities, \(summary.beliefCount) beliefs." : "Memory OS rejected artifact \(summary.artifactID): \(summary.issues.count) validation issue(s).",
            contentJSON: json,
            citations: [summary.artifactID]
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
        register(MemoryOSProjectStructuredArtifactTool(facade: facade))
    }
}
