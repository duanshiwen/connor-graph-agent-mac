import Testing
import ConnorGraphAgent

@Test func agentToolInputSchemaSerializesStringEnumeration() throws {
    let schema = AgentToolInputSchema.stringEnumeration(
        values: ["create_event", "update_event", "delete_event"],
        description: "Calendar mutation operation"
    ).jsonObject

    #expect(schema["type"] as? String == "string")
    #expect(schema["enum"] as? [String] == ["create_event", "update_event", "delete_event"])
    #expect(schema["description"] as? String == "Calendar mutation operation")
}

@Test func agentToolInputSchemaSerializesNullableValue() throws {
    let schema = AgentToolInputSchema.nullable(
        .string(description: "Optional calendar ID")
    ).jsonObject

    #expect(schema["type"] as? [String] == ["string", "null"])
    #expect(schema["description"] as? String == "Optional calendar ID")
}

@Test func agentToolInputSchemaReportsOpenAIStrictCompatibility() {
    let compatible = AgentToolInputSchema.closedObject(
        properties: [
            "operation": .stringEnumeration(values: ["create"], description: "Operation"),
            "optionalID": .nullable(.string(description: "Optional ID"))
        ],
        required: ["operation", "optionalID"]
    )
    let missingRequired = AgentToolInputSchema.closedObject(
        properties: ["operation": .string(description: "Operation"), "optionalID": .string(description: "Optional ID")],
        required: ["operation"]
    )
    let openObject = AgentToolInputSchema.object(
        properties: ["operation": .string(description: "Operation")],
        required: ["operation"]
    )

    #expect(compatible.isOpenAIStrictCompatible)
    #expect(!missingRequired.isOpenAIStrictCompatible)
    #expect(!openObject.isOpenAIStrictCompatible)
}

@Test func agentToolInputSchemaValidationReportsPrecisePaths() {
    let valid = AgentToolInputSchema.closedObject(
        properties: [
            "operation": .stringEnumeration(values: ["read"], description: "Operation"),
            "filters": .array(items: .closedObject(
                properties: ["query": .string(description: "Query")],
                required: ["query"]
            ), description: "Filters")
        ],
        required: ["operation"]
    )
    #expect(valid.validationIssues(toolName: "valid_tool").isEmpty)

    let invalid = AgentToolInputSchema.object(
        properties: [
            "operation": .stringEnumeration(values: [], description: "Operation")
        ],
        required: ["operation", "missing", "missing"]
    )
    #expect(invalid.validationIssues(toolName: "invalid_tool") == [
        AgentToolSchemaValidationIssue(toolName: "invalid_tool", path: "$.required", message: "contains duplicate property missing"),
        AgentToolSchemaValidationIssue(toolName: "invalid_tool", path: "$.required", message: "references missing property missing"),
        AgentToolSchemaValidationIssue(toolName: "invalid_tool", path: "$.properties.operation.enum", message: "must contain at least one value")
    ])
}

@Test func agentToolRegistryAggregatesSchemaValidationIssues() {
    var registry = AgentToolRegistry()
    registry.register(InvalidSchemaTestTool())

    #expect(registry.schemaValidationIssues == [
        AgentToolSchemaValidationIssue(toolName: "invalid_schema_test", path: "$.required", message: "references missing property absent")
    ])
}

@Test func agentToolInputSchemaRejectsSnakeCasePropertiesAndNormalizesLegacyArguments() {
    let schema = AgentToolInputSchema.closedObject(
        properties: [
            "taskID": .string(description: "Task ID"),
            "expectedUpdatedAt": .string(description: "Expected update time")
        ],
        required: ["taskID"]
    )
    #expect(schema.validationIssues(toolName: "camel_tool").isEmpty)
    #expect(schema.normalizingLegacyPropertyAliases(.object([
        "task_id": .string("task-1"),
        "expected_updated_at": .string("2026-07-24T00:00:00Z")
    ])) == .object([
        "taskID": .string("task-1"),
        "expectedUpdatedAt": .string("2026-07-24T00:00:00Z")
    ]))

    let nestedSchema = AgentToolInputSchema.closedObject(properties: [
        "updates": .array(items: .closedObject(properties: [
            "sessionID": .string(description: "Session ID"),
            "expectedUpdatedAt": .string(description: "Expected update time")
        ], required: ["sessionID"]), description: "Session updates")
    ], required: ["updates"])
    #expect(nestedSchema.normalizingLegacyPropertyAliases(.object([
        "updates": .array([.object([
            "session_id": .string("session-1"),
            "expected_updated_at": .string("2026-07-24T00:00:00Z")
        ])])
    ])) == .object([
        "updates": .array([.object([
            "sessionID": .string("session-1"),
            "expectedUpdatedAt": .string("2026-07-24T00:00:00Z")
        ])])
    ]))

    let invalid = AgentToolInputSchema.closedObject(
        properties: ["task_id": .string(description: "Task ID")],
        required: ["task_id"]
    )
    #expect(invalid.validationIssues(toolName: "snake_tool") == [
        AgentToolSchemaValidationIssue(
            toolName: "snake_tool",
            path: "$.properties.task_id",
            message: "property names exposed to the model must use camelCase"
        )
    ])
}

@Test func agentToolInputSchemaNormalizesUnambiguousLegacyValueFormats() {
    let schema = AgentToolInputSchema.closedObject(
        properties: [
            "timeSort": .stringEnumeration(values: ["timeAscThenRelevance", "timeDescThenRelevance"], description: "Sort"),
            "limit": .integer(description: "Limit"),
            "enabled": .boolean(description: "Enabled"),
            "optionalText": .string(description: "Optional text")
        ],
        required: []
    )

    #expect(schema.normalizingLegacyPropertyAliases(.object([
        "time_sort": .string("time_asc_then_relevance"),
        "limit": .string("50"),
        "enabled": .string("true"),
        "optionalText": .null
    ])) == .object([
        "timeSort": .string("timeAscThenRelevance"),
        "limit": .int(50),
        "enabled": .bool(true)
    ]))
}

@Test func agentToolInputSchemaNormalizesLegacyKeywordsAliasToQuery() {
    let schema = AgentToolInputSchema.closedObject(
        properties: ["query": .string(description: "Query")],
        required: ["query"]
    )

    #expect(schema.normalizingLegacyPropertyAliases(.object([
        "keywords": .string("Project A")
    ])) == .object(["query": .string("Project A")]))

    // A direct query still wins when both are present, and unrelated unknown keys stay rejected.
    #expect(schema.normalizingLegacyPropertyAliases(.object([
        "keywords": .string("Project A"),
        "query": .string("Project B")
    ])) == .object(["query": .string("Project B")]))
    #expect(schema.argumentValidationIssues(.object(["topic": .string("Project A")])) == [
        "$.query is required",
        "$.topic is not supported"
    ])
}

@Test func agentToolRegistryAcceptsLegacySnakeCaseAliasesWithoutExposingThem() async throws {
    var registry = AgentToolRegistry()
    registry.register(LegacyAliasTestTool())
    let result = try await registry.execute(
        AgentToolCall(name: "legacy_alias_test", argumentsJSON: #"{"task_id":"task-1"}"#),
        context: AgentToolExecutionContext(
            runID: "run",
            sessionID: "session",
            groupID: "group",
            userPrompt: "test aliases",
            toolCallID: "call",
            policyEngine: AgentPolicyEngine(permissionMode: .readOnly)
        )
    )

    #expect(result.contentText == "task-1")
    let properties = try #require(registry.definition(named: "legacy_alias_test")?.inputSchema.jsonObject["properties"] as? [String: Any])
    #expect(properties["taskID"] != nil)
    #expect(properties["task_id"] == nil)
}

@Test func agentToolRegistryNormalizesLegacyAliasesBeforePreflightAndApproval() async throws {
    var registry = AgentToolRegistry()
    registry.register(LegacyAliasLifecycleTestTool())
    let context = AgentToolExecutionContext(
        runID: "run",
        sessionID: "session",
        groupID: "group",
        userPrompt: "test lifecycle aliases",
        toolCallID: "call",
        policyEngine: AgentPolicyEngine(permissionMode: .askToWrite)
    )

    do {
        _ = try await registry.execute(
            AgentToolCall(name: "legacy_alias_lifecycle_test", argumentsJSON: #"{"task_id":"task-1"}"#),
            context: context
        )
        Issue.record("Expected approval to be required")
    } catch AgentToolError.permissionNeedsApproval(let request) {
        #expect(request.payloadJSON.contains(#""taskID":"task-1""#))
        #expect(!request.payloadJSON.contains("task_id"))
    }
}

private struct InvalidSchemaTestTool: AgentTool {
    let name = "invalid_schema_test"
    let description = "Invalid schema test tool"
    let inputSchema = AgentToolInputSchema.object(
        properties: [:],
        required: ["absent"]
    )
    let permission = AgentPermissionCapability.readSession

    func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "unused")
    }
}

private struct LegacyAliasTestTool: AgentTool {
    let name = "legacy_alias_test"
    let description = "Legacy alias test tool"
    let inputSchema = AgentToolInputSchema.closedObject(
        properties: ["taskID": .string(description: "Task ID")],
        required: ["taskID"]
    )
    let permission = AgentPermissionCapability.readSession

    func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: arguments.string("taskID") ?? "missing")
    }
}

private struct LegacyAliasLifecycleTestTool: AgentTool {
    let name = "legacy_alias_lifecycle_test"
    let description = "Legacy alias lifecycle test tool"
    let inputSchema = AgentToolInputSchema.closedObject(
        properties: ["taskID": .string(description: "Task ID")],
        required: ["taskID"]
    )
    let permission = AgentPermissionCapability.editWorkspaceFile

    func preflight(call: AgentToolCall, context: AgentToolExecutionContext) async throws {
        let arguments = try AgentToolArguments(json: call.argumentsJSON)
        guard arguments.string("taskID") == "task-1" else {
            throw AgentToolError.invalidArguments("preflight did not receive normalized taskID")
        }
    }

    func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "unused")
    }
}

@Test func agentToolInputSchemaSerializesClosedObject() throws {
    let schema = AgentToolInputSchema.closedObject(
        properties: ["operation": .string(description: "Operation")],
        required: ["operation"]
    ).jsonObject

    #expect(schema["type"] as? String == "object")
    #expect(schema["required"] as? [String] == ["operation"])
    #expect(schema["additionalProperties"] as? Bool == false)
}

@Test func closedAgentToolInputSchemaRejectsUnknownAndInvalidArguments() throws {
    let schema = AgentToolInputSchema.closedObject(
        properties: [
            "query": .string(description: "Query"),
            "page": .integer(description: "Page")
        ],
        required: ["query"]
    )

    let issues = schema.argumentValidationIssues(.object([
        "query": .string("memory"),
        "page": .string("two"),
        "limit": .int(10)
    ]))

    #expect(issues == ["$.limit is not supported", "$.page must be an integer"])
}

@Test func openAgentToolInputSchemaStillAllowsExtensiblePayloads() throws {
    let schema = AgentToolInputSchema.object(
        properties: ["operation": .string(description: "Operation")],
        required: ["operation"]
    )

    let issues = schema.argumentValidationIssues(.object([
        "operation": .string("custom"),
        "providerExtension": .string("value")
    ]))

    #expect(issues.isEmpty)
}
