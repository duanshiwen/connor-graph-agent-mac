import Testing
@testable import ConnorGraphAgentMac

@Suite("Zoomable image preview controls")
struct ZoomableImagePreviewControlPresentationTests {
    @Test func zoomControlsUseDistinctCompactSymbols() {
        #expect(ZoomableImagePreviewControlPresentation.zoomOutSystemImage == "minus")
        #expect(ZoomableImagePreviewControlPresentation.zoomInSystemImage == "plus")
        #expect(ZoomableImagePreviewControlPresentation.resetSystemImage == "arrow.counterclockwise")
        #expect(ZoomableImagePreviewControlPresentation.resetSystemImage.contains("magnifyingglass") == false)
    }
}
