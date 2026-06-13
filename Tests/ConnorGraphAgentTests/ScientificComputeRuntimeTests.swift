import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphCore

@Test func readOnlyPolicyApprovesScientificComputeCapability() async throws {
    let audit = InMemoryAgentAuditLog()
    let policy = AgentPolicyEngine(permissionMode: .readOnly, auditLog: audit)

    let decision = await policy.evaluate(
        capability: .computeScientific,
        runID: "run-science-permission",
        sessionID: "session-science-permission",
        toolName: "science_compute",
        payloadJSON: "{}"
    )

    #expect(decision.outcome == .approved)
    #expect(await audit.events.first?.capability == .computeScientific)
}

@Test func nativeScientificEngineAddsAndComparesScalars() async throws {
    let engine = NativeSwiftScientificEngine()

    let add = try await engine.compute(ScientificComputeRequest(
        operation: .add,
        inputs: .object([
            "values": .array([.double(2), .double(3), .double(4)])
        ])
    ))
    #expect(add.value == .double(9))
    #expect(add.diagnostics.engine == "native-swift")

    let compare = try await engine.compute(ScientificComputeRequest(
        operation: .compare,
        inputs: .object([
            "left": .double(0.30000000000000004),
            "right": .double(0.3)
        ]),
        options: ScientificComputeOptions(absoluteTolerance: 1e-12)
    ))
    #expect(compare.value.objectValue?["relation"] == .string("approximately_equal"))
    #expect(compare.value.objectValue?["comparison"] == .int(0))
}

@Test func nativeScientificEngineComputesStatsUnitsAndLinearAlgebra() async throws {
    let engine = NativeSwiftScientificEngine()

    let stats = try await engine.compute(ScientificComputeRequest(
        operation: .summary,
        inputs: .object(["values": .array([.double(1), .double(2), .double(3), .double(4), .double(5)])])
    ))
    #expect(stats.value.objectValue?["mean"] == .double(3))
    #expect(stats.value.objectValue?["median"] == .double(3))

    let unit = try await engine.compute(ScientificComputeRequest(
        operation: .unitConvert,
        inputs: .object(["value": .double(72), "from": .string("km/h"), "to": .string("m/s")])
    ))
    #expect(unit.value.objectValue?["value"] == .double(20))
    #expect(unit.value.objectValue?["dimension"] == .string("speed"))

    let linalg = try await engine.compute(ScientificComputeRequest(
        operation: .solveLinearSystem,
        inputs: .object([
            "matrix": .array([.array([.double(2), .double(1)]), .array([.double(1), .double(3)])]),
            "vector": .array([.double(1), .double(2)])
        ])
    ))
    #expect(linalg.value.objectValue?["solution"] == .array([.double(0.2), .double(0.6)]))
}

@Test func scientificComputeToolReturnsStructuredJSON() async throws {
    let tool = ScienceComputeTool(runtime: ScientificComputeRuntime(engines: [NativeSwiftScientificEngine()]))
    let result = try await tool.execute(
        arguments: try AgentToolArguments(json: #"{"operation":"greater_than","inputs":{"left":5,"right":3}}"#),
        context: scientificContext(toolCallID: "science-tool-call")
    )

    #expect(result.toolName == "science_compute")
    #expect(result.contentText.contains("greater_than"))
    #expect(result.contentJSON?.contains("native-swift") == true)
}

private func scientificContext(toolCallID: String = "tool-call-science") -> AgentToolExecutionContext {
    AgentToolExecutionContext(
        runID: "run-science",
        sessionID: "session-science",
        groupID: "default",
        userPrompt: "calculate",
        toolCallID: toolCallID,
        policyEngine: AgentPolicyEngine(permissionMode: .allowAll)
    )
}
