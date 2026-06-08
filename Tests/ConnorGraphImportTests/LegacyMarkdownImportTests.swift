import Testing
import ConnorGraphCore
import ConnorGraphImport

@Test func frontmatterParserExtractsYamlAndBody() throws {
    let markdown = """
    ---
    title: Agent OS
    category: internal/work-objects/projects
    tags:
      - agent-os
      - graph-memory
    work_object_id: agent-os
    related:
      - internal/decisions/native-swift.md
    ---
    # Agent OS

    A graph-backed agent operating system.
    """

    let document = try FrontmatterParser().parse(markdown)

    #expect(document.frontmatter["title"]?.stringValue == "Agent OS")
    #expect(document.frontmatter["work_object_id"]?.stringValue == "agent-os")
    #expect(document.frontmatter["tags"]?.arrayValue.map(\.stringValue) == ["agent-os", "graph-memory"])
    #expect(document.body.contains("graph-backed"))
}

@Test func workObjectMarkdownMapsToGraphNode() throws {
    let document = LegacyMarkdownDocument(
        sourcePath: "internal/work-objects/projects/agent-os.md",
        frontmatter: [
            "title": .string("Agent OS"),
            "summary": .string("Local-first agent operating system"),
            "work_object_id": .string("agent-os")
        ],
        body: "Project profile"
    )

    let result = try LegacyMarkdownImporter().importDocument(document)

    #expect(result.nodes.count == 1)
    #expect(result.nodes[0].id == "work-object-agent-os")
    #expect(result.nodes[0].type == .workObject)
    #expect(result.nodes[0].sourcePath == document.sourcePath)
}

@Test func questionMarkdownMapsToQuestionNode() throws {
    let document = LegacyMarkdownDocument(
        sourcePath: "internal/questions/how-memory-works.md",
        frontmatter: [
            "title": .string("How should memory work?"),
            "knowledge_type": .string("question"),
            "work_object_id": .string("agent-os")
        ],
        body: "Question body"
    )

    let result = try LegacyMarkdownImporter().importDocument(document)

    let question = try #require(result.nodes.first { $0.type == .question })
    #expect(question.title == "How should memory work?")
    #expect(result.edges.contains { $0.sourceNodeID == question.id && $0.relation == .belongsTo && $0.targetNodeID == "work-object-agent-os" })
}

@Test func answerManifestMapsToAnswerNodeAndAnswersEdge() throws {
    let document = LegacyMarkdownDocument(
        sourcePath: "_system/answer-cache/2026/06/how-memory-works/v1/manifest.md",
        frontmatter: [
            "title": .string("Use graph-backed memory"),
            "knowledge_type": .string("answer"),
            "question_id": .string("question-how-memory-works")
        ],
        body: "Answer body"
    )

    let result = try LegacyMarkdownImporter().importDocument(document)

    let answer = try #require(result.nodes.first { $0.type == .answer })
    #expect(answer.title == "Use graph-backed memory")
    #expect(result.edges.contains { $0.sourceNodeID == "question-how-memory-works" && $0.targetNodeID == answer.id && $0.relation == .answeredBy })
}

@Test func decisionSOPAndPersonProfilesMapToTypedNodes() throws {
    let importer = LegacyMarkdownImporter()

    let decision = try importer.importDocument(.init(
        sourcePath: "internal/decisions/use-swiftui.md",
        frontmatter: ["title": .string("Use SwiftUI")],
        body: "Decision body"
    ))
    let sop = try importer.importDocument(.init(
        sourcePath: "internal/sops/import-knowledge.md",
        frontmatter: ["title": .string("Import knowledge")],
        body: "SOP body"
    ))
    let person = try importer.importDocument(.init(
        sourcePath: "internal/persons/profiles/shiwen.md",
        frontmatter: ["title": .string("诗闻")],
        body: "Person profile"
    ))

    #expect(decision.nodes[0].type == .decision)
    #expect(sop.nodes[0].type == .procedure)
    #expect(person.nodes[0].type == .person)
}

@Test func relatedAndAnswerRefsGenerateSemanticEdges() throws {
    let document = LegacyMarkdownDocument(
        sourcePath: "internal/work-objects/projects/agent-os.md",
        frontmatter: [
            "title": .string("Agent OS"),
            "work_object_id": .string("agent-os"),
            "related": .array([.string("internal/decisions/use-swiftui.md")]),
            "answer_cache_refs": .array([.string("_system/answer-cache/2026/06/how-memory-works/v1/manifest.md")])
        ],
        body: "Project body"
    )

    let result = try LegacyMarkdownImporter().importDocument(document)

    #expect(result.edges.contains { $0.relation == .relatedTo && $0.targetNodeID == "document-internal-decisions-use-swiftui-md" })
    #expect(result.edges.contains { $0.relation == .answeredBy && $0.targetNodeID == "answer-system-answer-cache-2026-06-how-memory-works-v1-manifest-md" })
}
