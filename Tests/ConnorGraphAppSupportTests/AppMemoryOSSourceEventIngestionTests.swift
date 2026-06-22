import Foundation
import Testing
import ConnorGraphAppSupport
import ConnorGraphStore

@Test func appMemoryOSFacadeIngestsSourceEventsIntoL0L1() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSSourceEventDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let now = Date(timeIntervalSince1970: 7_000)

    let result = try facade.ingestSourceEvent(
        sourceID: "mail:message-1",
        title: "Mail summary",
        content: "The email says the meeting moved to Friday.",
        occurredAt: now,
        sourceKind: "mail",
        accountID: "account-1",
        metadata: ["message_id": "message-1"]
    )

    #expect(result.provenanceObject?.sourceType.rawValue == "source_event")
    #expect(result.provenanceObject?.sourceID == "mail:message-1")
    #expect(result.captureEvent?.eventType == "source_event")
    #expect(result.captureEvent?.metadata["source_kind"] == "mail")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l0_provenance_objects;").first?.first == "1")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l1_capture_events;").first?.first == "1")
}

private func temporaryAppMemoryOSSourceEventDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("app-memory-os-source-event-\(UUID().uuidString).sqlite")
}
