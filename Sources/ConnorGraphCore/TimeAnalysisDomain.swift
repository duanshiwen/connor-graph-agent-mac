import Foundation

public struct TimeAnalysisRange: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var start: Date
    public var end: Date

    public init(id: String, start: Date, end: Date) {
        self.id = id
        self.start = start
        self.end = end
    }

    public var dateInterval: DateInterval? {
        guard end >= start else { return nil }
        return DateInterval(start: start, end: end)
    }
}

public struct TimeStartDifference: Codable, Sendable, Equatable, Hashable {
    public var leftID: String
    public var rightID: String
    public var signedSeconds: TimeInterval

    public init(leftID: String, rightID: String, signedSeconds: TimeInterval) {
        self.leftID = leftID
        self.rightID = rightID
        self.signedSeconds = signedSeconds
    }
}

public struct TimeRangeOverlap: Codable, Sendable, Equatable, Hashable {
    public var leftID: String
    public var rightID: String
    public var overlaps: Bool
    public var overlapStart: Date?
    public var overlapEnd: Date?
    public var overlapSeconds: TimeInterval

    public init(leftID: String, rightID: String, overlaps: Bool, overlapStart: Date? = nil, overlapEnd: Date? = nil, overlapSeconds: TimeInterval = 0) {
        self.leftID = leftID
        self.rightID = rightID
        self.overlaps = overlaps
        self.overlapStart = overlapStart
        self.overlapEnd = overlapEnd
        self.overlapSeconds = overlapSeconds
    }
}

public struct TimeAnalysisResult: Codable, Sendable, Equatable, Hashable {
    public var ranges: [TimeAnalysisRange]
    public var startDifferences: [TimeStartDifference]
    public var overlaps: [TimeRangeOverlap]

    public init(ranges: [TimeAnalysisRange], startDifferences: [TimeStartDifference], overlaps: [TimeRangeOverlap]) {
        self.ranges = ranges
        self.startDifferences = startDifferences
        self.overlaps = overlaps
    }
}

public struct TimeRangeAnalyzer: Sendable {
    public init() {}

    public func analyze(ranges: [TimeAnalysisRange]) -> TimeAnalysisResult {
        var differences: [TimeStartDifference] = []
        var overlaps: [TimeRangeOverlap] = []

        for left in ranges {
            for right in ranges where left.id != right.id {
                differences.append(TimeStartDifference(
                    leftID: left.id,
                    rightID: right.id,
                    signedSeconds: right.start.timeIntervalSince(left.start)
                ))
            }
        }

        for leftIndex in ranges.indices {
            for rightIndex in ranges.indices where rightIndex > leftIndex {
                let left = ranges[leftIndex]
                let right = ranges[rightIndex]
                guard let leftInterval = left.dateInterval, let rightInterval = right.dateInterval,
                      let intersection = leftInterval.intersection(with: rightInterval),
                      intersection.duration > 0
                else {
                    overlaps.append(TimeRangeOverlap(leftID: left.id, rightID: right.id, overlaps: false))
                    continue
                }
                overlaps.append(TimeRangeOverlap(
                    leftID: left.id,
                    rightID: right.id,
                    overlaps: true,
                    overlapStart: intersection.start,
                    overlapEnd: intersection.end,
                    overlapSeconds: intersection.duration
                ))
            }
        }

        return TimeAnalysisResult(ranges: ranges, startDifferences: differences, overlaps: overlaps)
    }
}
