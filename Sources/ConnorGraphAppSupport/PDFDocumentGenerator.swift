import Foundation
import CoreGraphics
import CoreText

public enum PDFDocumentGeneratorError: Error, Sendable, Equatable, LocalizedError {
    case emptyContent
    case renderFailed(String)

    public var errorDescription: String? {
        switch self {
        case .emptyContent:
            return "PDF 内容不能为空。"
        case .renderFailed(let detail):
            return "PDF 渲染失败：\(detail)"
        }
    }
}

/// 把「标题 + Markdown 风格文本」渲染为 PDF（A4，分页，支持中文）。
///
/// 支持的内容格式：
/// - `#` / `##` / `###` 标题（加粗 + 放大）
/// - `-` / `*` / `•` 无序列表
/// - `1.` 等有序列表
/// - 其余为普通段落（空行分段）
///
/// 使用 CoreText 的 CTFramesetter 分页布局，字体优先 PingFang SC（中文），
/// 缺失时回退系统字体。渲染为字节流返回，由调用方落盘/导入会话。
public enum PDFDocumentGenerator {
    public static let pageWidth: CGFloat = 595.2   // A4 宽（pt）
    public static let pageHeight: CGFloat = 841.8  // A4 高（pt）

    private static let margin: CGFloat = 56
    private static let footerInset: CGFloat = 30
    private static let titleFontSize: CGFloat = 22
    private static let headingFontSize: CGFloat = 15
    private static let bodyFontSize: CGFloat = 11
    private static let lineSpacing: CGFloat = 4
    private static let paragraphSpacing: CGFloat = 7
    private static let maxPageCount = 1_000

    // MARK: - 渲染入口

    public static func render(title: String?, content: String) throws -> Data {
        let body = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw PDFDocumentGeneratorError.emptyContent }

        let attributed = makeAttributedString(title: title?.nilIfEmpty, body: body)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)

        let output = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let consumer = CGDataConsumer(data: output),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw PDFDocumentGeneratorError.renderFailed("无法创建 PDF 上下文")
        }

        let textRect = CGRect(
            x: margin,
            y: margin,
            width: pageWidth - margin * 2,
            height: pageHeight - margin - footerInset
        )
        var location = 0
        var page = 1
        while true {
            let path = CGPath(rect: textRect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
            let visible = CTFrameGetVisibleStringRange(frame)
            guard visible.length > 0 else { break }

            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(mediaBox)
            CTFrameDraw(frame, context)
            drawFooter(in: context, mediaBox: mediaBox, pageNumber: page)
            context.endPDFPage()

            location += visible.length
            page += 1
            if page > maxPageCount { break }
        }
        context.closePDF()
        return output as Data
    }

    /// 解析已生成 PDF 的页数（用于工具结果回报）。
    public static func pageCount(of data: Data) -> Int {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider) else { return 0 }
        return document.numberOfPages
    }

    // MARK: - 排版

    private static func makeAttributedString(title: String?, body: String) -> NSAttributedString {
        let output = NSMutableAttributedString()
        if let title, !title.isEmpty {
            output.append(NSAttributedString(
                string: title + "\n",
                attributes: attributes(fontName: "PingFangSC-Semibold", size: titleFontSize, color: 0x111111)
            ))
            output.append(NSAttributedString(
                string: "\n",
                attributes: attributes(fontName: "PingFangSC-Regular", size: bodyFontSize, color: 0x333333, paragraphSpacing: 10)
            ))
        }

        var isFirst = true
        for rawLine in body.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                if !isFirst {
                    output.append(NSAttributedString(
                        string: "\n",
                        attributes: attributes(fontName: "PingFangSC-Regular", size: bodyFontSize, color: 0x333333)
                    ))
                }
                continue
            }
            isFirst = false
            appendLine(line, to: output)
        }
        return output
    }

    private static func appendLine(_ line: String, to output: NSMutableAttributedString) {
        if line.hasPrefix("### ") {
            output.append(NSAttributedString(
                string: String(line.dropFirst(4)) + "\n",
                attributes: attributes(fontName: "PingFangSC-Semibold", size: headingFontSize, color: 0x1F1F1F, paragraphSpacing: 4)
            ))
            return
        }
        if line.hasPrefix("## ") {
            output.append(NSAttributedString(
                string: String(line.dropFirst(3)) + "\n",
                attributes: attributes(fontName: "PingFangSC-Semibold", size: headingFontSize + 1, color: 0x1F1F1F, paragraphSpacing: 4)
            ))
            return
        }
        if line.hasPrefix("# ") {
            output.append(NSAttributedString(
                string: String(line.dropFirst(2)) + "\n",
                attributes: attributes(fontName: "PingFangSC-Semibold", size: headingFontSize + 2, color: 0x1F1F1F, paragraphSpacing: 4)
            ))
            return
        }
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
            let bullet = "•  " + String(line.dropFirst(2))
            output.append(NSAttributedString(
                string: bullet + "\n",
                attributes: attributes(fontName: "PingFangSC-Regular", size: bodyFontSize, color: 0x333333, paragraphSpacing: 2)
            ))
            return
        }
        if let ordered = orderedListMarker(line) {
            output.append(NSAttributedString(
                string: ordered + "\n",
                attributes: attributes(fontName: "PingFangSC-Regular", size: bodyFontSize, color: 0x333333, paragraphSpacing: 2)
            ))
            return
        }
        output.append(NSAttributedString(
            string: line + "\n",
            attributes: attributes(fontName: "PingFangSC-Regular", size: bodyFontSize, color: 0x333333)
        ))
    }

    private static func orderedListMarker(_ line: String) -> String? {
        let pattern = #"^(\d+)[.、)]\s*(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = line as NSString
        guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let number = ns.substring(with: match.range(at: 1))
        let rest = ns.substring(with: match.range(at: 2))
        return "\(number).  \(rest)"
    }

    private static func attributes(
        fontName: String,
        size: CGFloat,
        color: Int,
        paragraphSpacing: CGFloat = PDFDocumentGenerator.paragraphSpacing
    ) -> [NSAttributedString.Key: Any] {
        let font = CTFontCreateWithName(fontName as CFString, size, nil)
        var lineSpacingValue = lineSpacing
        var paragraphSpacingValue = paragraphSpacing
        var lineBreakMode = CTLineBreakMode.byWordWrapping
        var settings: [CTParagraphStyleSetting] = [
            CTParagraphStyleSetting(spec: .lineSpacingAdjustment, valueSize: MemoryLayout<CGFloat>.size, value: &lineSpacingValue),
            CTParagraphStyleSetting(spec: .paragraphSpacing, valueSize: MemoryLayout<CGFloat>.size, value: &paragraphSpacingValue),
            CTParagraphStyleSetting(spec: .lineBreakMode, valueSize: MemoryLayout<CTLineBreakMode>.size, value: &lineBreakMode)
        ]
        let paragraph = CTParagraphStyleCreate(&settings, settings.count)
        return [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: CGFloat((color >> 16) & 0xFF) / 255,
                                                                                      green: CGFloat((color >> 8) & 0xFF) / 255,
                                                                                      blue: CGFloat(color & 0xFF) / 255,
                                                                                      alpha: 1),
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph
        ]
    }

    private static func drawFooter(in context: CGContext, mediaBox: CGRect, pageNumber: Int) {
        let footer = "— \(pageNumber) —"
        let font = CTFontCreateWithName("PingFangSC-Regular" as CFString, 9, nil)
        let attributed = NSAttributedString(
            string: footer,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.55, alpha: 1)
            ]
        )
        let line = CTLineCreateWithAttributedString(attributed)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let x = mediaBox.midX - width / 2
        let y = margin * 0.45
        context.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, context)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
