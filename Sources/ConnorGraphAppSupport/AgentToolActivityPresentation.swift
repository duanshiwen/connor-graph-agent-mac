import Foundation

public enum AgentToolActivityPhase: String, Codable, Sendable, Equatable {
    case requested
    case approved
    case running
    case finished
    case failed
}

public enum AgentToolSemanticKind: String, Codable, Sendable, Equatable {
    case readFile
    case writeFile
    case editFile
    case listDirectory
    case findFiles
    case searchFiles
    case shellCommand
    case swiftBuild
    case swiftTest
    case swiftRun
    case xcodeBuild
    case git
    case packageManager
    case python
    case node
    case browser
    case calendar
    case mcp
    case unknown
}

public struct AgentToolActivityPresentation: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var callID: String
    public var phase: AgentToolActivityPhase
    public var rawToolName: String
    public var semanticKind: AgentToolSemanticKind
    public var title: String
    public var subtitle: String?
    public var target: String?
    public var detail: String?
    public var icon: String
    public var severity: AgentEventPresentationSeverity
    public var argumentsJSON: String?
    public var resultJSON: String?

    public init(
        id: String = UUID().uuidString,
        callID: String,
        phase: AgentToolActivityPhase,
        rawToolName: String,
        semanticKind: AgentToolSemanticKind,
        title: String,
        subtitle: String? = nil,
        target: String? = nil,
        detail: String? = nil,
        icon: String,
        severity: AgentEventPresentationSeverity,
        argumentsJSON: String? = nil,
        resultJSON: String? = nil
    ) {
        self.id = id
        self.callID = callID
        self.phase = phase
        self.rawToolName = rawToolName
        self.semanticKind = semanticKind
        self.title = title
        self.subtitle = subtitle
        self.target = target
        self.detail = detail
        self.icon = icon
        self.severity = severity
        self.argumentsJSON = argumentsJSON
        self.resultJSON = resultJSON
    }
}
