import Foundation

public enum NativeSearchSourceKind: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case mail
    case calendar
    case rss
}

public enum NativeSearchTimeKind: String, Codable, Sendable, Equatable, Hashable {
    case sentAt
    case receivedAt
    case publishedAt
    case fetchedAt
    case eventStartAt
    case updatedAt
    case createdAt
    case indexedAt
    case unknown
}

public enum NativeSearchTemporalFilterMode: String, Codable, Sendable, Equatable, Hashable {
    case pointWithinRange
    case intervalOverlapsRange
    case startsWithinRange
    case endsWithinRange
    case updatedWithinRange
    case indexedWithinRange
}

public enum NativeSearchTemporalSort: String, Codable, Sendable, Equatable, Hashable {
    case relevanceThenTimeDesc
    case relevanceThenTimeAsc
    case timeDescThenRelevance
    case timeAscThenRelevance
}

public enum NativeSearchRankingProfile: String, Codable, Sendable, Equatable, Hashable {
    case general
    case recentFirst
    case calendarUpcoming
    case calendarHistorical
    case evidenceDiscovery
    case exactLookup
}

public enum NativeSearchTimePreset: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case today
    case yesterday
    case tomorrow
    case thisWeek
    case lastWeek
    case nextWeek
    case thisMonth
    case lastMonth
    case nextMonth
    case last7Days
    case last14Days
    case last30Days
    case last90Days
    case next7Days
    case next14Days
    case next30Days
    case yearToDate
}

public struct NativeSearchTemporalMetadata: Codable, Sendable, Equatable, Hashable {
    public var primaryTime: Date?
    public var primaryTimeKind: NativeSearchTimeKind
    public var createdAt: Date?
    public var updatedAt: Date?
    public var receivedAt: Date?
    public var sentAt: Date?
    public var publishedAt: Date?
    public var fetchedAt: Date?
    public var eventStartAt: Date?
    public var eventEndAt: Date?
    public var indexedAt: Date?
    public var timezoneIdentifier: String?
    public var isAllDay: Bool

    public init(
        primaryTime: Date? = nil,
        primaryTimeKind: NativeSearchTimeKind = .unknown,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        receivedAt: Date? = nil,
        sentAt: Date? = nil,
        publishedAt: Date? = nil,
        fetchedAt: Date? = nil,
        eventStartAt: Date? = nil,
        eventEndAt: Date? = nil,
        indexedAt: Date? = nil,
        timezoneIdentifier: String? = nil,
        isAllDay: Bool = false
    ) {
        self.primaryTime = primaryTime
        self.primaryTimeKind = primaryTimeKind
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.receivedAt = receivedAt
        self.sentAt = sentAt
        self.publishedAt = publishedAt
        self.fetchedAt = fetchedAt
        self.eventStartAt = eventStartAt
        self.eventEndAt = eventEndAt
        self.indexedAt = indexedAt
        self.timezoneIdentifier = timezoneIdentifier
        self.isAllDay = isAllDay
    }

    public func time(for kind: NativeSearchTimeKind) -> Date? {
        switch kind {
        case .sentAt: sentAt
        case .receivedAt: receivedAt
        case .publishedAt: publishedAt
        case .fetchedAt: fetchedAt
        case .eventStartAt: eventStartAt
        case .updatedAt: updatedAt
        case .createdAt: createdAt
        case .indexedAt: indexedAt
        case .unknown: primaryTime
        }
    }
}

public struct NativeSearchTemporalFilter: Codable, Sendable, Equatable, Hashable {
    public var start: Date?
    public var end: Date?
    public var mode: NativeSearchTemporalFilterMode
    public var timeFieldPreference: [NativeSearchTimeKind]
    public var timezoneIdentifier: String

    public init(
        start: Date? = nil,
        end: Date? = nil,
        mode: NativeSearchTemporalFilterMode = .pointWithinRange,
        timeFieldPreference: [NativeSearchTimeKind] = [],
        timezoneIdentifier: String = TimeZone.current.identifier
    ) {
        self.start = start
        self.end = end
        self.mode = mode
        self.timeFieldPreference = timeFieldPreference
        self.timezoneIdentifier = timezoneIdentifier
    }

    public func contains(_ temporal: NativeSearchTemporalMetadata, sourceKind: NativeSearchSourceKind) -> Bool {
        switch mode {
        case .intervalOverlapsRange:
            let intervalStart = temporal.eventStartAt ?? temporal.primaryTime
            let intervalEnd = temporal.eventEndAt ?? intervalStart
            return Self.intervalOverlaps(start: intervalStart, end: intervalEnd, filterStart: start, filterEnd: end)
        case .startsWithinRange:
            return Self.point(temporal.eventStartAt ?? temporal.primaryTime, isWithinStart: start, end: end)
        case .endsWithinRange:
            return Self.point(temporal.eventEndAt ?? temporal.primaryTime, isWithinStart: start, end: end)
        case .updatedWithinRange:
            return Self.point(temporal.updatedAt ?? temporal.primaryTime, isWithinStart: start, end: end)
        case .indexedWithinRange:
            return Self.point(temporal.indexedAt ?? temporal.primaryTime, isWithinStart: start, end: end)
        case .pointWithinRange:
            let preferred = timeFieldPreference.compactMap { temporal.time(for: $0) }.first
            let fallback: Date?
            switch sourceKind {
            case .mail:
                fallback = temporal.sentAt ?? temporal.receivedAt ?? temporal.primaryTime
            case .rss:
                fallback = temporal.publishedAt ?? temporal.fetchedAt ?? temporal.primaryTime
            case .calendar:
                fallback = temporal.eventStartAt ?? temporal.primaryTime
            }
            return Self.point(preferred ?? fallback, isWithinStart: start, end: end)
        }
    }

    private static func point(_ value: Date?, isWithinStart start: Date?, end: Date?) -> Bool {
        guard let value else { return false }
        if let start, value < start { return false }
        if let end, value >= end { return false }
        return true
    }

    private static func intervalOverlaps(start intervalStart: Date?, end intervalEnd: Date?, filterStart: Date?, filterEnd: Date?) -> Bool {
        guard let intervalStart else { return false }
        let intervalEnd = intervalEnd ?? intervalStart
        if let filterEnd, intervalStart >= filterEnd { return false }
        if let filterStart, intervalEnd <= filterStart { return false }
        return true
    }
}

public struct NativeSearchDocument: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var sourceKind: NativeSearchSourceKind
    public var sourceInstanceID: String?
    public var externalID: String
    public var title: String
    public var summary: String
    public var body: String?
    public var participants: [String]
    public var location: String?
    public var url: URL?
    public var temporal: NativeSearchTemporalMetadata
    public var visibility: String
    public var state: [String: String]
    public var metadata: [String: String]
    public var contentHash: String
    public var schemaVersion: Int

    public init(
        id: String,
        sourceKind: NativeSearchSourceKind,
        sourceInstanceID: String? = nil,
        externalID: String,
        title: String,
        summary: String,
        body: String? = nil,
        participants: [String] = [],
        location: String? = nil,
        url: URL? = nil,
        temporal: NativeSearchTemporalMetadata = NativeSearchTemporalMetadata(),
        visibility: String = "visible",
        state: [String: String] = [:],
        metadata: [String: String] = [:],
        contentHash: String,
        schemaVersion: Int = 1
    ) {
        self.id = id
        self.sourceKind = sourceKind
        self.sourceInstanceID = sourceInstanceID
        self.externalID = externalID
        self.title = title
        self.summary = summary
        self.body = body
        self.participants = participants
        self.location = location
        self.url = url
        self.temporal = temporal
        self.visibility = visibility
        self.state = state
        self.metadata = metadata
        self.contentHash = contentHash
        self.schemaVersion = schemaVersion
    }
}

public enum NativeSearchLimitPolicy {
    public static let defaultSearchLimit = 20
    public static let maxSearchLimit = 100
    public static let defaultListLimit = 50
    public static let maxListLimit = 200

    public static func clampSearchLimit(_ value: Int, default defaultValue: Int = defaultSearchLimit) -> Int {
        clamp(value, default: defaultValue, max: maxSearchLimit)
    }

    public static func clampListLimit(_ value: Int, default defaultValue: Int = defaultListLimit) -> Int {
        clamp(value, default: defaultValue, max: maxListLimit)
    }

    private static func clamp(_ value: Int, default defaultValue: Int, max upperBound: Int) -> Int {
        guard value > 0 else { return defaultValue }
        return Swift.min(value, upperBound)
    }
}

public struct NativeSearchQuery: Codable, Sendable, Equatable {
    public var text: String
    public var sourceKinds: Set<NativeSearchSourceKind>?
    public var sourceInstanceIDs: Set<String>?
    public var temporalFilter: NativeSearchTemporalFilter?
    public var temporalSort: NativeSearchTemporalSort
    public var limit: Int
    public var includeHidden: Bool
    public var includeArchived: Bool
    public var includeBodySnippets: Bool
    public var rankingProfile: NativeSearchRankingProfile
    public var fieldConstraints: [NativeSearchFieldConstraintKey: [String]]

    public init(
        text: String,
        sourceKinds: Set<NativeSearchSourceKind>? = nil,
        sourceInstanceIDs: Set<String>? = nil,
        temporalFilter: NativeSearchTemporalFilter? = nil,
        temporalSort: NativeSearchTemporalSort = .relevanceThenTimeDesc,
        limit: Int = 20,
        includeHidden: Bool = false,
        includeArchived: Bool = false,
        includeBodySnippets: Bool = false,
        rankingProfile: NativeSearchRankingProfile = .general,
        fieldConstraints: [NativeSearchFieldConstraintKey: [String]] = [:]
    ) {
        self.text = text
        self.sourceKinds = sourceKinds
        self.sourceInstanceIDs = sourceInstanceIDs
        self.temporalFilter = temporalFilter
        self.temporalSort = temporalSort
        self.limit = NativeSearchLimitPolicy.clampSearchLimit(limit)
        self.includeHidden = includeHidden
        self.includeArchived = includeArchived
        self.includeBodySnippets = includeBodySnippets
        self.rankingProfile = rankingProfile
        self.fieldConstraints = fieldConstraints
    }
}

public struct NativeSearchResultDiagnostics: Codable, Sendable, Equatable, Hashable {
    public var matchedFields: [String]
    public var indexedAt: Date?
    public var queryTokens: [String]
    public var softStopWords: [String]
    public var matchedTerms: [String]
    public var matchedFieldScores: [String: Double]
    public var fieldConstraints: [String: [String]]
    public var rankReason: String
    public var timeReason: String

    public init(
        matchedFields: [String] = [],
        indexedAt: Date? = nil,
        queryTokens: [String] = [],
        softStopWords: [String] = [],
        matchedTerms: [String] = [],
        matchedFieldScores: [String: Double] = [:],
        fieldConstraints: [String: [String]] = [:],
        rankReason: String = "",
        timeReason: String = ""
    ) {
        self.matchedFields = matchedFields
        self.indexedAt = indexedAt
        self.queryTokens = queryTokens
        self.softStopWords = softStopWords
        self.matchedTerms = matchedTerms
        self.matchedFieldScores = matchedFieldScores
        self.fieldConstraints = fieldConstraints
        self.rankReason = rankReason
        self.timeReason = timeReason
    }
}

public struct NativeSearchResult: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var sourceKind: NativeSearchSourceKind
    public var externalID: String
    public var sourceInstanceID: String?
    public var title: String
    public var snippet: String
    public var highlights: [String]
    public var score: Double
    public var lexicalScore: Double
    public var freshnessScore: Double
    public var fieldScore: Double
    public var temporal: NativeSearchTemporalMetadata
    public var resultTimeLabel: String
    public var resultTimeISO8601: String?
    public var resultTimeDisplay: String?
    public var diagnostics: NativeSearchResultDiagnostics?

    public init(
        id: String,
        sourceKind: NativeSearchSourceKind,
        externalID: String,
        sourceInstanceID: String? = nil,
        title: String,
        snippet: String,
        highlights: [String] = [],
        score: Double,
        lexicalScore: Double,
        freshnessScore: Double,
        fieldScore: Double,
        temporal: NativeSearchTemporalMetadata,
        resultTimeLabel: String,
        diagnostics: NativeSearchResultDiagnostics? = nil
    ) {
        self.id = id
        self.sourceKind = sourceKind
        self.externalID = externalID
        self.sourceInstanceID = sourceInstanceID
        self.title = title
        self.snippet = snippet
        self.highlights = highlights
        self.score = score
        self.lexicalScore = lexicalScore
        self.freshnessScore = freshnessScore
        self.fieldScore = fieldScore
        self.temporal = temporal
        self.resultTimeLabel = resultTimeLabel
        self.resultTimeISO8601 = temporal.primaryTime.map { ISO8601DateFormatter().string(from: $0) }
        self.resultTimeDisplay = temporal.primaryTime.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .short) }
        self.diagnostics = diagnostics
    }
}

public enum NativeSearchTimePresetResolver {
    public static func resolve(_ preset: NativeSearchTimePreset, now: Date = Date(), timezone: TimeZone = .current, calendar inputCalendar: Calendar = Calendar(identifier: .gregorian)) -> NativeSearchTemporalFilter {
        var calendar = inputCalendar
        calendar.timeZone = timezone
        let dayStart = calendar.startOfDay(for: now)
        func add(_ component: Calendar.Component, value: Int, to date: Date) -> Date {
            calendar.date(byAdding: component, value: value, to: date) ?? date
        }
        func weekInterval(offset: Int) -> (Date, Date) {
            let base = add(.weekOfYear, value: offset, to: now)
            let interval = calendar.dateInterval(of: .weekOfYear, for: base)
            return (interval?.start ?? dayStart, interval?.end ?? add(.day, value: 7, to: dayStart))
        }
        func monthInterval(offset: Int) -> (Date, Date) {
            let base = add(.month, value: offset, to: now)
            let interval = calendar.dateInterval(of: .month, for: base)
            return (interval?.start ?? dayStart, interval?.end ?? add(.month, value: 1, to: dayStart))
        }

        let range: (Date, Date)
        switch preset {
        case .today:
            range = (dayStart, add(.day, value: 1, to: dayStart))
        case .yesterday:
            range = (add(.day, value: -1, to: dayStart), dayStart)
        case .tomorrow:
            range = (add(.day, value: 1, to: dayStart), add(.day, value: 2, to: dayStart))
        case .thisWeek:
            range = weekInterval(offset: 0)
        case .lastWeek:
            range = weekInterval(offset: -1)
        case .nextWeek:
            range = weekInterval(offset: 1)
        case .thisMonth:
            range = monthInterval(offset: 0)
        case .lastMonth:
            range = monthInterval(offset: -1)
        case .nextMonth:
            range = monthInterval(offset: 1)
        case .last7Days:
            range = (add(.day, value: -7, to: now), now)
        case .last14Days:
            range = (add(.day, value: -14, to: now), now)
        case .last30Days:
            range = (add(.day, value: -30, to: now), now)
        case .last90Days:
            range = (add(.day, value: -90, to: now), now)
        case .next7Days:
            range = (now, add(.day, value: 7, to: now))
        case .next14Days:
            range = (now, add(.day, value: 14, to: now))
        case .next30Days:
            range = (now, add(.day, value: 30, to: now))
        case .yearToDate:
            let start = calendar.date(from: calendar.dateComponents([.year], from: now)) ?? dayStart
            range = (start, now)
        }
        return NativeSearchTemporalFilter(start: range.0, end: range.1, timezoneIdentifier: timezone.identifier)
    }
}
