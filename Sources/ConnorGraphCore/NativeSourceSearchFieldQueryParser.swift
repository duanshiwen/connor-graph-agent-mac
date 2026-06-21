import Foundation

public enum NativeSearchFieldConstraintKey: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case sender
    case recipient
    case feed
    case source
    case location
    case title
}

public struct NativeSearchParsedFieldQuery: Codable, Sendable, Equatable, Hashable {
    public var rawText: String
    public var residualText: String
    public var fieldConstraints: [NativeSearchFieldConstraintKey: [String]]
    public var sourceKinds: Set<NativeSearchSourceKind>?
    public var temporalFilter: NativeSearchTemporalFilter?

    public init(
        rawText: String,
        residualText: String,
        fieldConstraints: [NativeSearchFieldConstraintKey: [String]] = [:],
        sourceKinds: Set<NativeSearchSourceKind>? = nil,
        temporalFilter: NativeSearchTemporalFilter? = nil
    ) {
        self.rawText = rawText
        self.residualText = residualText
        self.fieldConstraints = fieldConstraints
        self.sourceKinds = sourceKinds
        self.temporalFilter = temporalFilter
    }

    public var stringFieldConstraints: [String: [String]] {
        Dictionary(uniqueKeysWithValues: fieldConstraints.map { ($0.key.rawValue, $0.value) })
    }

    public func makeQuery(
        sourceKinds explicitSourceKinds: Set<NativeSearchSourceKind>? = nil,
        sourceInstanceIDs: Set<String>? = nil,
        temporalFilter explicitTemporalFilter: NativeSearchTemporalFilter? = nil,
        temporalSort: NativeSearchTemporalSort = .relevanceThenTimeDesc,
        limit: Int = 20,
        includeHidden: Bool = false,
        includeArchived: Bool = false,
        includeBodySnippets: Bool = false,
        rankingProfile: NativeSearchRankingProfile = .general
    ) -> NativeSearchQuery {
        NativeSearchQuery(
            text: residualText,
            sourceKinds: explicitSourceKinds ?? sourceKinds,
            sourceInstanceIDs: sourceInstanceIDs,
            temporalFilter: explicitTemporalFilter ?? temporalFilter,
            temporalSort: temporalSort,
            limit: limit,
            includeHidden: includeHidden,
            includeArchived: includeArchived,
            includeBodySnippets: includeBodySnippets,
            rankingProfile: rankingProfile,
            fieldConstraints: fieldConstraints
        )
    }
}

public enum NativeSearchFieldAwareQueryParser {
    public static func parse(_ rawText: String) -> NativeSearchParsedFieldQuery {
        let tokens = splitRespectingQuotes(rawText)
        var residual: [String] = []
        var constraints: [NativeSearchFieldConstraintKey: [String]] = [:]
        var sourceKinds: Set<NativeSearchSourceKind>?
        var start: Date?
        var end: Date?

        for token in tokens {
            guard let separator = token.firstIndex(of: ":") else {
                residual.append(token)
                continue
            }
            let rawKey = String(token[..<separator]).lowercased()
            let rawValue = String(token[token.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawValue.isEmpty else {
                residual.append(token)
                continue
            }
            let value = unquote(rawValue).lowercased()
            switch rawKey {
            case "from", "sender":
                constraints[.sender, default: []].append(value)
            case "to", "recipient":
                constraints[.recipient, default: []].append(value)
            case "feed":
                constraints[.feed, default: []].append(value)
            case "source":
                constraints[.source, default: []].append(value)
            case "location":
                constraints[.location, default: []].append(value)
            case "title":
                constraints[.title, default: []].append(value)
            case "kind":
                if let kind = NativeSearchSourceKind(rawValue: value) {
                    var kinds = sourceKinds ?? []
                    kinds.insert(kind)
                    sourceKinds = kinds
                } else {
                    residual.append(token)
                }
            case "after", "since":
                if let parsed = parseDate(value) { start = parsed } else { residual.append(token) }
            case "before":
                if let parsed = parseDate(value) { end = parsed } else { residual.append(token) }
            default:
                residual.append(token)
            }
        }

        let temporalFilter: NativeSearchTemporalFilter?
        if start != nil || end != nil {
            temporalFilter = NativeSearchTemporalFilter(start: start, end: end, mode: .pointWithinRange, timeFieldPreference: [], timezoneIdentifier: "UTC")
        } else {
            temporalFilter = nil
        }

        return NativeSearchParsedFieldQuery(
            rawText: rawText,
            residualText: residual.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines),
            fieldConstraints: constraints,
            sourceKinds: sourceKinds,
            temporalFilter: temporalFilter
        )
    }

    private static func splitRespectingQuotes(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var isQuoted = false
        for character in text {
            if character == "\"" {
                isQuoted.toggle()
                current.append(character)
                continue
            }
            if character.isWhitespace, !isQuoted {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2, value.first == "\"", value.last == "\"" else { return value }
        return String(value.dropFirst().dropLast())
    }

    private static func parseDate(_ value: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: value) { return date }
        iso.formatOptions = [.withFullDate]
        if let date = iso.date(from: value) { return date }
        return nil
    }
}
