import CoreGraphics
import Foundation
import ConnorGraphCore

public struct BrowserWorkspaceSessionBinding: Equatable, Sendable {
    public private(set) var boundSessionID: String?

    public init(boundSessionID: String? = nil) {
        self.boundSessionID = boundSessionID
    }

    public mutating func bindBrowserWorkspace(to sessionID: String?) {
        let trimmed = sessionID?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return }
        boundSessionID = trimmed
    }

    public func sessionIDForReturningFromBrowser(currentSelectedSessionID: String?) -> String? {
        boundSessionID ?? currentSelectedSessionID
    }
}

public struct BrowserPromptFoldingParts: Equatable, Sendable {
    public var leadingMarkdown: String
    public var webPageBody: String
    public var trailingMarkdown: String

    public init(leadingMarkdown: String, webPageBody: String, trailingMarkdown: String) {
        self.leadingMarkdown = leadingMarkdown
        self.webPageBody = webPageBody
        self.trailingMarkdown = trailingMarkdown
    }
}

public struct BrowserPromptFoldingParser: Sendable {
    public init() {}

    public func parse(_ markdown: String) -> BrowserPromptFoldingParts? {
        guard let headingRange = markdown.range(of: "网页正文：") else { return nil }
        let afterHeading = markdown[headingRange.upperBound...]
        guard let fenceStart = afterHeading.range(of: "```") else { return nil }
        let afterFenceStart = afterHeading[fenceStart.upperBound...]
        let bodyStart: String.Index
        if let newline = afterFenceStart.firstIndex(of: "\n") {
            bodyStart = markdown.index(after: newline)
        } else {
            bodyStart = fenceStart.upperBound
        }
        guard let fenceEnd = markdown[bodyStart...].range(of: "```") else { return nil }

        let leading = String(markdown[..<headingRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let body = String(markdown[bodyStart..<fenceEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let trailing = String(markdown[fenceEnd.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }
        return BrowserPromptFoldingParts(leadingMarkdown: leading, webPageBody: body, trailingMarkdown: trailing)
    }
}

public enum BrowserPopoverDismissalPolicy: Equatable, Sendable {
    case escape
    case explicitClose

    public var shouldPreserveDraftQuestion: Bool {
        switch self {
        case .escape: true
        case .explicitClose: false
        }
    }
}

public enum BrowserKeyboardShortcut: Equatable, Sendable {
    case closeSelectionPopover
    case closeSelectedTab
}

public struct BrowserKeyboardShortcutResolver: Sendable {
    public init() {}

    public func shortcut(
        character: String? = nil,
        isEscape: Bool = false,
        isCommandDown: Bool = false,
        isShiftDown: Bool = false,
        isControlDown: Bool = false,
        isOptionDown: Bool = false,
        hasSelectionPopover: Bool = false
    ) -> BrowserKeyboardShortcut? {
        if isEscape, hasSelectionPopover {
            return .closeSelectionPopover
        }

        guard isCommandDown, !isShiftDown, !isControlDown, !isOptionDown else { return nil }
        if character?.lowercased() == "w" {
            return .closeSelectedTab
        }
        return nil
    }
}

public struct BrowserExternalOpenPlanner: Sendable {
    public init() {}

    public func open(urlString: String, in snapshot: AppBrowserStateSnapshot) -> AppBrowserStateSnapshot {
        var planned = snapshot
        planned.updatedAt = Date()
        planned.selectionPopover = nil
        let tab = AppBrowserTabSnapshot(
            initialURLString: urlString,
            title: "",
            currentURLString: urlString,
            isLoading: false,
            canGoBack: false,
            canGoForward: false
        )
        planned.tabs.append(tab)
        planned.selectedTabID = tab.id
        return planned
    }
}

public struct BrowserTabStripLayout: Equatable, Sendable {
    public var tabWidth: Double
    public var requiresHorizontalScroll: Bool

    public init(tabWidth: Double, requiresHorizontalScroll: Bool) {
        self.tabWidth = tabWidth
        self.requiresHorizontalScroll = requiresHorizontalScroll
    }
}

public struct BrowserTabStripLayoutCalculator: Sendable {
    public var preferredTabWidth: Double
    public var minimumTabWidth: Double
    public var interTabSpacing: Double

    public init(preferredTabWidth: Double = 150, minimumTabWidth: Double = 86, interTabSpacing: Double = 4) {
        self.preferredTabWidth = preferredTabWidth
        self.minimumTabWidth = minimumTabWidth
        self.interTabSpacing = interTabSpacing
    }

    public func layout(tabCount: Int, availableWidth: Double) -> BrowserTabStripLayout {
        guard tabCount > 0 else {
            return BrowserTabStripLayout(tabWidth: preferredTabWidth, requiresHorizontalScroll: false)
        }
        let totalSpacing = interTabSpacing * Double(max(0, tabCount - 1))
        let preferredTotalWidth = preferredTabWidth * Double(tabCount) + totalSpacing
        guard preferredTotalWidth > availableWidth else {
            return BrowserTabStripLayout(tabWidth: preferredTabWidth, requiresHorizontalScroll: false)
        }
        let fittedWidth = floor((availableWidth - totalSpacing) / Double(tabCount))
        let tabWidth = max(minimumTabWidth, fittedWidth)
        let minimumTotalWidth = minimumTabWidth * Double(tabCount) + totalSpacing
        return BrowserTabStripLayout(tabWidth: tabWidth, requiresHorizontalScroll: minimumTotalWidth > availableWidth)
    }
}

public enum ChatSessionWorkspaceMode: String, Codable, Equatable, Sendable {
    case conversation
    case browser
}

public struct ChatSessionWorkspaceModeStore: Equatable, Sendable {
    private var modesBySessionID: [String: ChatSessionWorkspaceMode]

    public init(modesBySessionID: [String: ChatSessionWorkspaceMode] = [:]) {
        self.modesBySessionID = modesBySessionID
    }

    public func mode(for sessionID: String?) -> ChatSessionWorkspaceMode {
        guard let key = normalizedSessionID(sessionID) else { return .conversation }
        return modesBySessionID[key] ?? .conversation
    }

    public mutating func setMode(_ mode: ChatSessionWorkspaceMode, for sessionID: String?) {
        guard let key = normalizedSessionID(sessionID) else { return }
        modesBySessionID[key] = mode
    }

    public var snapshot: [String: ChatSessionWorkspaceMode] { modesBySessionID }

    private func normalizedSessionID(_ sessionID: String?) -> String? {
        let trimmed = sessionID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

public enum BrowserSelectionPopoverPlacement: String, Equatable, Sendable {
    case below
    case above
}

public struct BrowserSelectionPopoverLayout: Equatable, Sendable {
    public var position: CGPoint
    public var width: CGFloat
    public var maxHeight: CGFloat
    public var placement: BrowserSelectionPopoverPlacement

    public init(position: CGPoint, width: CGFloat, maxHeight: CGFloat, placement: BrowserSelectionPopoverPlacement) {
        self.position = position
        self.width = width
        self.maxHeight = maxHeight
        self.placement = placement
    }

    public var frame: CGRect {
        CGRect(
            x: position.x - width / 2,
            y: position.y - maxHeight / 2,
            width: width,
            height: maxHeight
        )
    }
}

public struct BrowserSelectionPopoverLayoutCalculator: Sendable {
    public var margin: CGFloat
    public var gap: CGFloat
    public var minimumWidth: CGFloat
    public var minimumHeight: CGFloat

    public init(margin: CGFloat = 14, gap: CGFloat = 12, minimumWidth: CGFloat = 260, minimumHeight: CGFloat = 180) {
        self.margin = margin
        self.gap = gap
        self.minimumWidth = minimumWidth
        self.minimumHeight = minimumHeight
    }

    public func layout(anchorRect: AppBrowserSelectionRect, containerSize: CGSize, preferredSize: CGSize) -> BrowserSelectionPopoverLayout {
        let usableWidth = max(1, containerSize.width - margin * 2)
        let width = min(preferredSize.width, usableWidth)
        let anchor = CGRect(
            x: CGFloat(anchorRect.x),
            y: CGFloat(anchorRect.y),
            width: CGFloat(anchorRect.width),
            height: CGFloat(anchorRect.height)
        )

        let spaceBelow = max(0, containerSize.height - margin - (anchor.maxY + gap))
        let spaceAbove = max(0, anchor.minY - gap - margin)
        let placement: BrowserSelectionPopoverPlacement = if spaceBelow >= preferredSize.height || spaceBelow >= spaceAbove {
            .below
        } else {
            .above
        }
        let availableHeight = placement == .below ? spaceBelow : spaceAbove
        let boundedPreferredHeight = min(preferredSize.height, max(minimumHeight, containerSize.height - margin * 2))
        let maxHeight = min(boundedPreferredHeight, max(minimumHeight, availableHeight))

        let rawX = anchor.midX
        let halfWidth = width / 2
        let x = clamp(rawX, lower: margin + halfWidth, upper: max(margin + halfWidth, containerSize.width - margin - halfWidth))

        let rawY = switch placement {
        case .below:
            anchor.maxY + gap + maxHeight / 2
        case .above:
            anchor.minY - gap - maxHeight / 2
        }
        let halfHeight = maxHeight / 2
        let y = clamp(rawY, lower: margin + halfHeight, upper: max(margin + halfHeight, containerSize.height - margin - halfHeight))

        return BrowserSelectionPopoverLayout(position: CGPoint(x: x, y: y), width: width, maxHeight: maxHeight, placement: placement)
    }

    private func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }
}

public struct BrowserPageContext: Equatable, Sendable {
    public var url: String
    public var title: String
    public var text: String

    public init(url: String, title: String, text: String = "") {
        self.url = url
        self.title = title
        self.text = text
    }
}

public struct BrowserSelectedImageContext: Equatable, Sendable {
    public var url: String
    public var alt: String?
    public var mediaType: String?
    public var base64Data: String?

    public init(url: String, alt: String? = nil, mediaType: String? = nil, base64Data: String? = nil) {
        self.url = url
        self.alt = alt
        self.mediaType = mediaType
        self.base64Data = base64Data
    }
}

public struct BrowserSelectionContext: Equatable, Sendable {
    public var page: BrowserPageContext
    public var selectedText: String
    public var image: BrowserSelectedImageContext?

    public init(page: BrowserPageContext, selectedText: String = "", image: BrowserSelectedImageContext? = nil) {
        self.page = page
        self.selectedText = selectedText
        self.image = image
    }

    public var hasSelectionContext: Bool {
        !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || image != nil
    }

    public var hasPageContext: Bool {
        !page.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !page.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !page.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public struct BrowserLLMContextBuilder: Sendable {
    public var maxSelectedTextCharacters: Int
    public var maxPageTextCharacters: Int

    public init(maxSelectedTextCharacters: Int = 12_000, maxPageTextCharacters: Int = 30_000) {
        self.maxSelectedTextCharacters = maxSelectedTextCharacters
        self.maxPageTextCharacters = maxPageTextCharacters
    }

    public func makePrompt(selection: BrowserSelectionContext, question: String) -> String {
        """
        请基于下面网页上下文回答我的问题。

        \(makeContextMarkdown(selection: selection))

        我的问题：
        \(question.trimmingCharacters(in: .whitespacesAndNewlines))
        """
    }

    public func makeContextMarkdown(selection: BrowserSelectionContext) -> String {
        var lines: [String] = []
        lines.append("网页上下文：")
        if !selection.page.title.isEmpty { lines.append("- 标题：\(selection.page.title)") }
        if !selection.page.url.isEmpty { lines.append("- URL：\(selection.page.url)") }

        let trimmedSelectedText = selection.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSelectedText.isEmpty {
            lines.append("\n选中文本：")
            lines.append("```text")
            lines.append(Self.truncated(trimmedSelectedText, maxCharacters: maxSelectedTextCharacters))
            lines.append("```")
        }

        if let image = selection.image {
            lines.append("\n选中图片：")
            lines.append("- 图片 URL：\(image.url)")
            if let alt = image.alt?.trimmingCharacters(in: .whitespacesAndNewlines), !alt.isEmpty { lines.append("- Alt：\(alt)") }
            if let mediaType = image.mediaType, !mediaType.isEmpty { lines.append("- Media Type：\(mediaType)") }
            if image.base64Data != nil {
                lines.append("- 图片数据：已捕获 base64，占位字段可供未来 vision provider 使用。")
            } else {
                lines.append("\n注意：当前模型接口暂未启用 vision；请优先基于图片 URL、alt、页面正文和用户问题分析。")
            }
        }

        let pageText = selection.page.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !pageText.isEmpty {
            lines.append("\n网页正文：")
            lines.append("```text")
            lines.append(Self.truncated(pageText, maxCharacters: maxPageTextCharacters))
            lines.append("```")
        }

        return lines.joined(separator: "\n")
    }

    static func truncated(_ text: String, maxCharacters: Int) -> String {
        guard maxCharacters > 0, text.count > maxCharacters else { return text }
        let index = text.index(text.startIndex, offsetBy: maxCharacters)
        return String(text[..<index]) + "\n…[truncated]"
    }
}

public struct BrowserEvidenceEpisodeDraft: Equatable, Sendable {
    public var episode: GraphEpisodeV3

    public init(episode: GraphEpisodeV3) {
        self.episode = episode
    }
}

public struct BrowserGraphEvidenceBuilder: Sendable {
    public var contextBuilder: BrowserLLMContextBuilder

    public init(contextBuilder: BrowserLLMContextBuilder = BrowserLLMContextBuilder()) {
        self.contextBuilder = contextBuilder
    }

    public func makeEpisodeDraft(selection: BrowserSelectionContext, groupID: String = "default", sessionID: String? = nil, workObjectID: String? = nil) -> BrowserEvidenceEpisodeDraft {
        let name = selection.page.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallbackName(from: selection.page.url) : selection.page.title
        let episode = GraphEpisodeV3(
            id: UUID().uuidString,
            graphID: groupID,
            sourceType: .webPage,
            sourceID: selection.page.url.isEmpty ? nil : selection.page.url,
            title: name,
            content: contextBuilder.makeContextMarkdown(selection: selection),
            sourceDescription: "Embedded browser web page selection",
            sessionID: sessionID,
            workObjectID: workObjectID,
            metadata: [
                "origin": "embedded_browser",
                "pageTitle": selection.page.title,
                "hasSelectedText": selection.selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "false" : "true",
                "hasImage": selection.image == nil ? "false" : "true",
                "hasPageText": selection.page.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "false" : "true"
            ]
        )
        return BrowserEvidenceEpisodeDraft(episode: episode)
    }

    private func fallbackName(from urlString: String) -> String {
        guard let url = URL(string: urlString), let host = url.host, !host.isEmpty else {
            return urlString.isEmpty ? "Web page selection" : urlString
        }
        return host
    }
}
