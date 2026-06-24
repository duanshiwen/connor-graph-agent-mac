import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Calendar EventKit Connector Tests")
struct CalendarEventKitConnectorTests {
    @Test func eventKitConnectorSyncsInjectedSnapshotAsReadOnlyResult() async throws {
        let accountID = CalendarEventKitAdapter.systemAccountID
        let calendarID = CalendarID(rawValue: "calendar-system-work")
        let snapshot = CalendarEventKitSnapshot(
            accounts: [
                CalendarAccount(
                    id: accountID,
                    provider: .localFixture,
                    sourceKind: .macOSEventKit,
                    displayName: "本机日历",
                    configuration: CalendarSourceConfiguration(sourceKind: .macOSEventKit)
                )
            ],
            collections: [CalendarCollection(id: calendarID, accountID: accountID, displayName: "Work", source: "eventkit")],
            events: [
                CalendarEvent(
                    id: CalendarEventID(rawValue: "event-1"),
                    calendarID: calendarID,
                    title: "产品讨论",
                    start: CalendarEventDateTime(date: Date(timeIntervalSince1970: 1_800_000_000)),
                    end: CalendarEventDateTime(date: Date(timeIntervalSince1970: 1_800_003_600))
                )
            ]
        )
        let connector = CalendarEventKitConnector(fetchSnapshot: { snapshot })
        let account = snapshot.accounts[0]

        let result = try await connector.sync(request: CalendarSourceSyncRequest(account: account, runID: "run-eventkit"))

        #expect(result.accountID == accountID)
        #expect(result.sourceKind == .macOSEventKit)
        #expect(result.updatedCollections == 1)
        #expect(result.insertedEvents == 1)
        #expect(result.diagnostics.isEmpty)
    }
}
