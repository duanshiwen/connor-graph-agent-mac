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
}
