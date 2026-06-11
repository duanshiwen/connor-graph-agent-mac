import Foundation
import ConnorGraphCore

public struct AgentTextDeltaBufferConfiguration: Codable, Sendable, Equatable {
    public var characterThreshold: Int

    public init(characterThreshold: Int = 80) {
        self.characterThreshold = max(1, characterThreshold)
    }
}

public struct AgentTextDeltaBuffer: Sendable, Equatable {
    public var configuration: AgentTextDeltaBufferConfiguration
    private var bufferedText: String

    public init(configuration: AgentTextDeltaBufferConfiguration = AgentTextDeltaBufferConfiguration()) {
        self.configuration = configuration
        self.bufferedText = ""
    }

    public mutating func append(_ delta: AgentTextDeltaEvent) -> AgentTextDeltaEvent? {
        bufferedText += delta.text
        guard bufferedText.count >= configuration.characterThreshold else { return nil }
        return flush(runID: delta.runID, sessionID: delta.sessionID)
    }

    public mutating func flush(runID: String, sessionID: String) -> AgentTextDeltaEvent? {
        guard !bufferedText.isEmpty else { return nil }
        let text = bufferedText
        bufferedText = ""
        return AgentTextDeltaEvent(runID: runID, sessionID: sessionID, text: text)
    }
}
