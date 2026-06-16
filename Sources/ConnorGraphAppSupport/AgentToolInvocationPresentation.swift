import Foundation

public struct AgentToolInvocationPresentation: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var callID: String
    public var runID: String?
    public var sessionID: String?
    public var toolName: String
    public var semanticKind: AgentToolSemanticKind
    public var phase: AgentToolActivityPhase
    public var severity: AgentEventPresentationSeverity

    public var title: String
    public var subtitle: String?
    public var target: String?
    public var icon: String

    public var argumentsJSON: String?
    public var resultJSON: String?
    public var outputText: String?
    public var errorText: String?

    public var requestedEventID: String?
    public var approvedEventID: String?
    public var startedEventID: String?
    public var finishedEventID: String?
    public var failedEventID: String?

    public var rawEventIDs: [String]
    public var isOutputTruncated: Bool
    public var outputArtifactPath: String?
    public var createdAt: Date?
    public var completedAt: Date?

    public init(
        id: String,
        callID: String,
        runID: String?,
        sessionID: String?,
        toolName: String,
        semanticKind: AgentToolSemanticKind,
        phase: AgentToolActivityPhase,
        severity: AgentEventPresentationSeverity,
        title: String,
        subtitle: String? = nil,
        target: String? = nil,
        icon: String,
        argumentsJSON: String? = nil,
        resultJSON: String? = nil,
        outputText: String? = nil,
        errorText: String? = nil,
        requestedEventID: String? = nil,
        approvedEventID: String? = nil,
        startedEventID: String? = nil,
        finishedEventID: String? = nil,
        failedEventID: String? = nil,
        rawEventIDs: [String],
        isOutputTruncated: Bool = false,
        outputArtifactPath: String? = nil,
        createdAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.callID = callID
        self.runID = runID
        self.sessionID = sessionID
        self.toolName = toolName
        self.semanticKind = semanticKind
        self.phase = phase
        self.severity = severity
        self.title = title
        self.subtitle = subtitle
        self.target = target
        self.icon = icon
        self.argumentsJSON = argumentsJSON
        self.resultJSON = resultJSON
        self.outputText = outputText
        self.errorText = errorText
        self.requestedEventID = requestedEventID
        self.approvedEventID = approvedEventID
        self.startedEventID = startedEventID
        self.finishedEventID = finishedEventID
        self.failedEventID = failedEventID
        self.rawEventIDs = rawEventIDs
        self.isOutputTruncated = isOutputTruncated
        self.outputArtifactPath = outputArtifactPath
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}
