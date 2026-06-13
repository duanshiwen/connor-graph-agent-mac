import Testing
import ConnorGraphAppSupport

@Test func markdownBlockParserParsesTablesWithAlignmentAndRows() throws {
    let markdown = """
    | Name | Count | Status |
    | :--- | ---: | :---: |
    | Alpha | 12 | Ready |
    | Beta | 3 | Blocked |
    """

    let blocks = AgentMarkdownBlockParser().parse(markdown)
    let tableBlock = try #require(blocks.first)
    guard case .table(let table) = tableBlock else {
        Issue.record("Expected table block, got \(tableBlock)")
        return
    }

    #expect(table.headers == ["Name", "Count", "Status"])
    #expect(table.alignments == [.leading, .trailing, .center])
    #expect(table.rows == [
        ["Alpha", "12", "Ready"],
        ["Beta", "3", "Blocked"]
    ])
}

@Test func markdownBlockParserParsesHorizontalRulesWithoutTreatingThemAsParagraphs() throws {
    let blocks = AgentMarkdownBlockParser().parse("""
    Intro

    ---

    Outro
    """)

    #expect(blocks.contains(.horizontalRule))
    #expect(blocks.contains(.paragraph("Intro")))
    #expect(blocks.contains(.paragraph("Outro")))
    #expect(!blocks.contains(.paragraph("---")))
}

@Test func markdownBlockParserParsesTaskItemsBeforeUnorderedItems() throws {
    let blocks = AgentMarkdownBlockParser().parse("""
    - [ ] Fix table rendering
    - [x] Support horizontal rules
    - Ordinary bullet
    """)

    #expect(blocks == [
        .taskItem(isCompleted: false, text: "Fix table rendering"),
        .taskItem(isCompleted: true, text: "Support horizontal rules"),
        .unorderedItem("Ordinary bullet")
    ])
}

@Test func markdownBlockParserPreservesCodeFenceLanguage() throws {
    let markdown = """
    ```swift
    let value = 42
    ```
    """

    let blocks = AgentMarkdownBlockParser().parse(markdown)
    #expect(blocks == [.code(language: "swift", text: "let value = 42")])
}

@Test func markdownBlockParserStillSupportsCommonMarkdownBlocks() throws {
    let blocks = AgentMarkdownBlockParser().parse("""
    # Title
    Paragraph with **strong** text.
    > Quoted text
    1. Ordered item
    - Bullet item
    """)

    #expect(blocks == [
        .heading(level: 1, text: "Title"),
        .paragraph("Paragraph with **strong** text."),
        .quote("Quoted text"),
        .orderedItem(number: "1", text: "Ordered item"),
        .unorderedItem("Bullet item")
    ])
}
