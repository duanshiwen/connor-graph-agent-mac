import Foundation

public struct GlobalSearchSectionTiming: Sendable, Equatable {
    public var query: String
    public var section: String
    public var startedAt: Date
    public var endedAt: Date
    public var candidateCount: Int
    public var returnedCount: Int
    public var backend: String

    public init(
        query: String,
        section: String,
        startedAt: Date,
        endedAt: Date,
        candidateCount: Int,
        returnedCount: Int,
        backend: String
    ) {
        self.query = query
        self.section = section
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.candidateCount = candidateCount
        self.returnedCount = returnedCount
        self.backend = backend
    }

    public var durationMilliseconds: Double {
        endedAt.timeIntervalSince(startedAt) * 1_000
    }
}

public enum GlobalSearchTimeoutError: Error, Sendable, Equatable, CustomStringConvertible {
    case hardTimeout(milliseconds: Int)

    public var description: String {
        switch self {
        case .hardTimeout(let milliseconds): "globalSearchTimeout(\(milliseconds)ms)"
        }
    }
}
