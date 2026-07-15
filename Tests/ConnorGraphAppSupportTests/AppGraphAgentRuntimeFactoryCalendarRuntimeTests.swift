import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore
import ConnorGraphStore

private final class FactoryCalendarSettingsStore: LLMSettingsStore, @unchecked Sendable {
    private var values: [String: String] = [:]
    func string(forKey key: String) -> String? { values[key] }
    func set(_ value: String, forKey key: String) { values[key] = value }
}

private final class FactoryCalendarCredentialStore: CredentialStore, @unchecked Sendable {
    private var values: [String: String] = [:]
    func saveSecret(_ secret: String, service: String, account: String) throws { values["\(service):\(account)"] = secret }
    func readSecret(service: String, account: String) throws -> String? { values["\(service):\(account)"] }
    func deleteSecret(service: String, account: String) throws { values["\(service):\(account)"] = nil }
}

@Test func agentRuntimeFactoryUsesInjectedCalendarRuntimeStoreAsSingleOwner() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("connor-factory-calendar-runtime-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let storagePaths = AppStoragePaths(applicationSupportDirectory: root)
    try storagePaths.ensureDirectoryHierarchy()
    let graphStore = try SQLiteGraphKernelStore(path: root.appendingPathComponent("graph.sqlite").path)
    try graphStore.migrate()
    let settings = AppLLMSettingsRepository(
        settingsStore: FactoryCalendarSettingsStore(),
        credentialStore: FactoryCalendarCredentialStore()
    )
    let injectedURL = root.appendingPathComponent("injected-calendar-runtime.json")
    let runtimeStore = FileBackedCalendarSourceRuntimeStore(storeURL: injectedURL)
    let accountID = CalendarAccountID(rawValue: "injected-account")
    let calendarID = CalendarID(rawValue: "injected-calendar")
    let event = CalendarEvent(
        id: CalendarEventID(rawValue: "injected-event"),
        calendarID: calendarID,
        title: "Injected Calendar Fixture",
        start: CalendarEventDateTime(date: Date(timeIntervalSince1970: 1_000)),
        end: CalendarEventDateTime(date: Date(timeIntervalSince1970: 4_600))
    )
    try await runtimeStore.saveSnapshot(.init(
        accounts: [CalendarAccount(id: accountID, provider: .genericCalDAVCardDAV, sourceKind: .icsSubscription, displayName: "Injected")],
        collections: [CalendarCollection(id: calendarID, accountID: accountID, displayName: "Injected", isReadOnly: true)],
        events: [event]
    ))
    let factory = AppGraphAgentRuntimeFactory(
        store: graphStore,
        settingsRepository: settings,
        storagePaths: storagePaths,
        calendarRuntimeStore: runtimeStore,
        calendarCredentialStore: AppCalendarCredentialStore(credentialStore: FactoryCalendarCredentialStore())
    )
    let controller = factory.makeAgentLoopController(permissionMode: .allowAll)

    #expect(controller.toolRegistry.definitions.contains { $0.name == "calendar_read" })
    let result = try await controller.toolRegistry.execute(
        AgentToolCall(name: "calendar_read", argumentsJSON: #"{"operation":"list_events"}"#),
        context: AgentToolExecutionContext(
            runID: "calendar-runtime-run",
            sessionID: "calendar-runtime-session",
            groupID: "default",
            userPrompt: "list events",
            toolCallID: "calendar-read",
            policyEngine: AgentPolicyEngine(permissionMode: .allowAll)
        )
    )

    #expect(result.contentText.contains("Injected Calendar Fixture"))
    #expect(result.contentText.contains("injected-event"))
    let productionFallbackStore = FileBackedCalendarSourceRuntimeStore(storagePaths: storagePaths)
    #expect(try await productionFallbackStore.loadSnapshot().events.isEmpty)
}
