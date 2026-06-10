import Foundation

public struct GraphExtractionTracePayload: Codable, Sendable, Equatable, Identifiable {
    public var id: String { traceID }
    public var traceID: String
    public var promptText: String?
    public var rawResponseJSON: String?
    public var normalizedJSON: String?
    public var decoderErrorKind: String?
    public var decoderErrorMessage: String?
    public var createdAt: Date
    public var metadata: [String: String]

    public init(
        traceID: String,
        promptText: String? = nil,
        rawResponseJSON: String? = nil,
        normalizedJSON: String? = nil,
        decoderErrorKind: String? = nil,
        decoderErrorMessage: String? = nil,
        createdAt: Date = Date(),
        metadata: [String: String] = [:]
    ) {
        self.traceID = traceID
        self.promptText = promptText
        self.rawResponseJSON = rawResponseJSON
        self.normalizedJSON = normalizedJSON
        self.decoderErrorKind = decoderErrorKind
        self.decoderErrorMessage = decoderErrorMessage
        self.createdAt = createdAt
        self.metadata = metadata
    }
}
