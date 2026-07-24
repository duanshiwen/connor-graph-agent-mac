import Foundation
import Testing
import ConnorGraphAgent

private actor CountingEnvironmentProvider: AgentEnvironmentProviding {
    private(set) var requestCount = 0
    let value: AgentEnvironmentSnapshot

    init(value: AgentEnvironmentSnapshot) {
        self.value = value
    }

    func snapshot(for request: AgentEnvironmentRequest) async -> AgentEnvironmentSnapshot {
        requestCount += 1
        return value
    }
}

private actor EnvironmentLoopModelProvider: AgentModelProvider {
    let modelID = "environment-loop"
    let capabilities = AgentModelCapabilities(
        supportsStreaming: false,
        supportsToolCalling: true,
        supportsParallelToolCalls: false,
        supportsStructuredOutput: false,
        supportsVision: false
    )
    private(set) var requests: [AgentModelRequest] = []

    func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse {
        requests.append(request)
        if requests.count == 1 {
            return AgentModelResponse(
                text: nil,
                toolCalls: [AgentToolCall(id: "environment-noop-call", name: "environment_noop", argumentsJSON: "{}")],
                finishReason: .toolCalls
            )
        }
        return AgentModelResponse(text: "done", finishReason: .stop)
    }
}

private struct EnvironmentNoopTool: AgentTool {
    let name = "environment_noop"
    let description = "Test-only no-op."
    let permission: AgentPermissionCapability = .readSession
    let inputSchema = AgentToolInputSchema.closedObject(properties: [:], required: [])

    func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "ok")
    }
}

private func environmentFixture() -> AgentEnvironmentSnapshot {
    AgentEnvironmentSnapshot(
        capturedAt: Date(timeIntervalSince1970: 1_790_000_000),
        location: AgentEnvironmentLocation(
            status: .available,
            locality: "Hangzhou",
            administrativeArea: "Zhejiang",
            country: "China",
            latitude: 30.12345,
            longitude: 120.98765,
            horizontalAccuracyMeters: 1_200,
            capturedAt: Date(timeIntervalSince1970: 1_790_000_000)
        ),
        localTime: AgentEnvironmentLocalTime(
            timeZoneIdentifier: "Asia/Shanghai",
            localDateTime: "2026-09-22 09:00:00",
            dayPeriod: "morning"
        ),
        weather: AgentEnvironmentWeather(
            status: .available,
            condition: "晴朗",
            temperatureCelsius: 25,
            source: "Open-Meteo",
            sourceURL: "https://open-meteo.com/",
            updatedAt: Date(timeIntervalSince1970: 1_790_000_000)
        )
    )
}

@Test func environmentPreflightRunsOnceAcrossInternalModelTurns() async throws {
    let environmentProvider = CountingEnvironmentProvider(value: environmentFixture())
    let modelProvider = EnvironmentLoopModelProvider()
    var registry = AgentToolRegistry()
    registry.register(EnvironmentNoopTool())
    let loop = AgentLoopController(
        modelProvider: modelProvider,
        toolRegistry: registry,
        environmentProvider: AnyAgentEnvironmentProvider(environmentProvider),
        environmentStore: AgentEnvironmentSnapshotStore()
    )

    for try await _ in loop.run(AgentChatRequest(
        runID: "environment-run",
        sessionID: "environment-session",
        userMessage: "hello",
        permissionMode: .allowAll
    )) {}

    #expect(await environmentProvider.requestCount == 1)
    #expect(await modelProvider.requests.count == 2)
    let firstRequest = try #require(await modelProvider.requests.first)
    let systemText = firstRequest.messages.filter { $0.role == .system }.map(\.content).joined(separator: "\n")
    #expect(systemText.contains("Current Environment Snapshot"))
    #expect(systemText.contains("Hangzhou"))
    #expect(systemText.contains("Open-Meteo"))
    #expect(systemText.contains("weather.updatedAt is the actual provider query time"))
    #expect(systemText.contains("Do not give umbrella"))
    #expect(!AgentEnvironmentPromptRenderer.render(environmentFixture()).localizedCaseInsensitiveContains("calendar"))
}

@Test func environmentPromptAndToolExposeOnlyCoarseCoordinates() async throws {
    let fixture = environmentFixture()
    let provider = CountingEnvironmentProvider(value: fixture)
    let store = AgentEnvironmentSnapshotStore()
    await store.set(fixture, forRunID: "environment-tool-run")
    let tool = GetCurrentEnvironmentTool(
        provider: AnyAgentEnvironmentProvider(provider),
        store: store
    )
    let context = AgentToolExecutionContext(
        runID: "environment-tool-run",
        sessionID: "environment-tool-session",
        groupID: "default",
        userPrompt: "weather",
        toolCallID: "environment-tool-call",
        policyEngine: AgentPolicyEngine(permissionMode: .allowAll)
    )

    let result = try await tool.execute(arguments: AgentToolArguments(), context: context)

    #expect(await provider.requestCount == 0)
    #expect(result.contentJSON?.contains("30.12") == true)
    #expect(result.contentJSON?.contains("120.99") == true)
    #expect(result.contentJSON?.contains("30.12345") == false)
    #expect(result.contentJSON?.localizedCaseInsensitiveContains("calendar") == false)
}
