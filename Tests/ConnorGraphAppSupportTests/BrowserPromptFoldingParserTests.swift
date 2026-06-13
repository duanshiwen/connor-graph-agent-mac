import Testing
import ConnorGraphAppSupport

@Suite("Browser Prompt Folding Parser Tests")
struct BrowserPromptFoldingParserTests {
    @Test func parsesWebPageBodyFenceForCollapsedDisplay() throws {
        let prompt = """
        请基于下面网页上下文回答我的问题。

        网页上下文：
        - 标题：法国 - 维基百科，自由的百科全书
        - URL：https://zh.wikipedia.org/wiki/%E6%B3%95%E5%9B%BD

        选中文本：
        ```text
        海外领土则气候多样
        ```

        网页正文：
        ```text
        开关目录
        法国 [编辑]
        322种语言
        ```

        我的问题：
        海洋性气候是什么
        """

        let parts = try #require(BrowserPromptFoldingParser().parse(prompt))

        #expect(parts.leadingMarkdown.contains("网页上下文"))
        #expect(parts.leadingMarkdown.contains("选中文本"))
        #expect(parts.webPageBody.contains("开关目录"))
        #expect(parts.webPageBody.contains("322种语言"))
        #expect(parts.trailingMarkdown.contains("我的问题"))
        #expect(parts.trailingMarkdown.contains("海洋性气候是什么"))
    }

    @Test func ignoresPromptsWithoutWebPageBodyFence() {
        let parts = BrowserPromptFoldingParser().parse("普通问题\n\n网页正文：没有代码块")

        #expect(parts == nil)
    }
}
