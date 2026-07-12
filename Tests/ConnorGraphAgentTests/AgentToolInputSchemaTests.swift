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

@Test func agentToolInputSchemaSerializesClosedObject() throws {
    let schema = AgentToolInputSchema.closedObject(
        properties: ["operation": .string(description: "Operation")],
        required: ["operation"]
    ).jsonObject

    #expect(schema["type"] as? String == "object")
    #expect(schema["required"] as? [String] == ["operation"])
    #expect(schema["additionalProperties"] as? Bool == false)
}
