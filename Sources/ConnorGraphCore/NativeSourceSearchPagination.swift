import Foundation

public struct NativeSearchPageRequest: Codable, Sendable, Equatable {
    public var query: NativeSearchQuery
    public var pageSize: Int
    public var cursor: String?

    public init(query: NativeSearchQuery, pageSize: Int? = nil, cursor: String? = nil) {
        self.query = query
        self.pageSize = NativeSearchLimitPolicy.clampSearchLimit(pageSize ?? query.limit)
        self.cursor = cursor
    }
}

public struct NativeSearchPage: Codable, Sendable, Equatable {
    public var results: [NativeSearchResult]
    public var nextCursor: String?
    public var totalAvailable: Int?

    public init(results: [NativeSearchResult], nextCursor: String? = nil, totalAvailable: Int? = nil) {
        self.results = results
        self.nextCursor = nextCursor
        self.totalAvailable = totalAvailable
    }
}

public enum NativeSearchPaginationError: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidCursor
    case queryChanged

    public var description: String {
        switch self {
        case .invalidCursor: "invalidCursor"
        case .queryChanged: "queryChanged"
        }
    }
}

public struct NativeSearchCursorPayload: Codable, Sendable, Equatable, Hashable {
    public var version: Int
    public var backendKind: String
    public var querySignature: String
    public var offset: Int
    public var lastResultID: String?

    public init(version: Int = 1, backendKind: String, querySignature: String, offset: Int, lastResultID: String? = nil) {
        self.version = version
        self.backendKind = backendKind
        self.querySignature = querySignature
        self.offset = offset
        self.lastResultID = lastResultID
    }

    public func encode() throws -> String {
        let data = try JSONEncoder().encode(self)
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func decode(_ cursor: String) throws -> NativeSearchCursorPayload {
        var base64 = cursor
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        base64.append(String(repeating: "=", count: padding))
        guard let data = Data(base64Encoded: base64) else { throw NativeSearchPaginationError.invalidCursor }
        do {
            return try JSONDecoder().decode(NativeSearchCursorPayload.self, from: data)
        } catch {
            throw NativeSearchPaginationError.invalidCursor
        }
    }
}

public enum NativeSearchQuerySignature {
    public static func signature(for query: NativeSearchQuery) -> String {
        let sourceKinds = query.sourceKinds?.map(\.rawValue).sorted().joined(separator: ",") ?? "*"
        let sourceIDs = query.sourceInstanceIDs?.sorted().joined(separator: ",") ?? "*"
        let fields = query.fieldConstraints
            .map { key, values in "\(key.rawValue)=\(values.sorted().joined(separator: "|"))" }
            .sorted()
            .joined(separator: ";")
        let temporal = [
            query.temporalFilter?.start.map { String(format: "%.3f", $0.timeIntervalSince1970) } ?? "",
            query.temporalFilter?.end.map { String(format: "%.3f", $0.timeIntervalSince1970) } ?? "",
            query.temporalFilter?.mode.rawValue ?? ""
        ].joined(separator: ":")
        return [
            query.text.lowercased(),
            sourceKinds,
            sourceIDs,
            temporal,
            query.temporalSort.rawValue,
            String(query.includeHidden),
            String(query.includeArchived),
            String(query.includeBodySnippets),
            query.rankingProfile.rawValue,
            fields
        ].joined(separator: "\u{1F}")
    }
}
