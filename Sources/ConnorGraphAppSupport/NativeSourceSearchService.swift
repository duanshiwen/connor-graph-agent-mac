import Foundation
import ConnorGraphCore

public struct NativeSourceSearchHealthSnapshot: Codable, Sendable, Equatable {
    public var backendStatus: String
    public var schemaVersion: Int
    public var documentCountBySource: [NativeSearchSourceKind: Int]
    public var lastIndexedAtBySource: [NativeSearchSourceKind: Date]
    public var pendingUpdateCount: Int
    public var staleSourceKinds: [NativeSearchSourceKind]
    public var lastError: String?

    public init(
        backendStatus: String = "ready",
        schemaVersion: Int = NativeSourceSearchService.currentSchemaVersion,
        documentCountBySource: [NativeSearchSourceKind: Int] = [:],
        lastIndexedAtBySource: [NativeSearchSourceKind: Date] = [:],
        pendingUpdateCount: Int = 0,
        staleSourceKinds: [NativeSearchSourceKind] = [],
        lastError: String? = nil
    ) {
        self.backendStatus = backendStatus
        self.schemaVersion = schemaVersion
        self.documentCountBySource = documentCountBySource
        self.lastIndexedAtBySource = lastIndexedAtBySource
        self.pendingUpdateCount = pendingUpdateCount
        self.staleSourceKinds = staleSourceKinds
        self.lastError = lastError
    }
}

struct NativeSearchCorpusStatistics {
    var documentCount: Int
    var documentFrequencyByToken: [String: Int]
    var averageFieldLength: [String: Double]

    func idf(for token: String) -> Double {
        guard documentCount > 0 else { return 0 }
        let df = Double(documentFrequencyByToken[token] ?? 0)
        return log((Double(documentCount) - df + 0.5) / (df + 0.5) + 1.0)
    }
}

public actor NativeSourceSearchService {
    public static let currentSchemaVersion = 1

    private struct PersistedIndex: Codable {
        var documents: [NativeSearchDocument]
        var lastError: String?
    }

    private var documents: [String: NativeSearchDocument]
    private let indexURL: URL?
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var lastError: String?

    public init(indexURL: URL? = nil, fileManager: FileManager = .default) {
        self.documents = [:]
        self.indexURL = indexURL
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        if let indexURL,
           let data = try? Data(contentsOf: indexURL),
           let persisted = try? decoder.decode(PersistedIndex.self, from: data) {
            self.documents = Dictionary(uniqueKeysWithValues: persisted.documents.map { ($0.id, $0) })
            self.lastError = persisted.lastError
        }
    }

    public init(storagePaths: AppStoragePaths, fileManager: FileManager = .default) {
        let url = storagePaths.applicationSupportDirectory
            .appendingPathComponent("search", isDirectory: true)
            .appendingPathComponent("native-source-index.json")
        self.documents = [:]
        self.indexURL = url
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: url),
           let persisted = try? decoder.decode(PersistedIndex.self, from: data) {
            self.documents = Dictionary(uniqueKeysWithValues: persisted.documents.map { ($0.id, $0) })
            self.lastError = persisted.lastError
        } else {
            self.lastError = nil
        }
    }

    public func upsert(_ newDocuments: [NativeSearchDocument]) async throws {
        guard !newDocuments.isEmpty else { return }
        var didChange = false
        for document in newDocuments {
            var indexed = document
            var temporal = indexed.temporal
            if temporal.indexedAt == nil { temporal.indexedAt = documents[document.id]?.temporal.indexedAt ?? Date() }
            if temporal.primaryTime == nil {
                temporal.primaryTime = Self.defaultPrimaryTime(for: indexed.sourceKind, temporal: temporal)
                temporal.primaryTimeKind = Self.defaultPrimaryTimeKind(for: indexed.sourceKind, temporal: temporal)
            }
            indexed.temporal = temporal
            if documents[indexed.id] == indexed { continue }
            documents[indexed.id] = indexed
            didChange = true
        }
        if didChange { try persist() }
    }

    public func delete(documentIDs: [String]) async throws {
        var didChange = false
        for id in documentIDs {
            if documents.removeValue(forKey: id) != nil { didChange = true }
        }
        if didChange { try persist() }
    }

    public func deleteBySource(kind: NativeSearchSourceKind, sourceInstanceID: String? = nil) async throws {
        let originalCount = documents.count
        documents = documents.filter { _, document in
            guard document.sourceKind == kind else { return true }
            if let sourceInstanceID { return document.sourceInstanceID != sourceInstanceID }
            return false
        }
        if documents.count != originalCount { try persist() }
    }

    public func rebuildSource(kind: NativeSearchSourceKind, sourceInstanceID: String? = nil, documents newDocuments: [NativeSearchDocument]) async throws {
        var nextDocuments = documents.filter { _, document in
            guard document.sourceKind == kind else { return true }
            if let sourceInstanceID { return document.sourceInstanceID != sourceInstanceID }
            return false
        }
        for document in newDocuments {
            var indexed = document
            var temporal = indexed.temporal
            if temporal.indexedAt == nil { temporal.indexedAt = documents[document.id]?.temporal.indexedAt ?? Date() }
            if temporal.primaryTime == nil {
                temporal.primaryTime = Self.defaultPrimaryTime(for: indexed.sourceKind, temporal: temporal)
                temporal.primaryTimeKind = Self.defaultPrimaryTimeKind(for: indexed.sourceKind, temporal: temporal)
            }
            indexed.temporal = temporal
            nextDocuments[indexed.id] = indexed
        }
        guard nextDocuments != documents else { return }
        documents = nextDocuments
        try persist()
    }

    public func search(_ query: NativeSearchQuery) async throws -> [NativeSearchResult] {
        let normalizedQuery = NativeSearchQueryNormalizer.normalize(query.text)
        let tokens = normalizedQuery.scoringTokens.map(\.value)
        let allQueryTokens = normalizedQuery.tokens.map(\.value)
        let softStopWords = normalizedQuery.softStopTokenValues
        let now = Date()
        let filteredDocuments = documents.values.filter { document in
            if let kinds = query.sourceKinds, !kinds.contains(document.sourceKind) { return false }
            if let ids = query.sourceInstanceIDs, !(document.sourceInstanceID.map { ids.contains($0) } ?? false) { return false }
            if !query.includeHidden, document.state["isHidden"] == "true" { return false }
            if !query.includeArchived, document.state["isArchived"] == "true" { return false }
            if let temporalFilter = query.temporalFilter, !temporalFilter.contains(document.temporal, sourceKind: document.sourceKind) { return false }
            if !Self.matchesFieldConstraints(query.fieldConstraints, document: document) { return false }
            return true
        }
        let candidates = filteredDocuments.filter { document in
            if tokens.isEmpty { return true }
            return Self.score(document: document, tokens: tokens, phrase: normalizedQuery.normalizedText, now: now, rankingProfile: query.rankingProfile).lexicalScore > 0
        }

        let corpusStatistics = Self.corpusStatistics(for: Array(filteredDocuments), tokens: tokens)
        let results = candidates.map { document -> NativeSearchResult in
            let scored = Self.score(document: document, tokens: tokens, phrase: normalizedQuery.normalizedText, now: now, rankingProfile: query.rankingProfile, corpusStatistics: corpusStatistics)
            let matchedTerms = Self.matchedTerms(for: document, tokens: tokens)
            let snippet = query.includeBodySnippets ? Self.bestSnippet(for: document, tokens: matchedTerms.isEmpty ? tokens : matchedTerms) : document.summary
            let rankReason = "lexical=\(Self.rounded(scored.lexicalScore)); bm25=\(Self.rounded(scored.lexicalScore)); idf=\(Self.idfReason(tokens: tokens, statistics: corpusStatistics)); freshness=\(Self.rounded(scored.freshnessScore)); fields=\(scored.matchedFields.joined(separator: ","))"
            let timeReason = Self.timeReason(for: document, temporalFilter: query.temporalFilter)
            return NativeSearchResult(
                id: document.id,
                sourceKind: document.sourceKind,
                externalID: document.externalID,
                sourceInstanceID: document.sourceInstanceID,
                title: document.title,
                snippet: snippet,
                highlights: matchedTerms,
                score: scored.total,
                lexicalScore: scored.lexicalScore,
                freshnessScore: scored.freshnessScore,
                fieldScore: scored.fieldScore,
                temporal: document.temporal,
                resultTimeLabel: Self.resultTimeLabel(for: document.temporal.primaryTimeKind, sourceKind: document.sourceKind),
                diagnostics: NativeSearchResultDiagnostics(
                    matchedFields: scored.matchedFields,
                    indexedAt: document.temporal.indexedAt,
                    queryTokens: allQueryTokens,
                    softStopWords: softStopWords,
                    matchedTerms: matchedTerms,
                    matchedFieldScores: scored.matchedFieldScores,
                    fieldConstraints: query.fieldConstraints.mapKeys(\.rawValue),
                    rankReason: rankReason,
                    timeReason: timeReason
                )
            )
        }
        return Array(results.sorted { lhs, rhs in
            Self.compare(lhs, rhs, sort: query.temporalSort)
        }.prefix(query.limit))
    }

    public func health() async -> NativeSourceSearchHealthSnapshot {
        var counts: [NativeSearchSourceKind: Int] = [:]
        var lastIndexed: [NativeSearchSourceKind: Date] = [:]
        for document in documents.values {
            counts[document.sourceKind, default: 0] += 1
            if let indexedAt = document.temporal.indexedAt, indexedAt > (lastIndexed[document.sourceKind] ?? .distantPast) {
                lastIndexed[document.sourceKind] = indexedAt
            }
        }
        return NativeSourceSearchHealthSnapshot(
            documentCountBySource: counts,
            lastIndexedAtBySource: lastIndexed,
            lastError: lastError
        )
    }

    public func allDocuments() async -> [NativeSearchDocument] {
        documents.values.sorted { $0.id < $1.id }
    }

    private func persist() throws {
        guard let indexURL else { return }
        do {
            try fileManager.createDirectory(at: indexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let payload = PersistedIndex(documents: documents.values.sorted { $0.id < $1.id }, lastError: lastError)
            let data = try encoder.encode(payload)
            try data.write(to: indexURL, options: [.atomic])
        } catch {
            lastError = String(describing: error)
            throw error
        }
    }

    static func defaultPrimaryTime(for sourceKind: NativeSearchSourceKind, temporal: NativeSearchTemporalMetadata) -> Date? {
        switch sourceKind {
        case .rss: temporal.publishedAt ?? temporal.fetchedAt ?? temporal.updatedAt ?? temporal.indexedAt
        case .calendar: temporal.eventStartAt ?? temporal.updatedAt ?? temporal.createdAt ?? temporal.indexedAt
        case .browserHistory: temporal.updatedAt ?? temporal.createdAt ?? temporal.indexedAt
        }
    }

    static func defaultPrimaryTimeKind(for sourceKind: NativeSearchSourceKind, temporal: NativeSearchTemporalMetadata) -> NativeSearchTimeKind {
        switch sourceKind {
        case .rss:
            if temporal.publishedAt != nil { return .publishedAt }
            if temporal.fetchedAt != nil { return .fetchedAt }
        case .calendar:
            if temporal.eventStartAt != nil { return .eventStartAt }
        case .browserHistory:
            if temporal.updatedAt != nil { return .updatedAt }
            if temporal.createdAt != nil { return .createdAt }
        }
        if temporal.updatedAt != nil { return .updatedAt }
        if temporal.createdAt != nil { return .createdAt }
        if temporal.indexedAt != nil { return .indexedAt }
        return .unknown
    }

    static func corpusStatistics(for documents: [NativeSearchDocument], tokens: [String]) -> NativeSearchCorpusStatistics {
        let fields: [(String, (NativeSearchDocument) -> String)] = [
            ("title", { $0.title }),
            ("participants", { $0.participants.joined(separator: " ") }),
            ("summary", { $0.summary }),
            ("location", { $0.location ?? "" }),
            ("body", { $0.body ?? "" })
        ]
        var df: [String: Int] = [:]
        var fieldLengths: [String: Double] = [:]
        let uniqueTokens = Set(tokens)
        for document in documents {
            var documentTerms: Set<String> = []
            for (fieldName, fieldValue) in fields {
                let normalized = NativeSearchQueryNormalizer.normalize(fieldValue(document)).scoringTokens.map(\.value)
                fieldLengths[fieldName, default: 0] += Double(max(normalized.count, 1))
                let tokenSet = Set(normalized)
                for token in uniqueTokens where tokenSet.contains(token) || fieldValue(document).lowercased().contains(token) {
                    documentTerms.insert(token)
                }
            }
            for token in documentTerms { df[token, default: 0] += 1 }
        }
        let divisor = max(Double(documents.count), 1)
        let averages = fieldLengths.mapValues { max(1, $0 / divisor) }
        return NativeSearchCorpusStatistics(documentCount: documents.count, documentFrequencyByToken: df, averageFieldLength: averages)
    }

    static func idfReason(tokens: [String], statistics: NativeSearchCorpusStatistics) -> String {
        tokens.map { "\($0):\(rounded(statistics.idf(for: $0)))" }.joined(separator: ",")
    }

    static func score(document: NativeSearchDocument, tokens: [String], phrase: String, now: Date, rankingProfile: NativeSearchRankingProfile, corpusStatistics: NativeSearchCorpusStatistics? = nil) -> (total: Double, lexicalScore: Double, freshnessScore: Double, fieldScore: Double, matchedFields: [String], matchedFieldScores: [String: Double]) {
        guard !tokens.isEmpty else {
            let freshness = freshnessScore(for: document, now: now, rankingProfile: rankingProfile)
            return (freshness, 0, freshness, 0, [], [:])
        }
        var lexical = 0.0
        var field = 0.0
        var matched: Set<String> = []
        var matchedFieldScores: [String: Double] = [:]
        var coveredTokens: Set<String> = []
        let uniqueTokens = Array(Set(tokens))
        let fields = weightedFields(for: document)
        for token in uniqueTokens {
            for (name, value, weight, lengthPenalty) in fields {
                let lower = value.lowercased()
                guard lower.contains(token) else { continue }
                let occurrences = occurrenceCount(of: token, in: lower)
                let contribution: Double
                if let corpusStatistics {
                    let fieldLength = Double(NativeSearchQueryNormalizer.normalize(value).scoringTokens.count)
                    let averageLength = max(1, corpusStatistics.averageFieldLength[name] ?? fieldLength)
                    let tf = Double(occurrences)
                    let k1 = 1.2
                    let b = 0.75
                    let denominator = tf + k1 * (1 - b + b * fieldLength / averageLength)
                    let bm25 = denominator > 0 ? corpusStatistics.idf(for: token) * (tf * (k1 + 1)) / denominator : 0
                    contribution = weight * bm25
                } else {
                    let cappedFrequency = min(Double(occurrences), 3.0)
                    let dampening = 1.0 / (1.0 + max(0, Double(lower.count - 80)) * lengthPenalty / 100.0)
                    contribution = weight * (1.0 + log(cappedFrequency)) * dampening
                }
                lexical += contribution
                field += contribution
                matched.insert(name)
                matchedFieldScores[name, default: 0] += contribution
                coveredTokens.insert(token)
            }
        }

        if uniqueTokens.count > 1 {
            let coverage = Double(coveredTokens.count) / Double(uniqueTokens.count)
            lexical *= 0.75 + coverage
        }

        if phrase.split(separator: " ").count > 1 {
            for (name, value, weight, _) in fields {
                let lower = value.lowercased()
                if lower.contains(phrase) {
                    lexical += weight * 3.0
                    field += weight * 3.0
                    matched.insert(name)
                    matchedFieldScores[name, default: 0] += weight * 3.0
                }
            }
        }

        let freshness = freshnessScore(for: document, now: now, rankingProfile: rankingProfile)
        let total = lexical + freshness
        return (total, lexical, freshness, field, Array(matched).sorted(), matchedFieldScores)
    }

    static func weightedFields(for document: NativeSearchDocument) -> [(String, String, Double, Double)] {
        switch document.sourceKind {
        case .browserHistory:
            return [
                ("title", document.title, 12, 0.12),
                ("summary", document.summary, 7, 0.08),
                ("participants", document.participants.joined(separator: " "), 4, 0.10),
                ("location", document.location ?? "", 0, 0.10),
                ("body", document.body ?? "", 0.75, 0.08)
            ]
        default:
            return [
                ("title", document.title, 8, 0.15),
                ("participants", document.participants.joined(separator: " "), 5, 0.10),
                ("summary", document.summary, 4, 0.08),
                ("location", document.location ?? "", 3, 0.10),
                ("body", document.body ?? "", 2, 0.03)
            ]
        }
    }

    static func occurrenceCount(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var searchRange = haystack.startIndex..<haystack.endIndex
        while let range = haystack.range(of: needle, options: [], range: searchRange) {
            count += 1
            searchRange = range.upperBound..<haystack.endIndex
        }
        return count
    }

    static func freshnessScore(for document: NativeSearchDocument, now: Date, rankingProfile: NativeSearchRankingProfile) -> Double {
        guard let time = document.temporal.primaryTime else { return 0 }
        let age = abs(now.timeIntervalSince(time))
        let day = 86_400.0
        let base = max(0, 3.0 - min(age / day, 90) / 30.0)
        switch rankingProfile {
        case .recentFirst: return base * 1.5
        case .calendarUpcoming:
            return time >= now ? max(0, 5.0 - min(time.timeIntervalSince(now) / day, 30) / 6.0) : 0
        case .calendarHistorical:
            return time <= now ? base : 0
        case .evidenceDiscovery: return base * 0.4
        case .exactLookup: return base * 0.2
        case .general: return base
        }
    }

    static func matchesFieldConstraints(_ constraints: [NativeSearchFieldConstraintKey: [String]], document: NativeSearchDocument) -> Bool {
        guard !constraints.isEmpty else { return true }
        for (key, values) in constraints {
            let haystack: String
            switch key {
            case .sender, .recipient:
                haystack = document.participants.joined(separator: " ").lowercased()
            case .feed, .source:
                haystack = [
                    document.sourceInstanceID ?? "",
                    document.metadata["feedTitle"] ?? "",
                    document.metadata["sourceTitle"] ?? "",
                    document.metadata["feedURL"] ?? "",
                    document.metadata["source"] ?? ""
                ].joined(separator: " ").lowercased()
            case .location:
                haystack = (document.location ?? "").lowercased()
            case .title:
                haystack = document.title.lowercased()
            }
            guard values.allSatisfy({ haystack.contains($0.lowercased()) }) else { return false }
        }
        return true
    }

    static func matchedTerms(for document: NativeSearchDocument, tokens: [String]) -> [String] {
        let searchable = [
            document.title,
            document.participants.joined(separator: " "),
            document.summary,
            document.location ?? "",
            document.body ?? ""
        ].joined(separator: " ").lowercased()
        return tokens.filter { searchable.contains($0) }
    }

    static func bestSnippet(for document: NativeSearchDocument, tokens: [String]) -> String {
        let fields: [(String, String, Int, Double)] = [
            ("title", document.title, 40, 8),
            ("summary", document.summary, 120, 4),
            ("participants", document.participants.joined(separator: " "), 80, 5),
            ("location", document.location ?? "", 80, 3),
            ("body", document.body ?? "", 240, 2)
        ]
        let matches = fields.compactMap { field -> (text: String, maxLength: Int, token: String, score: Double)? in
            let lower = field.1.lowercased()
            let matchedTokens = tokens.filter { lower.contains($0) }
            guard let token = matchedTokens.first else { return nil }
            let score = Double(matchedTokens.count) * 10 + field.3
            return (field.1, field.2, token, score)
        }
        guard let match = matches.sorted(by: { $0.score > $1.score }).first else {
            return document.summary.isEmpty ? String((document.body ?? document.title).prefix(240)) : document.summary
        }
        return snippetWindow(text: match.text, token: match.token, maxLength: match.maxLength)
    }

    private static func snippetWindow(text: String, token: String, maxLength: Int) -> String {
        guard !text.isEmpty else { return "" }
        let lower = text.lowercased()
        guard let range = lower.range(of: token) else { return String(text.prefix(maxLength)) }
        let start = text.distance(from: text.startIndex, to: range.lowerBound)
        let contextBefore = min(80, maxLength / 3)
        let snippetStart = max(0, start - contextBefore)
        let snippetEnd = min(text.count, snippetStart + maxLength)
        let startIndex = text.index(text.startIndex, offsetBy: snippetStart)
        let endIndex = text.index(text.startIndex, offsetBy: snippetEnd)
        return String(text[startIndex..<endIndex])
    }

    static func rounded(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    static func timeReason(for document: NativeSearchDocument, temporalFilter: NativeSearchTemporalFilter?) -> String {
        guard let temporalFilter else {
            return "primaryTime=\(document.temporal.primaryTimeKind.rawValue)"
        }
        return "\(temporalFilter.mode.rawValue) on \(document.temporal.primaryTimeKind.rawValue)"
    }

    static func resultTimeLabel(for kind: NativeSearchTimeKind, sourceKind: NativeSearchSourceKind) -> String {
        switch kind {
        case .sentAt: "Sent"
        case .receivedAt: "Received"
        case .publishedAt: "Published"
        case .fetchedAt: "Fetched"
        case .eventStartAt: "Event starts"
        case .updatedAt: "Updated"
        case .createdAt: "Created"
        case .indexedAt: "Indexed"
        case .unknown:
            switch sourceKind {
                case .rss: "Item time"
            case .calendar: "Event time"
            case .browserHistory: "Visited"
            }
        }
    }

    static func compare(_ lhs: NativeSearchResult, _ rhs: NativeSearchResult, sort: NativeSearchTemporalSort) -> Bool {
        let lt = lhs.temporal.primaryTime ?? .distantPast
        let rt = rhs.temporal.primaryTime ?? .distantPast
        switch sort {
        case .relevanceThenTimeDesc:
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lt > rt
        case .relevanceThenTimeAsc:
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lt < rt
        case .timeDescThenRelevance:
            if lt != rt { return lt > rt }
            return lhs.score > rhs.score
        case .timeAscThenRelevance:
            if lt != rt { return lt < rt }
            return lhs.score > rhs.score
        }
    }
}

extension Dictionary where Key == NativeSearchFieldConstraintKey, Value == [String] {
    func mapKeys<T: Hashable>(_ transform: (Key) -> T) -> [T: Value] {
        Dictionary<T, Value>(uniqueKeysWithValues: map { (transform($0.key), $0.value) })
    }
}
