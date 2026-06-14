import Foundation

public struct AgentToolResultGateConfiguration: Codable, Sendable, Equatable {
    public var maxResultCharacters: Int
    public var perToolCharacterLimits: [String: Int]
    public var includeTruncationMetadata: Bool

    public init(
        maxResultCharacters: Int = 32 * 1024,
        perToolCharacterLimits: [String: Int] = [:],
        includeTruncationMetadata: Bool = true
    ) {
        self.maxResultCharacters = max(0, maxResultCharacters)
        self.perToolCharacterLimits = perToolCharacterLimits
        self.includeTruncationMetadata = includeTruncationMetadata
    }
}

public struct AgentToolResultGate: Sendable, Equatable {
    public var configuration: AgentToolResultGateConfiguration

    public init(configuration: AgentToolResultGateConfiguration = AgentToolResultGateConfiguration()) {
        self.configuration = configuration
    }

    public func gatedContent(for result: AgentToolResult) -> String {
        let base = result.contentJSON ?? result.contentText
        let limit = max(0, configuration.perToolCharacterLimits[result.toolName] ?? configuration.maxResultCharacters)
        guard base.count > limit else { return base }

        let kept = String(base.prefix(limit))
        guard configuration.includeTruncationMetadata else { return kept }
        return kept + "\n...[truncated tool result: tool=\(result.toolName), kept=\(limit) chars, original=\(base.count) chars]"
    }
}
