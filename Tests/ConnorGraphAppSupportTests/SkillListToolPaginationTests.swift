import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphCore
@testable import ConnorGraphAppSupport

private struct SkillListTestItem: Decodable {
    var slug: String
}

private struct SkillListTestPage: Decodable {
    var page: Int
    var pageSize: Int
    var returnedItems: Int
    var totalItems: Int
    var totalPages: Int
    var hasNextPage: Bool
    var nextPage: Int?
    var skills: [SkillListTestItem]
}

private func pagedSkill(_ slug: String) -> SkillPackage {
    SkillPackage(
        id: SkillPackageID("user:/tmp/\(slug)"),
        slug: SkillSlug(slug),
        sourceTier: .user,
        manifest: SkillManifest(name: slug.uppercased(), description: "\(slug) skill"),
        instructions: "Use \(slug).",
        packagePath: "/tmp/\(slug)",
        skillFilePath: "/tmp/\(slug)/SKILL.md"
    )
}

private func skillListContext(_ page: Int) -> AgentToolExecutionContext {
    AgentToolExecutionContext(
        runID: "skill-list-run",
        sessionID: "skill-list-session",
        groupID: "default",
        userPrompt: "list skills",
        toolCallID: "skill-list-page-\(page)",
        policyEngine: AgentPolicyEngine(permissionMode: .readOnly)
    )
}

@Test func skillListFollowsNextPageWithoutGapsOrDuplicatesInStableOrder() async throws {
    let tool = SkillListTool(packages: ["echo", "alpha", "delta", "bravo", "charlie"].map(pagedSkill))
    var page = 1
    var slugs: [String] = []
    var seenPages: [Int] = []

    while true {
        let result = try await tool.execute(
            arguments: AgentToolArguments(values: ["page": .int(page), "page_size": .int(2)]),
            context: skillListContext(page)
        )
        let payload = try JSONDecoder().decode(
            SkillListTestPage.self,
            from: Data(try #require(result.contentJSON).utf8)
        )
        seenPages.append(payload.page)
        slugs.append(contentsOf: payload.skills.map(\.slug))
        #expect(payload.pageSize == 2)
        #expect(payload.returnedItems == payload.skills.count)
        #expect(payload.totalItems == 5)
        #expect(payload.totalPages == 3)
        if let nextPage = payload.nextPage {
            #expect(payload.hasNextPage)
            page = nextPage
        } else {
            #expect(!payload.hasNextPage)
            break
        }
    }

    #expect(seenPages == [1, 2, 3])
    #expect(slugs == ["alpha", "bravo", "charlie", "delta", "echo"])
    #expect(Set(slugs).count == slugs.count)
}

@Test func skillListRejectsInvalidPaginationInsteadOfFallingBack() async {
    let tool = SkillListTool(packages: [pagedSkill("alpha")])
    await #expect(throws: AgentToolError.self) {
        try await tool.execute(
            arguments: AgentToolArguments(values: ["page": .int(0), "page_size": .int(2)]),
            context: skillListContext(0)
        )
    }
    await #expect(throws: AgentToolError.self) {
        try await tool.execute(
            arguments: AgentToolArguments(values: ["page": .int(2), "page_size": .int(2)]),
            context: skillListContext(2)
        )
    }
}
