import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Calendar Source Sync Engine Tests")
struct CalendarSourceSyncEngineTests {
    @Test func syncEngineDispatchesReadOnlyAccountToRegisteredConnector() async throws {
        let accountID = CalendarAccountID(rawValue: "calendar-account-caldav")
        let account = CalendarAccount(
            id: accountID,
            provider: .genericCalDAVCardDAV,
            sourceKind: .genericCalDAV,
            displayName: "Work CalDAV",
            configuration: CalendarSourceConfiguration(sourceKind: .genericCalDAV, authMode: .appPassword)
        )
        let connector = StubCalendarSourceConnector(kind: .genericCalDAV)
        let engine = CalendarSourceSyncEngine(connectors: [connector])

        let result = try await engine.sync(
            request: CalendarSourceSyncRequest(
                account: account,
                credential: "secret",
                runID: "run-calendar-sync"
            )
        )

        #expect(result.accountID == accountID)
        #expect(result.sourceKind == .genericCalDAV)
        #expect(result.insertedEvents == 2)
        #expect(result.updatedCollections == 1)
        #expect(result.diagnostics.isEmpty)
    }

    @Test func syncEnginePersistsSuccessfulSyncResultWhenRuntimeStoreIsProvided() async throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("calendar-engine-store-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("store.json")
        let store = FileBackedCalendarSourceRuntimeStore(storeURL: storeURL)
        let account = CalendarAccount(
            id: CalendarAccountID(rawValue: "calendar-account-caldav"),
            provider: .genericCalDAVCardDAV,
            sourceKind: .genericCalDAV,
            displayName: "Work CalDAV",
            configuration: CalendarSourceConfiguration(sourceKind: .genericCalDAV, authMode: .appPassword)
        )
        let engine = CalendarSourceSyncEngine(connectors: [StubCalendarSourceConnector(kind: .genericCalDAV, includeData: true)], runtimeStore: store)

        let result = try await engine.sync(request: CalendarSourceSyncRequest(account: account, credential: "secret", runID: "run-calendar-sync"))
        let snapshot = try await store.loadSnapshot()

        #expect(result.events.count == 1)
        #expect(snapshot.accounts.first?.id == account.id)
        #expect(snapshot.collections.first?.accountID == account.id)
        #expect(snapshot.events.first?.title == "Synced event")
        #expect(snapshot.syncStates.first?.lastSuccessfulSyncAt != nil)
    }

    @Test func syncEnginePersistsFailureStateForUnsupportedConnector() async throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("calendar-engine-failure-store-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("store.json")
        let store = FileBackedCalendarSourceRuntimeStore(storeURL: storeURL)
        let account = CalendarAccount(
            id: CalendarAccountID(rawValue: "calendar-account-google"),
            provider: .google,
            sourceKind: .googleCalendar,
            displayName: "Google Calendar",
            configuration: CalendarSourceConfiguration(sourceKind: .googleCalendar, authMode: .oauth2)
        )
        let engine = CalendarSourceSyncEngine(connectors: [], runtimeStore: store)

        var rejected = false
        do {
            _ = try await engine.sync(request: CalendarSourceSyncRequest(account: account, credential: nil, runID: nil))
        } catch CalendarSourceSyncError.unsupportedSourceKind(.googleCalendar) {
            rejected = true
        } catch {}
        let snapshot = try await store.loadSnapshot()

        #expect(rejected)
        #expect(snapshot.syncStates.first?.accountID == account.id)
        #expect(snapshot.syncStates.first?.failureCount == 1)
        #expect(snapshot.syncStates.first?.nextRetryAt != nil)
        #expect(snapshot.diagnostics.first?.severity == .error)
        #expect(snapshot.diagnostics.first?.code == "unsupportedSourceKind")
    }

    @Test func syncEngineRejectsUnsupportedConnector() async {
        let account = CalendarAccount(
            id: CalendarAccountID(rawValue: "calendar-account-google"),
            provider: .google,
            sourceKind: .googleCalendar,
            displayName: "Google Calendar",
            configuration: CalendarSourceConfiguration(sourceKind: .googleCalendar, authMode: .oauth2)
        )
        let engine = CalendarSourceSyncEngine(connectors: [])

        var rejected = false
        do {
            _ = try await engine.sync(request: CalendarSourceSyncRequest(account: account, credential: nil, runID: nil))
        } catch CalendarSourceSyncError.unsupportedSourceKind(.googleCalendar) {
            rejected = true
        } catch {}

        #expect(rejected)
    }
}

private struct StubCalendarSourceConnector: CalendarSourceConnector {
    var kind: CalendarSourceKind
    var includeData: Bool = false

    func validate(configuration: CalendarSourceConfiguration, credential: String?) async throws -> CalendarSourceValidationResult {
        CalendarSourceValidationResult(sourceKind: kind, status: .ready, summary: "Stub ready")
    }

    func discoverCalendars(configuration: CalendarSourceConfiguration, credential: String?) async throws -> [DiscoveredCalendarCollection] {
        [DiscoveredCalendarCollection(id: CalendarID(rawValue: "calendar-work"), displayName: "Work")]
    }

    func sync(request: CalendarSourceSyncRequest) async throws -> CalendarSourceSyncResult {
        CalendarSourceSyncResult(
            accountID: request.account.id,
            sourceKind: kind,
            insertedEvents: 2,
            updatedEvents: 0,
            deletedEvents: 0,
            unchangedEvents: 0,
            updatedCollections: 1,
            diagnostics: [],
            collections: includeData ? [CalendarCollection(id: CalendarID(rawValue: "calendar-work"), accountID: request.account.id, displayName: "Work", isReadOnly: true)] : [],
            events: includeData ? [CalendarEvent(id: CalendarEventID(rawValue: "event-synced"), calendarID: CalendarID(rawValue: "calendar-work"), title: "Synced event", start: CalendarEventDateTime(date: Date(timeIntervalSince1970: 1)), end: CalendarEventDateTime(date: Date(timeIntervalSince1970: 2)))] : []
        )
    }
}
