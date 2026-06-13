import Foundation
import ConnorGraphAgent

public struct AppSessionManifest: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var sessionID: String
    public var updatedAt: Date
    public var stateFile: String?
    public var recordsFile: String?
    public var browserStateFile: String?
    public var attachmentSummary: AppSessionAttachmentSummary?
    public var recordSummary: AppSessionRecordSummary?

    public init(
        schemaVersion: Int = 1,
        sessionID: String,
        updatedAt: Date = Date(),
        stateFile: String? = "state/session-state.json",
        recordsFile: String? = "state/records.jsonl",
        browserStateFile: String? = "browser/browser-state.json",
        attachmentSummary: AppSessionAttachmentSummary? = nil,
        recordSummary: AppSessionRecordSummary? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.sessionID = sessionID
        self.updatedAt = updatedAt
        self.stateFile = stateFile
        self.recordsFile = recordsFile
        self.browserStateFile = browserStateFile
        self.attachmentSummary = attachmentSummary
        self.recordSummary = recordSummary
    }
}

public struct AppSessionStateSnapshot: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var sessionID: String
    public var updatedAt: Date
    public var selectedPane: String?
    public var activityTimelineCache: [AgentEventPresentation]?
    public var browser: AppBrowserStateReference?
    public var recordSummary: AppSessionRecordSummary?
    public var attachmentSummary: AppSessionAttachmentSummary?

    public init(
        schemaVersion: Int = 1,
        sessionID: String,
        updatedAt: Date = Date(),
        selectedPane: String? = nil,
        activityTimelineCache: [AgentEventPresentation]? = nil,
        browser: AppBrowserStateReference? = nil,
        recordSummary: AppSessionRecordSummary? = nil,
        attachmentSummary: AppSessionAttachmentSummary? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.sessionID = sessionID
        self.updatedAt = updatedAt
        self.selectedPane = selectedPane
        self.activityTimelineCache = activityTimelineCache
        self.browser = browser
        self.recordSummary = recordSummary
        self.attachmentSummary = attachmentSummary
    }
}

public struct AppBrowserStateReference: Codable, Equatable, Sendable {
    public var path: String
    public var tabCount: Int
    public var threadCount: Int
    public var updatedAt: Date

    public init(path: String = "browser/browser-state.json", tabCount: Int = 0, threadCount: Int = 0, updatedAt: Date = Date()) {
        self.path = path
        self.tabCount = tabCount
        self.threadCount = threadCount
        self.updatedAt = updatedAt
    }
}

public struct AppSessionRecordSummary: Codable, Equatable, Sendable {
    public var count: Int
    public var updatedAt: Date?

    public init(count: Int = 0, updatedAt: Date? = nil) {
        self.count = count
        self.updatedAt = updatedAt
    }
}

public struct AppSessionAttachmentSummary: Codable, Equatable, Sendable {
    public var count: Int
    public var totalBytes: Int64
    public var updatedAt: Date?

    public init(count: Int = 0, totalBytes: Int64 = 0, updatedAt: Date? = nil) {
        self.count = count
        self.totalBytes = totalBytes
        self.updatedAt = updatedAt
    }
}

public struct AppSessionRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var sessionID: String
    public var kind: String
    public var createdAt: Date
    public var title: String?
    public var body: String?
    public var metadata: [String: String]

    public init(
        id: String = UUID().uuidString,
        sessionID: String,
        kind: String,
        createdAt: Date = Date(),
        title: String? = nil,
        body: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.sessionID = sessionID
        self.kind = kind
        self.createdAt = createdAt
        self.title = title
        self.body = body
        self.metadata = metadata
    }
}

public struct AppBrowserStateSnapshot: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var updatedAt: Date
    public var tabs: [AppBrowserTabSnapshot]
    public var selectedTabID: UUID?
    public var selectionPopover: AppBrowserSelectionPopoverSnapshot?
    public var threads: [UUID: AppBrowserSelectionThreadSnapshot]

    public init(
        schemaVersion: Int = 1,
        updatedAt: Date = Date(),
        tabs: [AppBrowserTabSnapshot] = [],
        selectedTabID: UUID? = nil,
        selectionPopover: AppBrowserSelectionPopoverSnapshot? = nil,
        threads: [UUID: AppBrowserSelectionThreadSnapshot] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt
        self.tabs = tabs
        self.selectedTabID = selectedTabID
        self.selectionPopover = selectionPopover
        self.threads = threads
    }
}

public struct AppBrowserTabSnapshot: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var initialURLString: String
    public var title: String
    public var currentURLString: String
    public var isLoading: Bool
    public var canGoBack: Bool
    public var canGoForward: Bool

    public init(
        id: UUID = UUID(),
        initialURLString: String,
        title: String = "",
        currentURLString: String,
        isLoading: Bool = false,
        canGoBack: Bool = false,
        canGoForward: Bool = false
    ) {
        self.id = id
        self.initialURLString = initialURLString
        self.title = title
        self.currentURLString = currentURLString
        self.isLoading = isLoading
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
    }
}

public struct AppBrowserSelectionPopoverSnapshot: Codable, Equatable, Sendable {
    public var tabID: UUID
    public var pageURL: String
    public var pageTitle: String
    public var pageText: String
    public var selectedText: String
    public var rect: AppBrowserSelectionRect
    public var threadID: UUID

    public init(tabID: UUID, pageURL: String, pageTitle: String, pageText: String, selectedText: String, rect: AppBrowserSelectionRect, threadID: UUID) {
        self.tabID = tabID
        self.pageURL = pageURL
        self.pageTitle = pageTitle
        self.pageText = pageText
        self.selectedText = selectedText
        self.rect = rect
        self.threadID = threadID
    }
}

public struct AppBrowserSelectionRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct AppBrowserSelectionThreadSnapshot: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var tabID: UUID
    public var pageURL: String
    public var selectedText: String
    public var messages: [AppBrowserSelectionThreadMessageSnapshot]

    public init(id: UUID = UUID(), tabID: UUID, pageURL: String, selectedText: String, messages: [AppBrowserSelectionThreadMessageSnapshot] = []) {
        self.id = id
        self.tabID = tabID
        self.pageURL = pageURL
        self.selectedText = selectedText
        self.messages = messages
    }
}

public struct AppBrowserSelectionThreadMessageSnapshot: Codable, Equatable, Identifiable, Sendable {
    public enum Role: String, Codable, Equatable, Sendable {
        case user
        case assistant
    }

    public var id: UUID
    public var role: Role
    public var text: String
    public var createdAt: Date

    public init(id: UUID = UUID(), role: Role, text: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}
