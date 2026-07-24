import Foundation
import Testing
import ConnorGraphAgent
@testable import ConnorGraphAppSupport

private func historyToolContext(toolCallID: String) -> AgentToolExecutionContext {
    AgentToolExecutionContext(
        runID: "history-run",
        sessionID: "history-session",
        groupID: "default",
        userPrompt: "分析杭州当时的环境",
        toolCallID: toolCallID,
        policyEngine: AgentPolicyEngine(permissionMode: .allowAll)
    )
}

private func seedHistoryStore(databaseURL: URL, includeWeather: Bool) async throws {
    let store = try await SQLiteEnvironmentStore.open(databaseURL: databaseURL)
    let region = try #require(AgentEnvironmentRegion.containing(latitude: 30.12345, longitude: 120.98765))
    let observedAt = try #require(ISO8601DateFormatter().date(from: "2026-07-01T00:00:00Z"))
    let regionID = try await store.upsertRegion(
        region,
        timeZoneIdentifier: "Asia/Shanghai",
        countryCode: "CN",
        administrativeArea: "Zhejiang",
        locality: "杭州",
        now: observedAt
    )
    if includeWeather {
        try await store.upsertWeatherPoint(EnvironmentWeatherPoint(
            regionID: regionID,
            observedAt: observedAt,
            dataKind: .currentObservation,
            provider: "Open-Meteo",
            temperatureCelsius: 28,
            precipitationMillimeters: 0.2,
            windSpeedKilometersPerHour: 8,
            sourceURL: "https://open-meteo.com/",
            fetchedAt: observedAt
        ))
    }
}

@Test func historyToolsHaveClosedSchemasAndQueryOnlyRecordedSnapshots() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let databaseURL = root.appendingPathComponent("environment.sqlite")
    try await seedHistoryStore(databaseURL: databaseURL, includeWeather: true)
    let service = EnvironmentHistoryService(databaseURL: databaseURL)
    let tool = EnvironmentHistoryQueryTool(service: service)
    #expect(tool.inputSchema.validationIssues(toolName: tool.name).isEmpty)
    #expect(tool.inputSchema.jsonObject["additionalProperties"] as? Bool == false)
    #expect(tool.permission == .readSession)

    let result = try await tool.execute(
        arguments: try AgentToolArguments(json: #"{"place":"杭州","start":"2026-07-01T00:00:00Z","end":"2026-07-01T00:00:00Z","categories":["weather"]}"#),
        context: historyToolContext(toolCallID: "query")
    )

    #expect(result.contentJSON?.contains("current_observation") == true)
    #expect(result.contentJSON?.contains("30.12345") == false)
    #expect(result.contentJSON?.contains("120.98765") == false)
    #expect(result.contentJSON?.contains("queryTimestamps") == true)
    #expect(result.contentJSON?.contains("not continuous coverage") == true)
    #expect(result.contentText.contains("Missing intervals were not reconstructed"))
}

@Test func historyCoverageDoesNotSynthesizeMissingMeasurements() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let databaseURL = root.appendingPathComponent("environment.sqlite")
    try await seedHistoryStore(databaseURL: databaseURL, includeWeather: false)
    let service = EnvironmentHistoryService(databaseURL: databaseURL)
    let tool = EnvironmentHistoryCoverageTool(service: service)
    let result = try await tool.execute(
        arguments: try AgentToolArguments(json: #"{"place":"杭州","start":"2026-07-01T00:00:00Z","end":"2026-07-01T01:00:00Z","categories":["weather"]}"#),
        context: historyToolContext(toolCallID: "coverage")
    )
    #expect(result.contentJSON?.contains("sampleCount") == false)
    #expect(result.contentText.contains("not fetched"))
}
