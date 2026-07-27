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

        #expect(created.contentText.contains("Created person"))
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
        #expect(listed.contentText.contains("personID: person-zhang-xia"))
        #expect(listed.contentText.contains("displayName: 张霞"))
        #expect(listed.contentText.contains("status: active"))
        #expect(listed.contentText.contains("段诗闻和段福强的妈妈"))
        #expect(listed.contentJSON?.contains(#""personID":"person-zhang-xia""#) == true)
        #expect(listed.contentJSON?.contains(#""person_id""#) == false)

        let loaded = try await readTool.execute(
            arguments: try AgentToolArguments(json: "{\"operation\":\"get_person\",\"personID\":\"person-zhang-xia\"}"),
            context: Self.context(toolCallID: "call-get-person-summary")
        )
        #expect(loaded.contentText.contains("Loaded person"))
        #expect(loaded.contentText.contains("personID: person-zhang-xia"))
        #expect(loaded.contentText.contains("displayName: 张霞"))
    }

    @Test func contactsReadReturnsEveryPersonPhoto() async throws {
        let paths = ["contacts/images/person-photo/one.png", "contacts/images/person-photo/two.jpg"]
        let runtime = InMemoryAgentContactRuntime(people: [
            PersonProfile(id: ContactID(rawValue: "person-photo"), displayName: "多图联系人", imageRelativePaths: paths)
        ])
        let result = try await ContactsReadTool(runtime: runtime).execute(
            arguments: try AgentToolArguments(json: "{\"operation\":\"get_person\",\"personID\":\"person-photo\"}"),
            context: Self.context(toolCallID: "call-get-person-photos")
        )

        let data = try #require(result.contentJSON?.data(using: .utf8))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["imageRelativePaths"] as? [String] == paths)
        #expect(object["photos"] as? [String] == paths)
    }

    @Test func contactsWriteCreatePersonAcceptsLLMDiscoveryWithoutApprovedFlagAndParsesAliases() async throws {
        let runtime = InMemoryAgentContactRuntime()
        let writeTool = ContactsWriteTool(runtime: runtime)

        let created = try await writeTool.execute(
            arguments: try AgentToolArguments(json: "{\"operation\":\"create_person\",\"name\":\"张三\",\"aliases\":[\"小张\",\"Zhang San\"],\"source\":\"llm-discovery\"}"),
            context: Self.context(toolCallID: "call-create-auto-person")
        )

        #expect(created.contentText.contains("Created person"))
        #expect(created.contentJSON?.contains("张三") == true)
        #expect(created.contentJSON?.contains("小张") == true)
        #expect(created.contentJSON?.contains("Zhang San") == true)
        #expect(created.contentJSON?.contains("active") == true)
    }

    @Test func contactsReadGetPersonFallsBackToUniqueDisplayNameMatch() async throws {
        let runtime = InMemoryAgentContactRuntime(people: [
            PersonProfile(
                id: ContactID(rawValue: "person-duan-fuqiang"),
                displayName: "段福强",
                emails: [ContactEmailAddress(email: "oisin.duan@apecho.com")]
            )
        ])
        let readTool = ContactsReadTool(runtime: runtime)

        let result = try await readTool.execute(
            arguments: try AgentToolArguments(json: "{\"operation\":\"get_person\",\"id\":\"段福强\"}"),
            context: Self.context(toolCallID: "call-get-person-by-name")
        )

        #expect(result.contentText.contains("Resolved person by query"))
        #expect(result.contentJSON?.contains("person-duan-fuqiang") == true)
        #expect(result.contentJSON?.contains("oisin.duan@apecho.com") == true)
    }

    @Test func contactsReadGetPersonReportsAmbiguousDisplayNameMatches() async throws {
        let runtime = InMemoryAgentContactRuntime(people: [
            PersonProfile(id: ContactID(rawValue: "person-a"), displayName: "小王"),
            PersonProfile(id: ContactID(rawValue: "person-b"), displayName: "王小明", aliases: ["小王"])
        ])
        let readTool = ContactsReadTool(runtime: runtime)

        let result = try await readTool.execute(
            arguments: try AgentToolArguments(json: "{\"operation\":\"get_person\",\"id\":\"小王\"}"),
            context: Self.context(toolCallID: "call-get-person-ambiguous")
        )

        #expect(result.contentText.contains("Ambiguous person query"))
        #expect(result.contentJSON?.contains("person-a") == true)
        #expect(result.contentJSON?.contains("person-b") == true)
    }

    @Test func contactsWriteCanUpdateDeleteAndMergePeople() async throws {
        let runtime = InMemoryAgentContactRuntime(people: [
            PersonProfile(id: ContactID(rawValue: "person-a"), displayName: "小王", aliases: ["王同学"]),
            PersonProfile(id: ContactID(rawValue: "person-b"), displayName: "王诗闻")
        ])
        let writeTool = ContactsWriteTool(runtime: runtime)
        let readTool = ContactsReadTool(runtime: runtime)

        let updated = try await writeTool.execute(
            arguments: try AgentToolArguments(json: "{\"operation\":\"update_person\",\"personID\":\"person-a\",\"organization\":\"Connor Labs\",\"approved\":true}"),
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
            arguments: try AgentToolArguments(json: "{\"operation\":\"delete_person\",\"personID\":\"person-b\",\"approved\":true}"),
            context: Self.context(toolCallID: "call-delete-person")
        )
        #expect(deleted.contentText.contains("Deleted person"))

        let afterDelete = try await readTool.execute(
            arguments: try AgentToolArguments(json: "{\"operation\":\"search_people\",\"query\":\"王\"}"),
            context: Self.context(toolCallID: "call-after-delete")
        )
        #expect(afterDelete.contentText.contains("Found 0 people"))
    }

    @Test func contactsWriteSchemaDocumentsOptionalPersonImages() throws {
        let tool = ContactsWriteTool(runtime: InMemoryAgentContactRuntime())
        let properties = try #require(tool.inputSchema.jsonObject["properties"] as? [String: Any])
        let operation = try #require(properties["operation"] as? [String: Any])
        let operations = try #require(operation["enum"] as? [String])
        let attachments = try #require(properties["attachmentIDs"] as? [String: Any])

        #expect(operations.contains("add_person_images"))
        #expect(operations.contains("remove_all_person_images"))
        #expect(attachments["type"] as? String == "array")
        #expect((attachments["description"] as? String)?.contains("one or more exact image IDs") == true)
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
