import Foundation
import Testing
import ConnorGraphAppSupport

@Suite("PDF document generator")
struct PDFDocumentGeneratorTests {
    @Test("Renders a short Chinese PDF with title and headings")
    func rendersShortPDF() throws {
        let content = """
        # 项目计划

        ## 目标

        为康纳同学生成一份可分享的 PDF 文档，支持中文、标题与列表。

        - 支持中文字体
        - 支持分页
        - 支持列表

        1. 渲染内容
        2. 落盘附件
        """
        let data = try PDFDocumentGenerator.render(title: "康纳同学报告", content: content)

        #expect(data.count > 1_000)
        #expect(String(data: data.prefix(5), encoding: .ascii) == "%PDF-")
        #expect(PDFDocumentGenerator.pageCount(of: data) == 1)
    }

    @Test("Paginates long content into multiple pages")
    func paginatesLongContent() throws {
        let paragraph = String(repeating: "这是一段用于撑满页面的中文内容，包含足够多的文字以确保换行与分页正常工作。", count: 40)
        let content = (1...12).map { "## 章节 \($0)\n\(paragraph)\n\n- 要点 \($0)\n- 补充说明" }.joined(separator: "\n\n")
        let data = try PDFDocumentGenerator.render(title: "长文档", content: content)

        #expect(PDFDocumentGenerator.pageCount(of: data) > 1)
    }

    @Test("Rejects empty content")
    func rejectsEmptyContent() throws {
        #expect(throws: PDFDocumentGeneratorError.emptyContent) {
            _ = try PDFDocumentGenerator.render(title: nil, content: "   \n ")
        }
    }
}
