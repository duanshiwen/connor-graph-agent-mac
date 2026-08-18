import Foundation
import Testing
import ConnorGraphCore
@testable import ConnorGraphAppSupport

@Suite("ENML → Markdown 转换与 App 解析器兼容性")
struct ENMLMarkdownConverterTests {
    @Test("真实导出带 XML 声明头时块结构不被吞掉")
    func xmlPrologDoesNotSwallowBlocks() {
        let enml = """
        <?xml version="1.0" encoding="UTF-8"?><!DOCTYPE en-note SYSTEM "http://xml.evernote.com/pub/enml2.dtd"><en-note><div>第一段</div><div>第二段</div><h1>标题</h1></en-note>
        """
        let markdown = ENMLMarkdownConverter.convert(enml)
        #expect(markdown.contains("第一段\n\n第二段"))
        #expect(markdown.contains("# 标题"))
        #expect(!markdown.contains("?xml"))
    }

    @Test("monospace div 多行转代码围栏，单行转行内代码")
    func monospaceDivBecomesCodeFence() {
        let enml = """
        <en-note><div style="font-family: Monaco, Menlo, Consolas, monospace;"><div>let a = 1</div><div>let b = 2</div></div><div style="font-family: monospace;">print(1)</div></en-note>
        """
        let markdown = ENMLMarkdownConverter.convert(enml)
        #expect(markdown.contains("```\nlet a = 1\nlet b = 2\n```"))
        #expect(markdown.contains("`print(1)`"))
    }

    @Test("li 内 en-todo 不产生双重列表标记")
    func todoInsideListItemSingleMarker() {
        let enml = "<en-note><ul><li><en-todo checked=\"true\"/>子任务</li></ul></en-note>"
        let markdown = ENMLMarkdownConverter.convert(enml)
        #expect(markdown.contains("- [x] 子任务"))
        #expect(!markdown.contains("- - [x]"))
    }

    @Test("表格单元格转义竖线可被 App 解析器正确还原")
    func escapedPipeInTableCellRoundTrips() {
        let enml = """
        <en-note><table><tr><th>A|B</th><th>C</th></tr><tr><td>x|y</td><td>z</td></tr></table></en-note>
        """
        let markdown = ENMLMarkdownConverter.convert(enml)
        let blocks = AgentMarkdownBlockParser().parse(markdown)
        guard case .table(let table)? = blocks.first else {
            Issue.record("Expected table block, got \(blocks)")
            return
        }
        #expect(table.headers == ["A|B", "C"])
        #expect(table.rows == [["x|y", "z"]])
    }

    @Test("全块元素转换后可被 App 解析器识别为对应块类型")
    func allBlockKindsParseInAppRenderer() {
        let enml = """
        <en-note><h1>标题</h1><div>段落 <b>加粗</b></div><ul><li>无序</li></ul><ol><li>有序</li></ol><div><en-todo/>待办</div><blockquote><div>引用</div></blockquote><pre>code()</pre><table><tr><th>H</th></tr><tr><td>V</td></tr></table><div><en-media hash="abcdef1234567890abcdef1234567890" type="image/png"/></div><hr/></en-note>
        """
        let markdown = ENMLMarkdownConverter.convert(enml) { media in
            "![img.png](attachment:\(media.hash))"
        }
        let blocks = AgentMarkdownBlockParser().parse(markdown)
        func has(_ predicate: (AgentMarkdownBlock) -> Bool) -> Bool {
            blocks.contains(where: predicate)
        }
        #expect(has { if case .heading = $0 { true } else { false } })
        #expect(has { if case .paragraph = $0 { true } else { false } })
        #expect(has { if case .unorderedItem = $0 { true } else { false } })
        #expect(has { if case .orderedItem = $0 { true } else { false } })
        #expect(has { if case .taskItem = $0 { true } else { false } })
        #expect(has { if case .quote = $0 { true } else { false } })
        #expect(has { if case .code = $0 { true } else { false } })
        #expect(has { if case .table = $0 { true } else { false } })
        #expect(has { if case .image = $0 { true } else { false } })
        #expect(has { if case .horizontalRule = $0 { true } else { false } })
    }
}
