import Foundation
import ConnorGraphCore

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
