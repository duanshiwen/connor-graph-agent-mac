import Foundation
import ConnorGraphAgent

public struct AppSessionManifest: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var sessionID: String
    public var updatedAt: Date
    public var stateFile: String?
    public var recordsFile: String?
    public var browserStateFile: String?
    public var workspace: AppSessionWorkspaceReference?
    public var attachmentSummary: AppSessionAttachmentSummary?
    public var recordSummary: AppSessionRecordSummary?

    public init(
        schemaVersion: Int = 1,
        sessionID: String,
        updatedAt: Date = Date(),
        stateFile: String? = "state/session-state.json",
        recordsFile: String? = "state/records.jsonl",
        browserStateFile: String? = "browser/browser-state.json",
        workspace: AppSessionWorkspaceReference? = nil,
        attachmentSummary: AppSessionAttachmentSummary? = nil,
        recordSummary: AppSessionRecordSummary? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.sessionID = sessionID
        self.updatedAt = updatedAt
        self.stateFile = stateFile
        self.recordsFile = recordsFile
        self.browserStateFile = browserStateFile
        self.workspace = workspace
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
    public var workspace: AppSessionWorkspaceReference?
    public var recordSummary: AppSessionRecordSummary?
    public var attachmentSummary: AppSessionAttachmentSummary?
    public var llmOverride: SessionLLMOverride?
    public var anchorState: SessionAnchorState?

    public init(
        schemaVersion: Int = 1,
        sessionID: String,
        updatedAt: Date = Date(),
        selectedPane: String? = nil,
        activityTimelineCache: [AgentEventPresentation]? = nil,
        browser: AppBrowserStateReference? = nil,
        workspace: AppSessionWorkspaceReference? = nil,
        recordSummary: AppSessionRecordSummary? = nil,
        attachmentSummary: AppSessionAttachmentSummary? = nil,
        llmOverride: SessionLLMOverride? = nil,
        anchorState: SessionAnchorState? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.sessionID = sessionID
        self.updatedAt = updatedAt
        self.selectedPane = selectedPane
        self.activityTimelineCache = activityTimelineCache
        self.browser = browser
        self.workspace = workspace
        self.recordSummary = recordSummary
        self.attachmentSummary = attachmentSummary
        self.llmOverride = llmOverride
        self.anchorState = anchorState
    }
}

public struct AppSessionWorkspaceRootReference: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var displayName: String
    public var path: String
    public var role: String
    public var isPrimary: Bool
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        displayName: String,
        path: String,
        role: String = "project",
        isPrimary: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.path = path
        self.role = role
        self.isPrimary = isPrimary
        self.updatedAt = updatedAt
    }
}

public struct AppSessionWorkspaceReference: Codable, Equatable, Sendable {
    public var workingDirectoryPath: String
    public var source: String
    public var updatedAt: Date
    public var roots: [AppSessionWorkspaceRootReference]

    public init(
        workingDirectoryPath: String,
        source: String,
        updatedAt: Date = Date(),
        roots: [AppSessionWorkspaceRootReference] = []
    ) {
        self.workingDirectoryPath = workingDirectoryPath
        self.source = source
        self.updatedAt = updatedAt
        self.roots = roots
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

public enum BrowserBuiltInPage: Sendable {
    public static let blankURLString = "connor://browser/blank"
    public static let webViewBaseURL: URL? = nil

    public static var blankHTML: String {
        """
        <!doctype html>
        <html lang="zh-CN">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Connor Browser</title>
          <style>
            :root { color-scheme: light dark; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif; }
            body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: radial-gradient(circle at 30% 20%, rgba(255,149,0,.16), transparent 34%), Canvas; color: CanvasText; }
            main { width: min(680px, calc(100vw - 48px)); padding: 36px; border: 1px solid color-mix(in srgb, CanvasText 12%, transparent); border-radius: 24px; background: color-mix(in srgb, Canvas 86%, transparent); box-shadow: 0 24px 80px rgba(0,0,0,.12); }
            .eyebrow { font-size: 13px; letter-spacing: .08em; text-transform: uppercase; opacity: .56; font-weight: 700; }
            h1 { margin: 10px 0 12px; font-size: 36px; line-height: 1.08; }
            p { margin: 0; font-size: 16px; line-height: 1.7; opacity: .72; }
            .hint { margin-top: 22px; padding: 14px 16px; border-radius: 14px; background: color-mix(in srgb, CanvasText 7%, transparent); font-size: 14px; }
          </style>
        </head>
        <body>
          <main>
            <div class="eyebrow">康纳同学 · 浏览器</div>
            <h1>康纳同学的浏览起点</h1>
            <p>你可以在这里打开网页、搜索资料，或者把当前页面作为会话里的工作上下文。康纳同学会把浏览、选区和对话放在同一个会话里，方便你继续追问、整理和行动。</p>
            <div class="hint">提示：每个会话都有独立的浏览标签、网页选区和工作上下文，不会和其他会话混在一起。</div>
          </main>
        </body>
        </html>
        """
    }

    public static func errorHTML(failedURLString: String, message: String) -> String {
        let failedURL = escapeHTML(failedURLString)
        let escapedMessage = escapeHTML(message)
        return """
        <!doctype html>
        <html lang="zh-CN">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>这个页面暂时打不开</title>
          <style>
            :root { color-scheme: light dark; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif; }
            body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: radial-gradient(circle at 28% 18%, rgba(255,59,48,.16), transparent 32%), Canvas; color: CanvasText; }
            main { width: min(720px, calc(100vw - 48px)); padding: 36px; border: 1px solid color-mix(in srgb, #ff3b30 34%, transparent); border-radius: 24px; background: color-mix(in srgb, Canvas 88%, transparent); box-shadow: 0 24px 80px rgba(0,0,0,.12); }
            .eyebrow { font-size: 13px; letter-spacing: .08em; text-transform: uppercase; color: #ff3b30; font-weight: 800; }
            h1 { margin: 10px 0 12px; font-size: 34px; line-height: 1.12; }
            p { margin: 0; font-size: 16px; line-height: 1.7; opacity: .76; }
            code { display: block; margin-top: 16px; padding: 14px 16px; border-radius: 14px; background: color-mix(in srgb, CanvasText 7%, transparent); overflow-wrap: anywhere; font-family: "SF Mono", ui-monospace, monospace; font-size: 13px; }
            .message { margin-top: 14px; color: color-mix(in srgb, CanvasText 72%, transparent); }
          </style>
        </head>
        <body>
          <main>
            <div class="eyebrow">康纳同学 · 页面状态</div>
            <h1>这个页面暂时打不开</h1>
            <p>康纳同学没能成功加载这个地址。可能是网址有误、网络暂时不可用，或者目标网站拒绝了访问。</p>
            <p class="message">你可以检查地址后重试，也可以复制这个链接回到会话里，让康纳同学帮你换一种方式查找资料。</p>
            <code>\(failedURL)</code>
            <p class="message">\(escapedMessage)</p>
          </main>
        </body>
        </html>
        """
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
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

public struct AppBrowserFormDraftSnapshot: Codable, Equatable, Sendable {
    public var selectorHint: String
    public var name: String?
    public var type: String?
    public var valuePreview: String
    public var valueHash: String

    public init(selectorHint: String, name: String? = nil, type: String? = nil, valuePreview: String, valueHash: String) {
        self.selectorHint = selectorHint
        self.name = name
        self.type = type
        self.valuePreview = valuePreview
        self.valueHash = valueHash
    }
}

public enum AppBrowserTabRestorationStatus: String, Codable, Equatable, Sendable {
    case live
    case evicted
    case restoredFromSnapshot
    case restoreFailed
}

public struct AppBrowserTabSnapshot: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var initialURLString: String
    public var title: String
    public var currentURLString: String
    public var isLoading: Bool
    public var canGoBack: Bool
    public var canGoForward: Bool
    public var lastAccessedAt: Date?
    public var lastVisibleAt: Date?
    public var scrollX: Double?
    public var scrollY: Double?
    public var viewportWidth: Double?
    public var viewportHeight: Double?
    public var contentFingerprint: String?
    public var focusedElementHint: String?
    public var formDrafts: [AppBrowserFormDraftSnapshot]?
    public var restorationStatus: AppBrowserTabRestorationStatus?

    public init(
        id: UUID = UUID(),
        initialURLString: String,
        title: String = "",
        currentURLString: String,
        isLoading: Bool = false,
        canGoBack: Bool = false,
        canGoForward: Bool = false,
        lastAccessedAt: Date? = nil,
        lastVisibleAt: Date? = nil,
        scrollX: Double? = nil,
        scrollY: Double? = nil,
        viewportWidth: Double? = nil,
        viewportHeight: Double? = nil,
        contentFingerprint: String? = nil,
        focusedElementHint: String? = nil,
        formDrafts: [AppBrowserFormDraftSnapshot]? = nil,
        restorationStatus: AppBrowserTabRestorationStatus? = nil
    ) {
        self.id = id
        self.initialURLString = initialURLString
        self.title = title
        self.currentURLString = currentURLString
        self.isLoading = isLoading
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.lastAccessedAt = lastAccessedAt
        self.lastVisibleAt = lastVisibleAt
        self.scrollX = scrollX
        self.scrollY = scrollY
        self.viewportWidth = viewportWidth
        self.viewportHeight = viewportHeight
        self.contentFingerprint = contentFingerprint
        self.focusedElementHint = focusedElementHint
        self.formDrafts = formDrafts
        self.restorationStatus = restorationStatus
    }
}

public extension AppBrowserTabSnapshot {
    var restoredURLString: String {
        let current = currentURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !current.isEmpty { return current }
        let initial = initialURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !initial.isEmpty { return initial }
        return BrowserBuiltInPage.blankURLString
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
    public var isPending: Bool

    public init(id: UUID = UUID(), role: Role, text: String, createdAt: Date = Date(), isPending: Bool = false) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.isPending = isPending
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case text
        case createdAt
        case isPending
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.role = try container.decode(Role.self, forKey: .role)
        self.text = try container.decode(String.self, forKey: .text)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.isPending = try container.decodeIfPresent(Bool.self, forKey: .isPending) ?? false
    }
}

// MARK: - Browser History

public enum BrowserHistoryContentFetchStatus: String, Codable, Sendable {
    case pending
    case fetched
    case failed
}

public struct BrowserHistoryRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var url: String
    public var title: String
    public var sessionID: String
    public var sessionTitle: String
    public var visitedAt: Date
    public var contentMarkdown: String?
    public var contentFetchedAt: Date?
    public var contentFetchStatus: BrowserHistoryContentFetchStatus?
    public var contentFetchError: String?

    public init(
        id: UUID = UUID(),
        url: String,
        title: String,
        sessionID: String,
        sessionTitle: String,
        visitedAt: Date = Date(),
        contentMarkdown: String? = nil,
        contentFetchedAt: Date? = nil,
        contentFetchStatus: BrowserHistoryContentFetchStatus? = nil,
        contentFetchError: String? = nil
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.sessionID = sessionID
        self.sessionTitle = sessionTitle
        self.visitedAt = visitedAt
        self.contentMarkdown = contentMarkdown
        self.contentFetchedAt = contentFetchedAt
        self.contentFetchStatus = contentFetchStatus
        self.contentFetchError = contentFetchError
    }
}

// MARK: - Browser Bookmarks

public struct BrowserBookmarkRecord: Codable, Equatable, Identifiable, Sendable {
    public static let defaultGroupName = "默认"

    public var id: UUID
    public var url: String
    public var title: String
    public var groupName: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        url: String,
        title: String,
        groupName: String = BrowserBookmarkRecord.defaultGroupName,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.groupName = groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Self.defaultGroupName : groupName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
