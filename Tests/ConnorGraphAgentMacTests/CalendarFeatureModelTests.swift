import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport
@testable import ConnorGraphAgentMac

@Suite("Calendar Feature Model Tests")
@MainActor
struct CalendarFeatureModelTests {
    @Test func reloadMergesRuntimeOverLegacyAndRepairsInvalidSelection() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let legacyAccount = makeAccount(id: "account-shared", name: "Legacy")
        let runtimeAccount = makeAccount(id: "account-shared", name: "Runtime")
        let early = makeEvent(id: "event-early", calendarID: "calendar-shared", title: "Early", start: 100)
        let late = makeEvent(id: "event-late", calendarID: "calendar-shared", title: "Late", start: 200)
        try await fixture.legacy.saveSnapshot(.init(
            accounts: [legacyAccount],
            collections: [makeCollection(id: "calendar-shared", accountID: legacyAccount.id, name: "Legacy")],
            events: [late]
        ))
        try await fixture.runtime.saveSnapshot(.init(
            accounts: [runtimeAccount],
            collections: [makeCollection(id: "calendar-shared", accountID: runtimeAccount.id, name: "Runtime")],
            events: [early]
        ))
        let model = fixture.model()
        model.selectedEventID = CalendarEventID(rawValue: "missing")

        await model.reload()

        #expect(model.accounts.map(\.displayName) == ["Runtime"])
        #expect(model.collections.map(\.displayName) == ["Runtime"])
        #expect(model.events.map(\.id.rawValue) == ["event-early", "event-late"])
        #expect(model.presentation.eventCount == 2)
        #expect(model.selectedEventID == early.id)
        #expect(model.errorMessage == nil)
    }

    @Test func successfulReloadPreservesNilSelectionAndOnlyReportsDomainSuccess() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        try await fixture.legacy.saveSnapshot(.init(events: [makeEvent(id: "event", calendarID: "calendar", title: "Event")]))
        let model = fixture.model()
        var events: [CalendarFeatureModel.Event] = []
        model.onEvent = { events.append($0) }

        await model.reload()

        #expect(model.selectedEventID == nil)
        #expect(events.contains { if case .operationSucceeded = $0 { true } else { false } })
        #expect(events.contains { if case .presentationChanged = $0 { true } else { false } })
    }

    @Test func systemSyncPersistsBothStoresAndPreservesRuntimeMetadata() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let retainedAccount = makeAccount(id: "remote", name: "Remote")
        let audit = CalendarMutationAuditRecord(
            runID: "run", sessionID: "session", accountID: retainedAccount.id,
            calendarID: CalendarID(rawValue: "remote-calendar"), eventID: nil,
            sourceKind: .genericCalDAV, operation: .create, status: .confirmed
        )
        try await fixture.runtime.saveSnapshot(.init(
            accounts: [retainedAccount],
            syncStates: [.init(accountID: retainedAccount.id, sourceKind: .genericCalDAV)],
            diagnostics: [.init(accountID: retainedAccount.id, severity: .info, code: "kept", message: "Kept")],
            mutationAudits: [audit]
        ))
        let systemAccount = makeAccount(id: CalendarEventKitAdapter.systemAccountID.rawValue, name: "System", sourceKind: .macOSEventKit)
        let systemCollection = makeCollection(id: "system-calendar", accountID: systemAccount.id, name: "System")
        let systemEvent = makeEvent(id: "system-event", calendarID: systemCollection.id.rawValue, title: "System Event")
        let model = fixture.model(systemSnapshotLoader: {
            CalendarEventKitSnapshot(accounts: [systemAccount], collections: [systemCollection], events: [systemEvent])
        })
        var sourceChanges = 0
        model.sourceSetChanged = { sourceChanges += 1 }
        await model.reload()

        let succeeded = await model.syncSystemCalendarNow()
        let runtime = try await fixture.runtime.loadSnapshot()
        let legacy = try await fixture.legacy.loadSnapshot()

        #expect(succeeded)
        #expect(model.syncMessage == "已同步本机日历：1 个日历，1 个日程")
        #expect(sourceChanges == 1)
        #expect(runtime.accounts.map(\.id).contains(systemAccount.id))
        #expect(runtime.syncStates.count == 1)
        #expect(runtime.diagnostics.map(\.code) == ["kept"])
        #expect(runtime.mutationAudits.map(\.id) == [audit.id])
        #expect(legacy.events.map(\.id) == [systemEvent.id])
    }

    @Test func systemSyncFailureResetsLoadingAndReportsExactLocalizedMessage() async throws {
        struct FixtureError: LocalizedError { var errorDescription: String? { "Calendar permission denied" } }
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let model = fixture.model(systemSnapshotLoader: { throw FixtureError() })
        var failure: String?
        model.onEvent = { event in if case let .operationFailed(message) = event { failure = message } }

        let succeeded = await model.syncSystemCalendarNow()

        #expect(!succeeded)
        #expect(!model.isSyncingSystemCalendar)
        #expect(model.syncMessage == "Calendar permission denied")
        #expect(model.errorMessage == "Calendar permission denied")
        #expect(failure == "Calendar permission denied")
    }

    @Test func deleteRemovesOnlyAccountScopedPresentationAndNotifiesReconcile() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let removed = makeAccount(id: "remove", name: "Remove")
        let kept = makeAccount(id: "keep", name: "Keep")
        let removedCollection = makeCollection(id: "remove-calendar", accountID: removed.id, name: "Remove")
        let keptCollection = makeCollection(id: "keep-calendar", accountID: kept.id, name: "Keep")
        let removedEvent = makeEvent(id: "remove-event", calendarID: removedCollection.id.rawValue, title: "Remove")
        let keptEvent = makeEvent(id: "keep-event", calendarID: keptCollection.id.rawValue, title: "Keep")
        try await fixture.runtime.saveSnapshot(.init(
            accounts: [removed, kept], collections: [removedCollection, keptCollection], events: [removedEvent, keptEvent]
        ))
        let model = fixture.model()
        await model.reload()
        model.selectedEventID = removedEvent.id
        var sourceChanges = 0
        model.sourceSetChanged = { sourceChanges += 1 }

        model.deleteSource(removed)
        await model.waitForPendingOperations()

        #expect(model.accounts.map(\.id) == [kept.id])
        #expect(model.events.map(\.id) == [keptEvent.id])
        #expect(model.selectedEventID == nil)
        #expect(model.syncMessage == "已移除日历源：Remove")
        #expect(sourceChanges == 1)
        let persisted = try await fixture.runtime.loadSnapshot()
        #expect(persisted.accounts.map(\.id) == [kept.id])
    }

    @Test func scheduledRefreshUsesInjectedSynchronizerAndMaintainsSummary() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let account = makeAccount(id: "remote", name: "Remote", sourceKind: .icsSubscription)
        try await fixture.runtime.saveSnapshot(.init(accounts: [account]))
        let collection = makeCollection(id: "remote-calendar", accountID: account.id, name: "Remote")
        let event = makeEvent(id: "remote-event", calendarID: collection.id.rawValue, title: "Remote")
        let model = fixture.model(remoteAccountSynchronizer: { account, _, _, store in
            let result = CalendarSourceSyncResult(
                accountID: account.id, sourceKind: account.sourceKind,
                collections: [collection], events: [event]
            )
            try await store.applySyncResult(result, account: account)
            return result
        })
        await model.reload()

        let summary = await model.refreshForScheduledTask(sourceInstanceID: account.id.rawValue, runID: "run")

        #expect(summary == "Calendar refreshed account remote; synced 1 events across 1 calendars")
        #expect(model.events.map(\.id) == [event.id])
        #expect(await model.refreshForScheduledTask(sourceInstanceID: "missing", runID: nil) == "Calendar account not found: missing")
    }

    @Test func shutdownPreventsSystemSnapshotApplication() async throws {
        actor Gate {
            var continuation: CheckedContinuation<Void, Never>?
            func wait() async { await withCheckedContinuation { continuation = $0 } }
            func release() { continuation?.resume(); continuation = nil }
        }
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let gate = Gate()
        let event = makeEvent(id: "late", calendarID: "calendar", title: "Late")
        let model = fixture.model(systemSnapshotLoader: {
            await gate.wait()
            return CalendarEventKitSnapshot(accounts: [], collections: [], events: [event])
        })
        let task = Task { @MainActor in await model.syncSystemCalendarNow() }
        await Task.yield()
        model.shutdown()
        await gate.release()

        #expect(await task.value == false)
        #expect(model.events.isEmpty)
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-calendar-feature-model-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return Fixture(
            root: root,
            legacy: FileBackedCalendarSourceStore(storeURL: root.appendingPathComponent("legacy.json")),
            runtime: FileBackedCalendarSourceRuntimeStore(storeURL: root.appendingPathComponent("runtime.json"))
        )
    }

    private func makeAccount(
        id: String,
        name: String,
        sourceKind: CalendarSourceKind = .icsSubscription
    ) -> CalendarAccount {
        CalendarAccount(
            id: CalendarAccountID(rawValue: id),
            provider: sourceKind == .macOSEventKit ? .localFixture : .genericCalDAVCardDAV,
            sourceKind: sourceKind,
            displayName: name,
            configuration: CalendarSourceConfiguration(sourceKind: sourceKind)
        )
    }

    private func makeCollection(id: String, accountID: CalendarAccountID, name: String) -> CalendarCollection {
        CalendarCollection(id: CalendarID(rawValue: id), accountID: accountID, displayName: name)
    }

    private func makeEvent(
        id: String,
        calendarID: String,
        title: String,
        start: TimeInterval = 1_000
    ) -> CalendarEvent {
        CalendarEvent(
            id: CalendarEventID(rawValue: id),
            calendarID: CalendarID(rawValue: calendarID),
            title: title,
            start: CalendarEventDateTime(date: Date(timeIntervalSince1970: start)),
            end: CalendarEventDateTime(date: Date(timeIntervalSince1970: start + 3_600))
        )
    }

    private struct Fixture {
        var root: URL
        var legacy: FileBackedCalendarSourceStore
        var runtime: FileBackedCalendarSourceRuntimeStore

        @MainActor
        func model(
            systemSnapshotLoader: @escaping CalendarFeatureModel.SystemSnapshotLoader = {
                CalendarEventKitSnapshot(accounts: [], collections: [], events: [])
            },
            remoteAccountSynchronizer: @escaping CalendarFeatureModel.RemoteAccountSynchronizer = { account, _, _, _ in
                CalendarSourceSyncResult(accountID: account.id, sourceKind: account.sourceKind)
            }
        ) -> CalendarFeatureModel {
            CalendarFeatureModel(
                legacyStore: legacy,
                runtimeStore: runtime,
                systemSnapshotLoader: systemSnapshotLoader,
                remoteAccountSynchronizer: remoteAccountSynchronizer
            )
        }

        func cleanup() { try? FileManager.default.removeItem(at: root) }
    }
}
