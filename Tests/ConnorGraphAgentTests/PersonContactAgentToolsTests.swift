import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAgent

@Suite("Person Contact Agent Tools Tests")
struct PersonContactAgentToolsTests {
    @Test func contactsWriteCanCreatePersonWithoutContactMethods() async throws {
        let runtime = InMemoryAgentContactRuntime()
        let writeTool = ContactsWriteTool(runtime: runtime)

        let created = try await writeTool.execute(
            arguments: try AgentToolArguments(json: "{\"operation\":\"create_person\",\"name\":\"小王\",\"approved\":true}"),
            context: Self.context(toolCallID: "call-create-person")
        )

        #expect(created.contentText.contains("Created approved person"))
        #expect(created.contentJSON?.contains("小王") == true)

        let readTool = ContactsReadTool(runtime: runtime)
        let found = try await readTool.execute(
            arguments: try AgentToolArguments(json: "{\"operation\":\"search_people\",\"query\":\"小王\"}"),
            context: Self.context(toolCallID: "call-search-person")
        )
        #expect(found.contentText.contains("Found 1 people"))
    }

    @Test func contactsReadSummarizesPeopleWithIDsInContentText() async throws {
        let runtime = InMemoryAgentContactRuntime(people: [
            PersonProfile(
                id: ContactID(rawValue: "person-zhang-xia"),
                displayName: "张霞",
                aliases: ["妈妈"],
                notes: "段诗闻和段福强的妈妈。"
            )
        ])
        let readTool = ContactsReadTool(runtime: runtime)

        let listed = try await readTool.execute(
            arguments: try AgentToolArguments(json: "{\"operation\":\"list_people\"}"),
            context: Self.context(toolCallID: "call-list-people-summary")
        )
        #expect(listed.contentText.contains("Found 1 people"))
        #expect(listed.contentText.contains("person_id: person-zhang-xia"))
        #expect(listed.contentText.contains("display_name: 张霞"))
        #expect(listed.contentText.contains("status: active"))
        #expect(listed.contentText.contains("段诗闻和段福强的妈妈"))

        let loaded = try await readTool.execute(
            arguments: try AgentToolArguments(json: "{\"operation\":\"get_person\",\"id\":\"person-zhang-xia\"}"),
            context: Self.context(toolCallID: "call-get-person-summary")
        )
        #expect(loaded.contentText.contains("Loaded person"))
        #expect(loaded.contentText.contains("person_id: person-zhang-xia"))
        #expect(loaded.contentText.contains("display_name: 张霞"))
    }

    @Test func contactsWriteCanUpdateDeleteAndMergePeople() async throws {
        let runtime = InMemoryAgentContactRuntime(people: [
            PersonProfile(id: ContactID(rawValue: "person-a"), displayName: "小王", aliases: ["王同学"]),
            PersonProfile(id: ContactID(rawValue: "person-b"), displayName: "王诗闻")
        ])
        let writeTool = ContactsWriteTool(runtime: runtime)
        let readTool = ContactsReadTool(runtime: runtime)

        let updated = try await writeTool.execute(
            arguments: try AgentToolArguments(json: "{\"operation\":\"update_person\",\"id\":\"person-a\",\"organization\":\"Connor Labs\",\"approved\":true}"),
            context: Self.context(toolCallID: "call-update-person")
        )
        #expect(updated.contentJSON?.contains("Connor Labs") == true)

        let merged = try await writeTool.execute(
            arguments: try AgentToolArguments(json: "{\"operation\":\"merge_people\",\"sourceID\":\"person-a\",\"targetID\":\"person-b\",\"approved\":true}"),
            context: Self.context(toolCallID: "call-merge-person")
        )
        #expect(merged.contentText.contains("Merged person"))

        let searchSource = try await readTool.execute(
            arguments: try AgentToolArguments(json: "{\"operation\":\"search_people\",\"query\":\"小王\"}"),
            context: Self.context(toolCallID: "call-search-merged")
        )
        #expect(searchSource.contentText.contains("Found 1 people"))
        #expect(searchSource.contentJSON?.contains("person-b") == true)

        let deleted = try await writeTool.execute(
            arguments: try AgentToolArguments(json: "{\"operation\":\"delete_person\",\"id\":\"person-b\",\"approved\":true}"),
            context: Self.context(toolCallID: "call-delete-person")
        )
        #expect(deleted.contentText.contains("Deleted person"))

        let afterDelete = try await readTool.execute(
            arguments: try AgentToolArguments(json: "{\"operation\":\"search_people\",\"query\":\"王\"}"),
            context: Self.context(toolCallID: "call-after-delete")
        )
        #expect(afterDelete.contentText.contains("Found 0 people"))
    }

    private static func context(toolCallID: String) -> AgentToolExecutionContext {
        let audit = InMemoryAgentAuditLog()
        let policy = AgentPolicyEngine(permissionMode: .allowAll, auditLog: audit)
        return AgentToolExecutionContext(
            runID: "run-person-contacts",
            sessionID: "session-person-contacts",
            groupID: "group-person-contacts",
            userPrompt: "test",
            toolCallID: toolCallID,
            policyEngine: policy
        )
    }
}
