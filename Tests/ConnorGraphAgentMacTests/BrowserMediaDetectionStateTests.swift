import Foundation
import Testing
import ConnorGraphCore
@testable import ConnorGraphAgentMac

@Suite("Browser Media Detection State Tests")
struct BrowserMediaDetectionStateTests {
    @Test func browserTabStateStoresMediaSnapshotOutsidePersistentSnapshot() {
        var tab = BrowserTabState(initialURLString: "https://example.com/video")
        let media = BrowserMediaSourceSnapshot(
            pageURLString: "https://example.com/video",
            pageTitle: "Video",
            mediaElements: [BrowserDetectedMediaElement(id: "video-0", kind: "video", sourceURLString: "https://cdn.example.com/video.mp4")]
        )

        tab.mediaSnapshot = media

        #expect(tab.mediaSnapshot?.hasDetectedMedia == true)
        #expect(tab.mediaSnapshot?.mediaElements.first?.kind == "video")
        #expect(tab.snapshot.currentURLString == "https://example.com/video")
    }

    @Test func mediaBridgeDecodesJavaScriptISODateWithFractionalSeconds() throws {
        let json = """
        {
          "pageURLString": "https://www.youtube.com/watch?v=abc123",
          "pageTitle": "YouTube Video",
          "detectedAt": "2026-06-20T03:17:31.123Z",
          "mediaElements": [
            {
              "id": "video-0",
              "kind": "video",
              "sourceURLString": null,
              "durationSeconds": 120.5,
              "currentTimeSeconds": 3.0,
              "isPaused": false,
              "isMuted": false,
              "readyState": 4
            }
          ],
          "openGraphMedia": [],
          "canonicalURLString": "https://www.youtube.com/watch?v=abc123",
          "userVisibleSelection": null
        }
        """

        let snapshot = try #require(BrowserMediaSnapshotDecoder.decode(from: Data(json.utf8)))

        #expect(snapshot.hasDetectedMedia)
        #expect(snapshot.pageURLString.contains("youtube.com"))
        #expect(snapshot.mediaElements.first?.kind == "video")
    }
}
