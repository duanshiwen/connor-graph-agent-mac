import CoreGraphics
import Testing
import ConnorGraphAppSupport

@Suite("Browser Selection Popover Layout Tests")
struct BrowserSelectionPopoverLayoutTests {
    @Test func flipsAboveWhenSelectionIsNearBottom() {
        let calculator = BrowserSelectionPopoverLayoutCalculator()

        let layout = calculator.layout(
            anchorRect: AppBrowserSelectionRect(x: 260, y: 520, width: 80, height: 20),
            containerSize: CGSize(width: 800, height: 600),
            preferredSize: CGSize(width: 420, height: 320)
        )

        #expect(layout.placement == .above)
        #expect(layout.frame.maxY <= 600 - 14 + 0.001)
        #expect(layout.frame.minY >= 14 - 0.001)
    }

    @Test func shiftsLeftWhenSelectionIsNearRightEdge() {
        let calculator = BrowserSelectionPopoverLayoutCalculator()

        let layout = calculator.layout(
            anchorRect: AppBrowserSelectionRect(x: 760, y: 120, width: 24, height: 18),
            containerSize: CGSize(width: 800, height: 600),
            preferredSize: CGSize(width: 420, height: 300)
        )

        #expect(layout.frame.maxX <= 800 - 14 + 0.001)
        #expect(layout.frame.minX >= 14 - 0.001)
    }

    @Test func shrinksWidthInsideSmallContainer() {
        let calculator = BrowserSelectionPopoverLayoutCalculator()

        let layout = calculator.layout(
            anchorRect: AppBrowserSelectionRect(x: 160, y: 120, width: 40, height: 20),
            containerSize: CGSize(width: 320, height: 560),
            preferredSize: CGSize(width: 420, height: 300)
        )

        #expect(layout.width == 292)
        #expect(layout.frame.minX >= 14 - 0.001)
        #expect(layout.frame.maxX <= 320 - 14 + 0.001)
    }

    @Test func capsHeightWhenPreferredHeightExceedsAvailableSpace() {
        let calculator = BrowserSelectionPopoverLayoutCalculator()

        let layout = calculator.layout(
            anchorRect: AppBrowserSelectionRect(x: 240, y: 250, width: 80, height: 20),
            containerSize: CGSize(width: 700, height: 500),
            preferredSize: CGSize(width: 420, height: 720)
        )

        #expect(layout.maxHeight < 720)
        #expect(layout.frame.minY >= 14 - 0.001)
        #expect(layout.frame.maxY <= 500 - 14 + 0.001)
    }
}
