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
            diagnostics: []
        )
    }
}
