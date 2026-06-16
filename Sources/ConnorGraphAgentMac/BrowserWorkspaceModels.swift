import Foundation
import WebKit
import ConnorGraphAppSupport

struct BrowserSessionState {
    var tabs: [BrowserTabState]
    var selectedTabID: BrowserTabState.ID?
    var selectionPopover: BrowserSelectionPopoverState?
    var threads: [UUID: BrowserSelectionThread] = [:]
    var webViewsByTabID: [UUID: WKWebView] = [:]

    init(tabs: [BrowserTabState], selectedTabID: BrowserTabState.ID?, selectionPopover: BrowserSelectionPopoverState? = nil, threads: [UUID: BrowserSelectionThread] = [:], webViewsByTabID: [UUID: WKWebView] = [:]) {
        self.tabs = tabs
        self.selectedTabID = selectedTabID
        self.selectionPopover = selectionPopover
        self.threads = threads
        self.webViewsByTabID = webViewsByTabID
    }

    init(snapshot: BrowserWorkspaceSnapshot?, webViewsByTabID: [UUID: WKWebView], fallbackURLString: String) {
        guard let snapshot else {
            self = .default(urlString: fallbackURLString)
            self.webViewsByTabID = webViewsByTabID
            return
        }
        self.tabs = snapshot.tabs.map { BrowserTabState(snapshot: $0, webView: webViewsByTabID[$0.id]) }
        self.selectedTabID = snapshot.selectedTabID ?? self.tabs.first?.id
        self.selectionPopover = snapshot.selectionPopover.map(BrowserSelectionPopoverState.init(snapshot:))
        self.threads = Dictionary(uniqueKeysWithValues: snapshot.threads.map { ($0.key, BrowserSelectionThread(snapshot: $0.value)) })
        self.webViewsByTabID = webViewsByTabID
        if self.tabs.isEmpty {
            let fallback = BrowserTabState(initialURLString: fallbackURLString)
            self.tabs = [fallback]
            self.selectedTabID = fallback.id
        }
    }

    static func `default`(urlString: String) -> BrowserSessionState {
        let tab = BrowserTabState(initialURLString: urlString)
        return BrowserSessionState(tabs: [tab], selectedTabID: tab.id)
    }

    var snapshot: BrowserWorkspaceSnapshot {
        BrowserWorkspaceSnapshot(
            tabs: tabs.map(\.snapshot),
            selectedTabID: selectedTabID,
            selectionPopover: selectionPopover?.snapshot,
            threads: Dictionary(uniqueKeysWithValues: threads.map { ($0.key, $0.value.snapshot) })
        )
    }

    func thread(for id: UUID) -> BrowserSelectionThread? {
        threads[id]
    }
}

struct BrowserTabState: Identifiable {
    let id: UUID
    var initialURLString: String
    var webView: WKWebView?
    var navigationState: WebNavigationState

    init(id: UUID = UUID(), initialURLString: String) {
        self.id = id
        self.initialURLString = initialURLString
        self.navigationState = WebNavigationState(canGoBack: false, canGoForward: false, title: "", url: initialURLString)
    }

    init(snapshot: BrowserTabSnapshot, webView: WKWebView?) {
        self.id = snapshot.id
        self.initialURLString = snapshot.initialURLString
        self.webView = webView
        self.navigationState = WebNavigationState(
            canGoBack: snapshot.canGoBack,
            canGoForward: snapshot.canGoForward,
            title: snapshot.title,
            url: snapshot.currentURLString,
            isLoading: snapshot.isLoading
        )
    }

    var snapshot: BrowserTabSnapshot {
        BrowserTabSnapshot(
            id: id,
            initialURLString: initialURLString,
            title: navigationState.title,
            currentURLString: displayURL,
            isLoading: navigationState.isLoading,
            canGoBack: navigationState.canGoBack,
            canGoForward: navigationState.canGoForward
        )
    }

    var displayTitle: String {
        let title = navigationState.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        if let host = URL(string: displayURL)?.host, !host.isEmpty { return host }
        return "新标签页"
    }

    var displayURL: String { navigationState.url.isEmpty ? initialURLString : navigationState.url }

    var restoredURLString: String {
        let restored = displayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return restored.isEmpty ? BrowserBuiltInPage.blankURLString : restored
    }
}

struct BrowserSelectionPopoverState {
    var tabID: BrowserTabState.ID
    var context: BrowserSelectionContext
    var rect: BrowserSelectionRect
    var threadID: UUID

    init(tabID: BrowserTabState.ID, context: BrowserSelectionContext, rect: BrowserSelectionRect, threadID: UUID) {
        self.tabID = tabID
        self.context = context
        self.rect = rect
        self.threadID = threadID
    }

    init(snapshot: BrowserSelectionPopoverSnapshot) {
        self.tabID = snapshot.tabID
        self.context = BrowserSelectionContext(
            page: BrowserPageContext(url: snapshot.pageURL, title: snapshot.pageTitle, text: snapshot.pageText),
            selectedText: snapshot.selectedText
        )
        self.rect = snapshot.rect
        self.threadID = snapshot.threadID
    }

    var snapshot: BrowserSelectionPopoverSnapshot {
        BrowserSelectionPopoverSnapshot(
            tabID: tabID,
            pageURL: context.page.url,
            pageTitle: context.page.title,
            pageText: context.page.text,
            selectedText: context.selectedText,
            rect: rect,
            threadID: threadID
        )
    }
}

struct BrowserSelectionThread: Identifiable {
    var id: UUID
    var tabID: BrowserTabState.ID
    var pageURL: String
    var selectedText: String
    var messages: [BrowserSelectionThreadMessage]

    init(id: UUID, tabID: BrowserTabState.ID, pageURL: String, selectedText: String, messages: [BrowserSelectionThreadMessage]) {
        self.id = id
        self.tabID = tabID
        self.pageURL = pageURL
        self.selectedText = selectedText
        self.messages = messages
    }

    init(snapshot: BrowserSelectionThreadSnapshot) {
        self.id = snapshot.id
        self.tabID = snapshot.tabID
        self.pageURL = snapshot.pageURL
        self.selectedText = snapshot.selectedText
        self.messages = snapshot.messages.map(BrowserSelectionThreadMessage.init(snapshot:))
    }

    var snapshot: BrowserSelectionThreadSnapshot {
        BrowserSelectionThreadSnapshot(
            id: id,
            tabID: tabID,
            pageURL: pageURL,
            selectedText: selectedText,
            messages: messages.map(\.snapshot)
        )
    }

    static func stableID(tabID: UUID, pageURL: String, selectedText: String) -> UUID {
        let key = "\(tabID.uuidString)|\(pageURL)|\(selectedText.prefix(120))"
        return UUID(uuidString: UUID.nameUUIDFromBytes(key)) ?? UUID()
    }

    static func stablePageID(tabID: UUID, pageURL: String) -> UUID {
        let key = "\(tabID.uuidString)|\(pageURL)|__page__"
        return UUID(uuidString: UUID.nameUUIDFromBytes(key)) ?? UUID()
    }
}

struct BrowserSelectionThreadMessage: Identifiable {
    enum Role { case user, assistant }
    var id: UUID = UUID()
    var role: Role
    var text: String
    var createdAt: Date
    var isPending: Bool

    init(id: UUID = UUID(), role: Role, text: String, createdAt: Date, isPending: Bool = false) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.isPending = isPending
    }

    init(snapshot: BrowserSelectionThreadMessageSnapshot) {
        self.id = snapshot.id
        self.role = snapshot.role == .user ? .user : .assistant
        self.text = snapshot.text
        self.createdAt = snapshot.createdAt
        self.isPending = snapshot.isPending
    }

    var snapshot: BrowserSelectionThreadMessageSnapshot {
        BrowserSelectionThreadMessageSnapshot(
            id: id,
            role: role == .user ? .user : .assistant,
            text: text,
            createdAt: createdAt,
            isPending: isPending
        )
    }
}

struct BrowserSelectionPayload: Decodable {
    var pageURL: String
    var pageTitle: String
    var pageText: String
    var selectedText: String
    var rect: BrowserSelectionRect
}

struct BrowserPageQuestionPayload: Decodable {
    var pageURL: String
    var pageTitle: String
    var pageText: String
}

