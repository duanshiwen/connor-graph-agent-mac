import Foundation

public enum SpeechInputModelPolicy: String, Codable, Sendable, Equatable, CaseIterable {
    case automaticRecommended
    case speedFirst
    case balanced
    case highAccuracy
    case appleSpeechOnly
}

public enum SpeechInputTriggerKind: String, Codable, Sendable, Equatable, CaseIterable {
    case mouseHold
    case optionHold
    case spaceHold
}

public enum SpeechInputCommitPhase: String, Codable, Sendable, Equatable {
    case idle
    case recordingPartial
    case finalizing
    case committed
    case failed
}

public struct SpeechInputRuntimeSnapshot: Codable, Sendable, Equatable {
    public var selectedModelID: String?
    public var localRuntimeAvailable: Bool
    public var fallbackReason: String?
    public var policy: SpeechInputModelPolicy

    public init(
        selectedModelID: String? = nil,
        localRuntimeAvailable: Bool = false,
        fallbackReason: String? = nil,
        policy: SpeechInputModelPolicy = .automaticRecommended
    ) {
        self.selectedModelID = selectedModelID
        self.localRuntimeAvailable = localRuntimeAvailable
        self.fallbackReason = fallbackReason
        self.policy = policy
    }
}
