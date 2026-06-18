import Foundation

public struct RSSSourceID: RawRepresentable, Codable, Sendable, Equatable, Hashable, Identifiable {
    public var rawValue: String
    public var id: String { rawValue }
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct RSSItemID: RawRepresentable, Codable, Sendable, Equatable, Hashable, Identifiable {
    public var rawValue: String
    public var id: String { rawValue }
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct RSSGroupID: RawRepresentable, Codable, Sendable, Equatable, Hashable, Identifiable {
    public var rawValue: String
    public var id: String { rawValue }
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct RSSFetchRunID: RawRepresentable, Codable, Sendable, Equatable, Hashable, Identifiable {
    public var rawValue: String
    public var id: String { rawValue }
    public init(rawValue: String) { self.rawValue = rawValue }
}

public enum RSSFeedFormat: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case rss
    case atom
    case jsonFeed
    case unknown
}

public enum RSSSourceOpenTarget: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case localReader
    case webpage
    case externalBrowser
    case fullContent
}

public enum RSSSourceTextDirection: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case ltr
    case rtl
    case vertical
}

public enum RSSSourceHealthStatus: String, Codable, Sendable, Equatable, Hashable {
    case ready
    case degraded
    case blocked
    case unknown
}

public struct RSSSourceHealth: Codable, Sendable, Equatable, Hashable {
    public var status: RSSSourceHealthStatus
    public var checkedAt: Date
    public var summary: String
    public var blockingReasons: [String]

    public init(status: RSSSourceHealthStatus, checkedAt: Date = Date(), summary: String, blockingReasons: [String] = []) {
        self.status = status
        self.checkedAt = checkedAt
        self.summary = summary
        self.blockingReasons = blockingReasons
    }
}

public struct RSSSourceFetchPolicy: Codable, Sendable, Equatable, Hashable {
    public var intervalMinutes: Int
    public var timeoutSeconds: Int
    public var maxItemsPerFetch: Int
    public var allowExternalNetwork: Bool

    public init(intervalMinutes: Int = 30, timeoutSeconds: Int = 30, maxItemsPerFetch: Int = 200, allowExternalNetwork: Bool = true) {
        self.intervalMinutes = intervalMinutes
        self.timeoutSeconds = timeoutSeconds
        self.maxItemsPerFetch = maxItemsPerFetch
        self.allowExternalNetwork = allowExternalNetwork
    }
}

public struct RSSSyncCursor: Codable, Sendable, Equatable, Hashable {
    public var value: String
    public var updatedAt: Date
    public var lastItemDate: Date?
    public var lastItemID: RSSItemID?

    public init(value: String, updatedAt: Date = Date(), lastItemDate: Date? = nil, lastItemID: RSSItemID? = nil) {
        self.value = value
        self.updatedAt = updatedAt
        self.lastItemDate = lastItemDate
        self.lastItemID = lastItemID
    }
}

public struct RSSSource: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: RSSSourceID
    public var feedURL: URL
    public var siteURL: URL?
    public var displayName: String
    public var iconURL: URL?
    public var format: RSSFeedFormat
    public var groupIDs: [RSSGroupID]
    public var openTarget: RSSSourceOpenTarget
    public var textDirection: RSSSourceTextDirection
    public var fetchPolicy: RSSSourceFetchPolicy
    public var syncCursor: RSSSyncCursor?
    public var unreadCount: Int
    public var isHidden: Bool
    public var health: RSSSourceHealth
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: RSSSourceID,
        feedURL: URL,
        siteURL: URL? = nil,
        displayName: String,
        iconURL: URL? = nil,
        format: RSSFeedFormat = .unknown,
        groupIDs: [RSSGroupID] = [],
        openTarget: RSSSourceOpenTarget = .localReader,
        textDirection: RSSSourceTextDirection = .ltr,
        fetchPolicy: RSSSourceFetchPolicy = RSSSourceFetchPolicy(),
        syncCursor: RSSSyncCursor? = nil,
        unreadCount: Int = 0,
        isHidden: Bool = false,
        health: RSSSourceHealth = RSSSourceHealth(status: .unknown, summary: "Not checked"),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.feedURL = feedURL
        self.siteURL = siteURL
        self.displayName = displayName
        self.iconURL = iconURL
        self.format = format
        self.groupIDs = groupIDs
        self.openTarget = openTarget
        self.textDirection = textDirection
        self.fetchPolicy = fetchPolicy
        self.syncCursor = syncCursor
        self.unreadCount = unreadCount
        self.isHidden = isHidden
        self.health = health
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct RSSGroup: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: RSSGroupID
    public var name: String
    public var parentID: RSSGroupID?
    public init(id: RSSGroupID, name: String, parentID: RSSGroupID? = nil) {
        self.id = id
        self.name = name
        self.parentID = parentID
    }
}

public struct RSSItemState: Codable, Sendable, Equatable, Hashable {
    public var isRead: Bool
    public var isStarred: Bool
    public var isHidden: Bool
    public var notify: Bool

    public init(isRead: Bool = false, isStarred: Bool = false, isHidden: Bool = false, notify: Bool = false) {
        self.isRead = isRead
        self.isStarred = isStarred
        self.isHidden = isHidden
        self.notify = notify
    }
}

public struct RSSItemMedia: Codable, Sendable, Equatable, Hashable {
    public var thumbnailURL: URL?
    public var imageURL: URL?
    public var enclosureURL: URL?
    public var mimeType: String?
    public init(thumbnailURL: URL? = nil, imageURL: URL? = nil, enclosureURL: URL? = nil, mimeType: String? = nil) {
        self.thumbnailURL = thumbnailURL
        self.imageURL = imageURL
        self.enclosureURL = enclosureURL
        self.mimeType = mimeType
    }
}

public struct RSSItemContent: Codable, Sendable, Equatable, Hashable {
    public var safeMarkdown: String
    public var plainText: String
    public var rawHTMLHash: String?
    public var byteCount: Int
    public var wasTruncated: Bool
    public var omittedReason: String?

    public init(safeMarkdown: String = "", plainText: String = "", rawHTMLHash: String? = nil, byteCount: Int = 0, wasTruncated: Bool = false, omittedReason: String? = nil) {
        self.safeMarkdown = safeMarkdown
        self.plainText = plainText
        self.rawHTMLHash = rawHTMLHash
        self.byteCount = byteCount
        self.wasTruncated = wasTruncated
        self.omittedReason = omittedReason
    }
}

public struct RSSItemSummary: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: RSSItemID
    public var sourceID: RSSSourceID
    public var externalID: String?
    public var title: String
    public var link: URL?
    public var author: String?
    public var publishedAt: Date
    public var fetchedAt: Date
    public var snippet: String
    public var media: RSSItemMedia
    public var state: RSSItemState
    public var contentHash: String

    public init(id: RSSItemID, sourceID: RSSSourceID, externalID: String? = nil, title: String, link: URL? = nil, author: String? = nil, publishedAt: Date = Date(), fetchedAt: Date = Date(), snippet: String = "", media: RSSItemMedia = RSSItemMedia(), state: RSSItemState = RSSItemState(), contentHash: String = "") {
        self.id = id
        self.sourceID = sourceID
        self.externalID = externalID
        self.title = title
        self.link = link
        self.author = author
        self.publishedAt = publishedAt
        self.fetchedAt = fetchedAt
        self.snippet = snippet
        self.media = media
        self.state = state
        self.contentHash = contentHash
    }
}

public struct RSSItemDetail: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: RSSItemID { summary.id }
    public var summary: RSSItemSummary
    public var content: RSSItemContent?
    public init(summary: RSSItemSummary, content: RSSItemContent? = nil) {
        self.summary = summary
        self.content = content
    }
}

public struct RSSFeedMetadata: Codable, Sendable, Equatable, Hashable {
    public var title: String
    public var siteURL: URL?
    public var feedURL: URL?
    public var description: String?
    public var iconURL: URL?
    public var format: RSSFeedFormat
    public init(title: String, siteURL: URL? = nil, feedURL: URL? = nil, description: String? = nil, iconURL: URL? = nil, format: RSSFeedFormat = .unknown) {
        self.title = title
        self.siteURL = siteURL
        self.feedURL = feedURL
        self.description = description
        self.iconURL = iconURL
        self.format = format
    }
}

public struct RSSParsedFeed: Codable, Sendable, Equatable, Hashable {
    public var metadata: RSSFeedMetadata
    public var items: [RSSItemDetail]
    public init(metadata: RSSFeedMetadata, items: [RSSItemDetail]) {
        self.metadata = metadata
        self.items = items
    }
}

public struct RSSFetchResult: Codable, Sendable, Equatable, Hashable {
    public var runID: RSSFetchRunID
    public var sourceID: RSSSourceID
    public var fetchedAt: Date
    public var insertedCount: Int
    public var duplicateCount: Int
    public var parseReport: RSSParseReport
    public init(runID: RSSFetchRunID, sourceID: RSSSourceID, fetchedAt: Date = Date(), insertedCount: Int, duplicateCount: Int, parseReport: RSSParseReport) {
        self.runID = runID
        self.sourceID = sourceID
        self.fetchedAt = fetchedAt
        self.insertedCount = insertedCount
        self.duplicateCount = duplicateCount
        self.parseReport = parseReport
    }
}

public struct RSSParseReport: Codable, Sendable, Equatable, Hashable {
    public var format: RSSFeedFormat
    public var itemCount: Int
    public var warnings: [String]
    public init(format: RSSFeedFormat, itemCount: Int, warnings: [String] = []) {
        self.format = format
        self.itemCount = itemCount
        self.warnings = warnings
    }
}

public struct OPMLSubscriptionOutline: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String { xmlURL.absoluteString }
    public var title: String
    public var xmlURL: URL
    public var htmlURL: URL?
    public var categoryPath: [String]
    public init(title: String, xmlURL: URL, htmlURL: URL? = nil, categoryPath: [String] = []) {
        self.title = title
        self.xmlURL = xmlURL
        self.htmlURL = htmlURL
        self.categoryPath = categoryPath
    }
}

public struct OPMLDocument: Codable, Sendable, Equatable, Hashable {
    public var title: String
    public var createdAt: Date
    public var outlines: [OPMLSubscriptionOutline]
    public init(title: String, createdAt: Date = Date(), outlines: [OPMLSubscriptionOutline]) {
        self.title = title
        self.createdAt = createdAt
        self.outlines = outlines
    }
}

public struct RSSEvidenceCandidate: Codable, Sendable, Equatable, Hashable {
    public var sourceID: RSSSourceID
    public var itemID: RSSItemID
    public var evidenceKind: String
    public var redactedSummary: String
    public var sourceHash: String
    public init(sourceID: RSSSourceID, itemID: RSSItemID, evidenceKind: String = "rss-item", redactedSummary: String, sourceHash: String) {
        self.sourceID = sourceID
        self.itemID = itemID
        self.evidenceKind = evidenceKind
        self.redactedSummary = redactedSummary
        self.sourceHash = sourceHash
    }
}
