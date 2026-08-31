import Foundation
import SwiftSoup

/// 基于 SwiftSoup 的正文定位器。
/// 目标：在“正则转 markdown”之前先找到正文容器，让导航/侧栏/广告等噪声
/// 不再进入字符预算，解决长文被噪声截断的问题。
/// 策略：优先语义容器（article/main/[role=main]），否则按“文本密度 - 链接密度”
/// 对块级候选打分，取得分最高的容器；非文章页或解析失败时回退整页去噪。
enum NativeWebReadabilityExtractor {

    private static let noiseSelector =
        "script, style, noscript, iframe, nav, header, footer, aside, form, button, select, option, svg, canvas, " +
        "figure, figcaption, .advertisement, .ad, .ads, .banner, .cookie, .modal, .popup, .share, .social, " +
        ".related, .recommend, .sidebar, .menu, .breadcrumb, .pagination, .comment, .comments, .author-box"

    private static let semanticSelector = "article, main, [role=main], [itemprop=articleBody]"

    /// 定位正文 HTML 片段。任何异常都回退到原 HTML（由上层正则转换器继续处理）。
    static func articleHTML(from html: String) -> String {
        do {
            let doc: Document = try SwiftSoup.parse(html)
            try doc.select(noiseSelector).remove()
            if let candidate = try selectArticleCandidate(doc) {
                return try candidate.html()
            }
            if let body = try doc.body() {
                return try body.html()
            }
            return try doc.html()
        } catch {
            return html
        }
    }

    private static func selectArticleCandidate(_ doc: Document) throws -> Element? {
        if let semantic = try doc.select(semanticSelector).first() {
            return semantic
        }

        let candidates = try doc.select("div, section, td")
        var best: Element?
        var bestScore: Double = 0
        for element in candidates {
            let text = try element.text()
            let textLength = Double(text.count)
            if textLength < 40 { continue }
            let ownLength = element.ownText().count
            // 纯链接墙（导航/目录）：自身文本极少的容器跳过
            if ownLength > 0, Double(ownLength) > textLength * 0.5 { continue }
            let linkTextLength = Double(try element.select("a").map { try $0.text() }.reduce("", +).count)
            let density = textLength > 0 ? (textLength - linkTextLength) / textLength : 0
            let score = textLength * density
            if score > bestScore {
                bestScore = score
                best = element
            }
        }
        // 阈值：正文至少要一定规模的连续文本，避免误选导航条
        if let candidate = best, bestScore >= 120 {
            return candidate
        }
        return nil
    }
}
