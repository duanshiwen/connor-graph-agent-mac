import Testing
import Foundation
@testable import ConnorGraphAppSupport

@Suite("Agent Markdown Compiled Document Tests")
struct AgentMarkdownCompiledDocumentTests {
    @Test func compilerPreservesBlockStructureAndStableIDs() {
        let markdown = """
        # Title

        Paragraph with **bold** and `code`.

        - first
        1. second
        - [x] done
        > quoted

        ```swift
        let value = 1
        ```

        | Name | Score |
        | :--- | ----: |
        | Ada | 10 |

        ---
        """

        let document = AgentMarkdownDocumentCompiler().compile(markdown)

        #expect(document.source == markdown)
        #expect(document.blocks.count == 14)
        #expect(document.blocks.map(\.kind) == [
            .heading,
            .spacer,
            .paragraph,
            .spacer,
            .unorderedItem,
            .orderedItem,
            .taskItem,
            .quote,
            .spacer,
            .code,
            .spacer,
            .table,
            .spacer,
            .horizontalRule
        ])
        #expect(Set(document.blocks.map(\.id)).count == document.blocks.count)

        guard case .heading(level: 1, text: let heading, inline: _) = document.blocks[0].content else {
            Issue.record("Expected heading block")
            return
        }
        #expect(heading == "Title")

        guard case .table(let table) = document.blocks[11].content else {
            Issue.record("Expected table block")
            return
        }
        #expect(table.headers == ["Name", "Score"])
        #expect(table.alignments == [.leading, .trailing])
        #expect(table.rows == [["Ada", "10"]])
    }

    @Test func compilerCachesDocumentsByFullMarkdownString() {
        let cache = AgentMarkdownCompiledDocumentCache(limit: 2)
        let markdown = "# Cached\n\nBody"
        var compileCount = 0

        let first = cache.document(for: markdown) { source in
            compileCount += 1
            return AgentMarkdownDocumentCompiler().compile(source)
        }
        let second = cache.document(for: markdown) { source in
            compileCount += 1
            return AgentMarkdownDocumentCompiler().compile(source)
        }

        #expect(compileCount == 1)
        #expect(first.id == second.id)
        #expect(first.blocks.map(\.id) == second.blocks.map(\.id))
    }

    @Test func cacheEvictsWhenLimitIsReached() {
        let cache = AgentMarkdownCompiledDocumentCache(limit: 2)
        var compileCount = 0

        for markdown in ["one", "two", "three", "one"] {
            _ = cache.document(for: markdown) { source in
                compileCount += 1
                return AgentMarkdownDocumentCompiler().compile(source)
            }
        }

        #expect(compileCount == 4)
    }

    @Test func renderWindowLimitsMaterializedBlocksAndReportsOmittedCount() {
        let markdown = (1...20)
            .map { "Paragraph \($0)" }
            .joined(separator: "\n\n")
        let document = AgentMarkdownDocumentCompiler().compile(markdown)

        let window = AgentMarkdownCompiledRenderWindowPolicy().window(
            for: document,
            maxRenderedBlocks: 5
        )

        #expect(window.blocks.count == 5)
        #expect(window.omittedBlockCount == document.blocks.count - 5)
        #expect(window.blocks.map(\.id) == Array(document.blocks.prefix(5)).map(\.id))
    }

    @Test func renderWindowReturnsAllBlocksWhenLimitIsNil() {
        let document = AgentMarkdownDocumentCompiler().compile("one\n\ntwo")

        let window = AgentMarkdownCompiledRenderWindowPolicy().window(
            for: document,
            maxRenderedBlocks: nil
        )

        #expect(window.blocks == document.blocks)
        #expect(window.omittedBlockCount == 0)
    }
}
