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
        let tokens = Self.tokens(query.text)
        let now = Date()
        let candidates = documents.values.filter { document in
            if let kinds = query.sourceKinds, !kinds.contains(document.sourceKind) { return false }
            if let ids = query.sourceInstanceIDs, !(document.sourceInstanceID.map { ids.contains($0) } ?? false) { return false }
            if !query.includeHidden, document.state["isHidden"] == "true" { return false }
            if !query.includeArchived, document.state["isArchived"] == "true" { return false }
            if let temporalFilter = query.temporalFilter, !temporalFilter.contains(document.temporal, sourceKind: document.sourceKind) { return false }
            if tokens.isEmpty { return true }
            return Self.score(document: document, tokens: tokens, now: now, rankingProfile: query.rankingProfile).lexicalScore > 0
        }

        let results = candidates.map { document -> NativeSearchResult in
            let scored = Self.score(document: document, tokens: tokens, now: now, rankingProfile: query.rankingProfile)
            let snippet = query.includeBodySnippets ? Self.bestSnippet(for: document, tokens: tokens) : document.summary
            return NativeSearchResult(
                id: document.id,
                sourceKind: document.sourceKind,
                externalID: document.externalID,
                sourceInstanceID: document.sourceInstanceID,
                title: document.title,
                snippet: snippet,
                highlights: tokens,
                score: scored.total,
                lexicalScore: scored.lexicalScore,
                freshnessScore: scored.freshnessScore,
                fieldScore: scored.fieldScore,
                temporal: document.temporal,
                resultTimeLabel: Self.resultTimeLabel(for: document.temporal.primaryTimeKind, sourceKind: document.sourceKind),
                diagnostics: NativeSearchResultDiagnostics(matchedFields: scored.matchedFields, indexedAt: document.temporal.indexedAt)
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

    private static func defaultPrimaryTime(for sourceKind: NativeSearchSourceKind, temporal: NativeSearchTemporalMetadata) -> Date? {
        switch sourceKind {
        case .mail: temporal.sentAt ?? temporal.receivedAt ?? temporal.updatedAt ?? temporal.createdAt ?? temporal.indexedAt
        case .rss: temporal.publishedAt ?? temporal.fetchedAt ?? temporal.updatedAt ?? temporal.indexedAt
        case .calendar: temporal.eventStartAt ?? temporal.updatedAt ?? temporal.createdAt ?? temporal.indexedAt
        }
    }

    private static func defaultPrimaryTimeKind(for sourceKind: NativeSearchSourceKind, temporal: NativeSearchTemporalMetadata) -> NativeSearchTimeKind {
        switch sourceKind {
        case .mail:
            if temporal.sentAt != nil { return .sentAt }
            if temporal.receivedAt != nil { return .receivedAt }
        case .rss:
            if temporal.publishedAt != nil { return .publishedAt }
            if temporal.fetchedAt != nil { return .fetchedAt }
        case .calendar:
            if temporal.eventStartAt != nil { return .eventStartAt }
        }
        if temporal.updatedAt != nil { return .updatedAt }
        if temporal.createdAt != nil { return .createdAt }
        if temporal.indexedAt != nil { return .indexedAt }
        return .unknown
    }

    private static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func score(document: NativeSearchDocument, tokens: [String], now: Date, rankingProfile: NativeSearchRankingProfile) -> (total: Double, lexicalScore: Double, freshnessScore: Double, fieldScore: Double, matchedFields: [String]) {
        guard !tokens.isEmpty else {
            let freshness = freshnessScore(for: document, now: now, rankingProfile: rankingProfile)
            return (freshness, 0, freshness, 0, [])
        }
        var lexical = 0.0
        var field = 0.0
        var matched: Set<String> = []
        let fields: [(String, String, Double)] = [
            ("title", document.title, 8),
            ("participants", document.participants.joined(separator: " "), 5),
            ("summary", document.summary, 4),
            ("location", document.location ?? "", 3),
            ("body", document.body ?? "", 2)
        ]
        for token in tokens {
            for (name, value, weight) in fields {
                let lower = value.lowercased()
                if lower.contains(token) {
                    lexical += weight
                    field += weight
                    matched.insert(name)
                }
            }
        }
        let freshness = freshnessScore(for: document, now: now, rankingProfile: rankingProfile)
        let total = lexical + freshness
        return (total, lexical, freshness, field, Array(matched).sorted())
    }

    private static func freshnessScore(for document: NativeSearchDocument, now: Date, rankingProfile: NativeSearchRankingProfile) -> Double {
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

    private static func bestSnippet(for document: NativeSearchDocument, tokens: [String]) -> String {
        guard let body = document.body, !body.isEmpty else { return document.summary }
        guard let token = tokens.first(where: { body.lowercased().contains($0) }) else { return document.summary }
        let lower = body.lowercased()
        guard let range = lower.range(of: token) else { return String(body.prefix(240)) }
        let start = body.distance(from: body.startIndex, to: range.lowerBound)
        let snippetStart = max(0, start - 80)
        let snippetEnd = min(body.count, start + 160)
        let startIndex = body.index(body.startIndex, offsetBy: snippetStart)
        let endIndex = body.index(body.startIndex, offsetBy: snippetEnd)
        return String(body[startIndex..<endIndex])
    }

    private static func resultTimeLabel(for kind: NativeSearchTimeKind, sourceKind: NativeSearchSourceKind) -> String {
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
            case .mail: "Message time"
            case .rss: "Item time"
            case .calendar: "Event time"
            }
        }
    }

    private static func compare(_ lhs: NativeSearchResult, _ rhs: NativeSearchResult, sort: NativeSearchTemporalSort) -> Bool {
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
