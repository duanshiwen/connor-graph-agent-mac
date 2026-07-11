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

@Test func agentToolInputSchemaSerializesClosedObject() throws {
    let schema = AgentToolInputSchema.closedObject(
        properties: ["operation": .string(description: "Operation")],
        required: ["operation"]
    ).jsonObject

    #expect(schema["type"] as? String == "object")
    #expect(schema["required"] as? [String] == ["operation"])
    #expect(schema["additionalProperties"] as? Bool == false)
}
