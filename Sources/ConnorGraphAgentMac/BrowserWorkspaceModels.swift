import Foundation
import WebKit
import ConnorGraphCore
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

enum BrowserDownloadStatus: String, Equatable {
    case preparing
    case downloading
    case finished
    case failed
    case cancelled
}

struct BrowserDownloadItem: Identifiable, Equatable {
    var id: UUID
    var sourceURL: URL?
    var filename: String
    var destinationURL: URL?
    var progress: Double
    var status: BrowserDownloadStatus
    var errorMessage: String?
    var startedAt: Date
}

enum BrowserSitePermissionKind: String, Codable, CaseIterable, Identifiable {
    case camera
    case microphone

    var id: String { rawValue }
    var displayName: String { self == .camera ? "摄像头" : "麦克风" }
    var systemImage: String { self == .camera ? "video" : "mic" }
}

enum BrowserSitePermissionDecision: String, Codable {
    case allow
    case deny
}

struct BrowserSitePermissionRecord: Codable, Equatable {
    var origin: String
    var decisions: [BrowserSitePermissionKind: BrowserSitePermissionDecision]
}

struct BrowserTabState: Identifiable {
    let id: UUID
    var initialURLString: String
    var webView: WKWebView?
    var navigationState: WebNavigationState
    var lastAccessedAt: Date?
    var lastVisibleAt: Date?
    var scrollX: Double?
    var scrollY: Double?
    var viewportWidth: Double?
    var viewportHeight: Double?
    var contentFingerprint: String?
    var focusedElementHint: String?
    var formDrafts: [AppBrowserFormDraftSnapshot]?
    var restorationStatus: AppBrowserTabRestorationStatus?
    var localFileReadAccessPath: String?

    init(id: UUID = UUID(), initialURLString: String) {
        self.id = id
        self.initialURLString = initialURLString
        self.navigationState = WebNavigationState(canGoBack: false, canGoForward: false, title: "", url: initialURLString)
        self.lastAccessedAt = Date()
        self.lastVisibleAt = nil
        self.scrollX = nil
        self.scrollY = nil
        self.viewportWidth = nil
        self.viewportHeight = nil
        self.contentFingerprint = nil
        self.focusedElementHint = nil
        self.formDrafts = nil
        self.restorationStatus = .live
        self.localFileReadAccessPath = nil
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
        self.lastAccessedAt = snapshot.lastAccessedAt
        self.lastVisibleAt = snapshot.lastVisibleAt
        self.scrollX = snapshot.scrollX
        self.scrollY = snapshot.scrollY
        self.viewportWidth = snapshot.viewportWidth
        self.viewportHeight = snapshot.viewportHeight
        self.contentFingerprint = snapshot.contentFingerprint
        self.focusedElementHint = snapshot.focusedElementHint
        self.formDrafts = snapshot.formDrafts
        self.restorationStatus = snapshot.restorationStatus
        self.localFileReadAccessPath = snapshot.localFileReadAccessPath
    }

    var snapshot: BrowserTabSnapshot {
        BrowserTabSnapshot(
            id: id,
            initialURLString: initialURLString,
            title: navigationState.title,
            currentURLString: displayURL,
            isLoading: navigationState.isLoading,
            canGoBack: navigationState.canGoBack,
            canGoForward: navigationState.canGoForward,
            lastAccessedAt: lastAccessedAt,
            lastVisibleAt: lastVisibleAt,
            scrollX: scrollX,
            scrollY: scrollY,
            viewportWidth: viewportWidth,
            viewportHeight: viewportHeight,
            contentFingerprint: contentFingerprint,
            focusedElementHint: focusedElementHint,
            formDrafts: formDrafts,
            restorationStatus: restorationStatus,
            localFileReadAccessPath: localFileReadAccessPath
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

enum BrowserEditableFieldEvent: String, Decodable, Sendable {
    case focused
    case moved
    case dismissed
}

struct BrowserEditableFieldPayload: Decodable, Sendable {
    var event: BrowserEditableFieldEvent
    var pageURL: String
    var pageTitle: String
    var token: String
    var tag: String
    var type: String
    var role: String
    var name: String
    var label: String
    var placeholder: String
    var ariaLabel: String
    var autocomplete: String
    var maxLength: Int
    var currentValue: String
    var selectedText: String
    var nearbyText: String
    var formTitle: String
    var sectionTitle: String
    var rect: BrowserSelectionRect
    var sensitive: Bool
    var sensitiveReason: String
}

enum BrowserFormFieldSemantic: String, Sendable {
    case comment
    case message
    case title
    case description
    case search
    case profile
    case generic

    var displayName: String {
        switch self {
        case .comment: "评论或回复"
        case .message: "消息或邮件"
        case .title: "标题"
        case .description: "描述"
        case .search: "搜索"
        case .profile: "资料字段"
        case .generic: "文本输入"
        }
    }
}

struct BrowserFormQuickTask: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var systemImage: String
    var prompt: String
}

struct BrowserFormCandidate: Identifiable, Equatable, Sendable {
    var id = UUID()
    var text: String
    var label: String
}

struct BrowserFormAssistantMessage: Identifiable, Equatable, Sendable {
    enum Role: Sendable { case user, assistant }
    var id = UUID()
    var role: Role
    var text: String
}

enum BrowserFormAssistantTone: String, CaseIterable, Identifiable, Sendable {
    case natural = "自然"
    case friendly = "友好"
    case formal = "正式"
    case concise = "直接"
    var id: String { rawValue }
}

enum BrowserFormAssistantLength: String, CaseIterable, Identifiable, Sendable {
    case short = "简短"
    case medium = "适中"
    case detailed = "详细"
    var id: String { rawValue }
}

enum BrowserFormAssistantLanguage: String, CaseIterable, Identifiable, Sendable {
    case automatic = "自动"
    case chinese = "中文"
    case english = "英文"
    var id: String { rawValue }
}

struct BrowserFormAssistantState: Sendable {
    var tabID: UUID
    var field: BrowserEditableFieldPayload
    var semantic: BrowserFormFieldSemantic
    var quickTasks: [BrowserFormQuickTask]
    var candidates: [BrowserFormCandidate] = []
    var messages: [BrowserFormAssistantMessage] = []
    var isGenerating = false
    var errorMessage: String?
    var tone: BrowserFormAssistantTone = .natural
    var length: BrowserFormAssistantLength = .medium
    var language: BrowserFormAssistantLanguage = .automatic
}

struct BrowserFormInsertionReceipt: Decodable, Sendable {
    var ok: Bool
    var reason: String?
    var previousValue: String?
    var insertedValue: String?
    var token: String?
}

enum BrowserFormAssistantClassifier {
    static func semantic(for field: BrowserEditableFieldPayload) -> BrowserFormFieldSemantic {
        let text = [field.label, field.placeholder, field.ariaLabel, field.name, field.formTitle, field.sectionTitle]
            .joined(separator: " ").lowercased()
        if field.type == "search" || contains(text, ["search", "搜索", "查找"]) { return .search }
        if contains(text, ["comment", "reply", "评论", "回复", "评价"]) { return .comment }
        if contains(text, ["message", "email", "邮件", "消息", "私信"]) { return .message }
        if contains(text, ["title", "subject", "标题", "主题"]) { return .title }
        if contains(text, ["description", "summary", "bio", "描述", "简介", "说明", "内容"]) { return .description }
        if contains(text, ["name", "company", "job", "姓名", "公司", "职位", "资料"]) { return .profile }
        return .generic
    }

    static func quickTasks(for semantic: BrowserFormFieldSemantic, hasText: Bool) -> [BrowserFormQuickTask] {
        let polish = BrowserFormQuickTask(id: "polish", title: "润色", systemImage: "wand.and.stars", prompt: "润色当前内容，保留原意并让表达更自然。")
        switch semantic {
        case .comment:
            return [
                .init(id: "reply", title: "礼貌回复", systemImage: "bubble.left.and.bubble.right", prompt: "生成一条礼貌、真诚且有针对性的回复。"),
                .init(id: "brief", title: "简洁回应", systemImage: "text.alignleft", prompt: "生成一条简短、自然的回应。"),
                hasText ? polish : .init(id: "view", title: "补充观点", systemImage: "plus.bubble", prompt: "结合上下文补充一个有价值的观点。")
            ]
        case .message:
            return [
                .init(id: "formal", title: "正式回复", systemImage: "envelope", prompt: "生成一条清晰、正式的回复。"),
                .init(id: "ack", title: "确认收到", systemImage: "checkmark.message", prompt: "生成一条确认收到并说明下一步的回复。"),
                hasText ? polish : .init(id: "question", title: "提出问题", systemImage: "questionmark.bubble", prompt: "生成一个清晰、礼貌的追问。")
            ]
        case .title:
            if !hasText {
                return [
                    .init(id: "titles", title: "生成标题", systemImage: "textformat", prompt: "根据字段附近的内容生成三个明确、有信息量的标题候选。"),
                    .init(id: "highlight", title: "突出重点", systemImage: "scope", prompt: "根据页面上下文生成三个突出核心价值的标题，不要虚构信息。"),
                    .init(id: "styles", title: "多种风格", systemImage: "textformat.alt", prompt: "根据页面上下文分别生成直接、场景化和价值导向的标题。")
                ]
            }
            return [
                .init(id: "titles", title: "生成标题", systemImage: "textformat", prompt: "生成三个明确、有信息量的标题候选。"),
                .init(id: "shorten", title: "缩短标题", systemImage: "arrow.left.and.right.text.vertical", prompt: "缩短当前标题，同时保留关键信息。"),
                .init(id: "clarify", title: "更明确", systemImage: "scope", prompt: "改写标题，使表达更具体明确。")
            ]
        case .description:
            return [
                .init(id: "organize", title: "整理描述", systemImage: "list.bullet.rectangle", prompt: "把已有信息整理成完整、易读的描述。"),
                .init(id: "keypoints", title: "提炼重点", systemImage: "text.badge.checkmark", prompt: "提炼关键信息并生成精炼描述。"),
                hasText ? polish : .init(id: "expand", title: "帮助起草", systemImage: "square.and.pencil", prompt: "根据页面和字段上下文起草描述；缺少事实时不要猜测。")
            ]
        case .search:
            return [
                .init(id: "query", title: "优化关键词", systemImage: "magnifyingglass", prompt: "将当前需求整理成更有效的搜索关键词。"),
                .init(id: "precise", title: "精确搜索", systemImage: "scope", prompt: "生成更精确、更聚焦的搜索词。")
            ]
        case .profile:
            return [
                .init(id: "format", title: "整理格式", systemImage: "textformat", prompt: "仅根据用户已经提供的内容整理格式，不猜测个人信息。"),
                polish
            ]
        case .generic:
            return [
                .init(id: "draft", title: "帮助填写", systemImage: "square.and.pencil", prompt: "根据字段和页面上下文起草合适内容；缺少事实时明确保留待填写项。"),
                polish,
                .init(id: "shorten", title: "精简", systemImage: "text.alignleft", prompt: "精简当前内容，保留必要信息。")
            ]
        }
    }

    private static func contains(_ text: String, _ terms: [String]) -> Bool {
        terms.contains { text.contains($0) }
    }
}

enum BrowserFormAssistantPromptBuilder {
    static func prompt(
        state: BrowserFormAssistantState,
        request: String
    ) -> String {
        let field = state.field
        let host = URL(string: field.pageURL)?.host ?? ""
        let current = String(field.currentValue.prefix(2_000))
        let nearby = String(field.nearbyText.prefix(1_500))
        let history = state.messages.suffix(6).map {
            "\($0.role == .user ? "用户" : "助手")：\(String($0.text.prefix(600)))"
        }.joined(separator: "\n")
        let candidates = state.candidates.enumerated().map { index, candidate in
            "候选 \(index + 1)（\(candidate.label)）：\(String(candidate.text.prefix(800)))"
        }.joined(separator: "\n")
        return """
        你是网页输入助手。只生成供用户审阅的文本，不执行网页操作，不虚构姓名、联系方式、地址、经历或其他事实。
        请返回严格 JSON，不要使用 Markdown：{"candidates":[{"label":"自然","text":"候选内容"}]}
        返回 3 个有实质差异的候选；每个候选必须适合直接放入当前字段。

        页面标题：\(String(field.pageTitle.prefix(300)))
        网站：\(host)
        字段语义：\(state.semantic.displayName)
        字段标签：\(String(field.label.prefix(300)))
        占位提示：\(String(field.placeholder.prefix(300)))
        表单标题：\(String(field.formTitle.prefix(300)))
        区块标题：\(String(field.sectionTitle.prefix(300)))
        附近文本：\(nearby)
        当前内容：\(current)
        语气：\(state.tone.rawValue)
        长度：\(state.length.rawValue)
        语言：\(state.language.rawValue)
        最近对话：
        \(history)
        当前候选：
        \(candidates)

        用户要求：\(request)
        """
    }
}

enum BrowserFormCandidateParser {
    private struct Envelope: Decodable {
        struct Item: Decodable { var label: String; var text: String }
        var candidates: [Item]
    }

    static func parse(_ response: String) -> [BrowserFormCandidate] {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let json: String
        if trimmed.hasPrefix("```") {
            let lines = trimmed.components(separatedBy: .newlines)
            json = lines.dropFirst().dropLast().joined(separator: "\n")
        } else {
            json = trimmed
        }
        if let data = json.data(using: .utf8),
           let envelope = try? JSONDecoder().decode(Envelope.self, from: data) {
            return envelope.candidates.prefix(3).compactMap { item in
                let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                let label = item.label.trimmingCharacters(in: .whitespacesAndNewlines)
                return BrowserFormCandidate(text: text, label: label.isEmpty ? "候选" : label)
            }
        }
        return trimmed.isEmpty ? [] : [BrowserFormCandidate(text: trimmed, label: "候选")]
    }
}
