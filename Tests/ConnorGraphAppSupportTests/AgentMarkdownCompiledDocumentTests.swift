import Testing
import Foundation
import ConnorGraphCore
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

        let first = cache.document(for: markdown, compile: { source, cachedBlocks in
            compileCount += 1
            if let cachedBlocks {
                return AgentMarkdownDocumentCompiler().compile(source: source, blocks: cachedBlocks)
            }
            return AgentMarkdownDocumentCompiler().compile(source)
        })
        let second = cache.document(for: markdown, compile: { source, cachedBlocks in
            compileCount += 1
            if let cachedBlocks {
                return AgentMarkdownDocumentCompiler().compile(source: source, blocks: cachedBlocks)
            }
            return AgentMarkdownDocumentCompiler().compile(source)
        })

        #expect(compileCount == 1)
        #expect(first.id == second.id)
        #expect(first.blocks.map(\.id) == second.blocks.map(\.id))
    }

    @Test func renderWindowLimitsMaterializedBlocksAndReportsOmittedCount() {
        let markdown = (1...20)
            .map { "Paragraph \($0)" }
            .joined(separator: "\n\n")
        let document = AgentMarkdownDocumentCompiler().compile(markdown)

        let window = AgentMarkdownCompiledRenderWindowPolicy().window(for: document, maxRenderedBlocks: 5)

        #expect(window.blocks.count == 5)
        #expect(window.omittedBlockCount == document.blocks.count - 5)
        #expect(window.blocks.map(\.id) == Array(document.blocks.prefix(5)).map(\.id))
    }

    @Test func diskCacheRoundTripsParsedBlocksAndInvalidatesOnContentChange() throws {
        let temp = temporaryDirectory()
        let paths = AppStoragePaths(applicationSupportDirectory: temp)
        let store = AgentMarkdownRenderCacheStore(storagePaths: paths)
        let content = "# Cached\n\nBody with **markdown**"
        let blocks = AgentMarkdownBlockParser().parse(content)

        try store.saveBlocks(sessionID: "session-1", messageID: "message-1", content: content, blocks: blocks)

        let loaded = try store.loadBlocks(sessionID: "session-1", messageID: "message-1", content: content)
        #expect(loaded == blocks)

        let stale = try store.loadBlocks(sessionID: "session-1", messageID: "message-1", content: content + " changed")
        #expect(stale == nil)
    }

    @Test func prewarmWritesAssistantCachesOnlyForLongMessages() throws {
        let temp = temporaryDirectory()
        let paths = AppStoragePaths(applicationSupportDirectory: temp)
        let store = AgentMarkdownRenderCacheStore(storagePaths: paths)
        let longAssistant = String(repeating: "long markdown paragraph\n\n", count: 60)
        let shortAssistant = "short"
        let userContent = String(repeating: "user markdown\n\n", count: 60)
        let session = AgentSession(
            id: "session-prewarm",
            messages: [
                AgentMessage(id: "user-long", role: .user, content: userContent),
                AgentMessage(id: "assistant-short", role: .assistant, content: shortAssistant),
                AgentMessage(id: "assistant-long", role: .assistant, content: longAssistant)
            ]
        )

        try store.prewarm(session: session, minimumContentLength: 100)

        #expect(try store.loadBlocks(sessionID: session.id, messageID: "assistant-long", content: longAssistant) != nil)
        #expect(try store.loadBlocks(sessionID: session.id, messageID: "assistant-short", content: shortAssistant) == nil)
        #expect(try store.loadBlocks(sessionID: session.id, messageID: "user-long", content: userContent) == nil)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-markdown-cache-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
