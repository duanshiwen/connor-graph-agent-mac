import Foundation
import Testing
import ConnorGraphStore
import ConnorGraphAppSupport

@Test func nativeSourceEventBridgeIngestsMailCalendarRSSBrowserAttachmentAndMediaEvents() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryNativeSourceBridgeDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let bridge = AppMemoryOSNativeSourceEventBridge(facade: facade)
    let now = Date(timeIntervalSince1970: 11_000)

    try bridge.ingestMailMessage(id: "mail-1", subject: "Project update", bodyPreview: "Memory OS update", accountID: "mail-account", occurredAt: now)
    try bridge.ingestCalendarEvent(id: "calendar-1", title: "Design review", notes: "Memory OS review", accountID: "calendar-account", occurredAt: now)
    try bridge.ingestRSSItem(id: "rss-1", title: "Agent OS article", snippet: "Memory architecture", sourceID: "rss-source", occurredAt: now)
    try bridge.ingestBrowserHistoryEvent(id: "browser-1", title: "Connor docs", urlString: "https://example.com/connor", occurredAt: now)
    try bridge.ingestAttachmentText(id: "attachment-1", displayName: "notes.txt", extractedText: "Memory notes", sessionID: "session", occurredAt: now)
    try bridge.ingestMediaTranscript(id: "media-1", title: "Meeting transcript", transcript: "We discussed Memory OS", sessionID: "session", occurredAt: now)

    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l0_provenance_objects;").first?.first == "6")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l1_capture_events;").first?.first == "6")
    let sourceKinds = try store.query(sql: "SELECT metadata_json FROM memory_l1_capture_events ORDER BY occurred_at ASC;")
        .compactMap { row -> String? in row.first }
        .joined(separator: "\n")
    #expect(sourceKinds.contains("mail"))
    #expect(sourceKinds.contains("calendar"))
    #expect(sourceKinds.contains("rss"))
    #expect(sourceKinds.contains("browser_history"))
    #expect(sourceKinds.contains("attachment"))
    #expect(sourceKinds.contains("media_transcription"))
}

private func temporaryNativeSourceBridgeDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("native-source-memory-bridge-\(UUID().uuidString).sqlite")
}
