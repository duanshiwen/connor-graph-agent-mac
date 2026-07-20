import Foundation
import Testing
import ConnorGraphAppSupport

@Suite("Browser Tab Snapshot Restoration Tests")
struct BrowserTabSnapshotRestorationTests {
    @Test func decodesLegacyBrowserTabSnapshotWithoutRestorationFields() throws {
        let tabID = UUID()
        let json = """
        {
          "id": "\(tabID.uuidString)",
          "initialURLString": "https://example.com",
          "title": "Example",
          "currentURLString": "https://example.com/page",
          "isLoading": false,
          "canGoBack": true,
          "canGoForward": false
        }
        """.data(using: .utf8)!

        let snapshot = try JSONDecoder().decode(AppBrowserTabSnapshot.self, from: json)

        #expect(snapshot.id == tabID)
        #expect(snapshot.scrollX == nil)
        #expect(snapshot.scrollY == nil)
        #expect(snapshot.viewportWidth == nil)
        #expect(snapshot.viewportHeight == nil)
        #expect(snapshot.contentFingerprint == nil)
        #expect(snapshot.focusedElementHint == nil)
        #expect(snapshot.formDrafts == nil)
        #expect(snapshot.restorationStatus == nil)
        #expect(snapshot.localFileReadAccessPath == nil)
    }

    @Test func roundTripsRestorationMetadata() throws {
        let tabID = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = AppBrowserTabSnapshot(
            id: tabID,
            initialURLString: "https://example.com",
            title: "Example",
            currentURLString: "https://example.com/article",
            isLoading: false,
            canGoBack: true,
            canGoForward: false,
            lastAccessedAt: now,
            lastVisibleAt: now.addingTimeInterval(-10),
            scrollX: 12,
            scrollY: 3456,
            viewportWidth: 1280,
            viewportHeight: 720,
            contentFingerprint: "fingerprint-1",
            focusedElementHint: "textarea[name=q]",
            formDrafts: [
                AppBrowserFormDraftSnapshot(
                    selectorHint: "textarea[name=q]",
                    name: "q",
                    type: "textarea",
                    valuePreview: "hello",
                    valueHash: "hash-hello"
                )
            ],
            restorationStatus: .evicted,
            localFileReadAccessPath: "/tmp/workspace"
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(AppBrowserTabSnapshot.self, from: data)

        #expect(decoded == snapshot)
        #expect(decoded.restoredURLString == "https://example.com/article")
        #expect(decoded.localFileReadAccessPath == "/tmp/workspace")
    }
}
