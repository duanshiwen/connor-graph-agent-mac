import Foundation
import CryptoKit
import Testing
import ConnorGraphCore
@testable import ConnorGraphAppSupport

@Suite("新版印象笔记 .notes 流式导入适配器")
struct NotesNoteImportAdapterTests {
    @Test("解析 .notes 并完整转换 ENML 块元素（标题/列表/表格/代码/待办/媒体/加密）")
    func streamsNotesAndConvertsAllENMLBlocks() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let imageData = Data("mindmap-png-bytes".utf8)
        let videoData = Data("demo-mp4-bytes".utf8)
        let imageHash = md5Hex(imageData)
        let videoHash = md5Hex(videoData)

        let notes = """
        <?xml version="1.0" encoding="UTF-8"?><en-export><note><title>全元素示例</title><content><![CDATA[<en-note>
        <h1>一级标题</h1>
        <h2>二级标题</h2>
        <div>Hello &amp; world &lt;tag&gt;，实体已解码。</div>
        <div>支持 <b>加粗</b>、<i>斜体</i>、<u>下划线</u>、<strike>删除线</strike>、<code>inline code</code> 与 <a href="https://example.com/a">链接</a>。</div>
        <ul><li>一级项目<ul><li>嵌套二级项目</li></ul></li><li>一级项目二</li></ul>
        <ol><li>第一项</li><li>第二项</li></ol>
        <table><tr><th>名称</th><th>说明</th></tr><tr><td>功能</td><td>导入导出</td></tr><tr><td>格式</td><td>.notes</td></tr></table>
        <div><en-todo checked="true"/>已完成事项</div>
        <div><en-todo/>待办事项</div>
        <pre>func hello() {
            print("code")
        }</pre>
        <blockquote><div>引用的内容</div></blockquote>
        <hr/>
        <div><en-media hash="\(imageHash)" type="image/png"/></div>
        <div><en-media hash="\(videoHash)" type="video/mp4"/></div>
        <div><en-crypt hint="生日">base64:ciphertext</en-crypt></div>
        </en-note>]]></content><created>20260818T120000Z</created><updated>20260818T130000Z</updated><tag>测试</tag><tag>富文本</tag><guid>notes-guid-1</guid><resource><data encoding="base64">\(imageData.base64EncodedString())</data><mime>image/png</mime><resource-attributes><file-name>diagram.png</file-name></resource-attributes></resource><resource><data encoding="base64">\(videoData.base64EncodedString())</data><mime>video/mp4</mime><resource-attributes><file-name>demo.mp4</file-name></resource-attributes></resource></note><note><title>第二条</title><content><![CDATA[<en-note><div>简单正文</div></en-note>]]></content><guid>notes-guid-2</guid></note></en-export>
        """

        let file = root.appendingPathComponent("笔记本.notes")
        try notes.write(to: file, atomically: true, encoding: .utf8)

        var imported: [ImportedNote] = []
        for try await note in NotesNoteImportAdapter().scan(.init(sourceID: "n", sourceURL: file, kind: .yinxiangNotes, options: .init())) {
            imported.append(note)
        }

        #expect(imported.count == 2)
        let first = imported[0]
        #expect(first.sourceKind == .yinxiangNotes)
        #expect(first.title == "全元素示例")
        #expect(first.externalID == "notes-guid-1")
        #expect(first.tags == ["测试", "富文本"])
        #expect(first.createdAt != nil)
        #expect(first.updatedAt != nil)

        let markdown = first.markdownContent
        // 标题
        #expect(markdown.contains("# 一级标题"))
        #expect(markdown.contains("## 二级标题"))
        // 实体解码与行内样式
        #expect(markdown.contains("Hello & world <tag>，实体已解码。"))
        #expect(markdown.contains("**加粗**"))
        #expect(markdown.contains("*斜体*"))
        #expect(markdown.contains("~~删除线~~"))
        #expect(markdown.contains("`inline code`"))
        #expect(markdown.contains("[链接](https://example.com/a)"))
        // 嵌套列表
        #expect(markdown.contains("- 一级项目"))
        #expect(markdown.contains("  - 嵌套二级项目"))
        #expect(markdown.contains("1. 第一项"))
        // GFM 表格
        #expect(markdown.contains("| 名称 | 说明 |"))
        #expect(markdown.contains("| --- | --- |"))
        #expect(markdown.contains("| 功能 | 导入导出 |"))
        // 待办
        #expect(markdown.contains("- [x] 已完成事项"))
        #expect(markdown.contains("- [ ] 待办事项"))
        // 代码块
        #expect(markdown.contains("```"))
        #expect(markdown.contains("func hello()"))
        // 引用与分隔线
        #expect(markdown.contains("> 引用的内容"))
        #expect(markdown.contains("---"))
        // 图片内嵌与视频附件链接
        #expect(markdown.contains("![diagram.png](attachment:\(imageHash))"))
        #expect(markdown.contains("[demo.mp4](attachment:\(videoHash))"))
        // 加密内容
        #expect(markdown.contains("🔒 加密内容"))
        #expect(markdown.contains("生日"))
        // 第二条
        #expect(imported[1].title == "第二条")
        #expect(imported[1].markdownContent.contains("简单正文"))

        #expect(first.attachments.count == 2)
        #expect(first.attachments[0].displayName == "diagram.png")
        #expect(first.attachments[0].mimeType == "image/png")
        #expect(first.attachments[0].metadata["enex_md5"] == imageHash)
        #expect(first.attachments[1].displayName == "demo.mp4")
        #expect(first.attachments[1].mimeType == "video/mp4")
        #expect(first.attachments[1].metadata["enex_md5"] == videoHash)
    }

    @Test("缺资源的 en-media 输出可读占位符而不是丢内容")
    func missingMediaFallsBackToPlaceholder() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let notes = """
        <?xml version="1.0" encoding="UTF-8"?><en-export><note><title>缺资源</title><content><![CDATA[<en-note><div>正文<en-media hash="deadbeefdeadbeefdeadbeefdeadbeef" type="image/png"/></div></en-note>]]></content><guid>g-3</guid></note></en-export>
        """
        let file = root.appendingPathComponent("Missing.notes")
        try notes.write(to: file, atomically: true, encoding: .utf8)
        var imported: [ImportedNote] = []
        for try await note in NotesNoteImportAdapter().scan(.init(sourceID: "n", sourceURL: file, kind: .yinxiangNotes, options: .init())) {
            imported.append(note)
        }
        #expect(imported.count == 1)
        #expect(imported[0].markdownContent.contains("媒体附件"))
        #expect(imported[0].markdownContent.contains("deadbeef"))
        #expect(imported[0].attachments.isEmpty)
    }

    private func md5Hex(_ data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
