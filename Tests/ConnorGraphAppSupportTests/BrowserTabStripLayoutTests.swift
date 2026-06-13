import Testing
import ConnorGraphAppSupport

@Suite("Browser Tab Strip Layout Tests")
struct BrowserTabStripLayoutTests {
    @Test func keepsPreferredWidthWhenTabsFit() {
        let layout = BrowserTabStripLayoutCalculator().layout(tabCount: 3, availableWidth: 520)

        #expect(layout.tabWidth == 150)
        #expect(layout.requiresHorizontalScroll == false)
    }

    @Test func shrinksTabsBeforeScrolling() {
        let layout = BrowserTabStripLayoutCalculator().layout(tabCount: 6, availableWidth: 620)

        #expect(layout.tabWidth < 150)
        #expect(layout.tabWidth >= 86)
        #expect(layout.requiresHorizontalScroll == false)
    }

    @Test func scrollsOnlyAfterMinimumWidthCannotFit() {
        let layout = BrowserTabStripLayoutCalculator().layout(tabCount: 10, availableWidth: 520)

        #expect(layout.tabWidth == 86)
        #expect(layout.requiresHorizontalScroll == true)
    }

    @Test func emptyTabStripUsesPreferredWidthWithoutScroll() {
        let layout = BrowserTabStripLayoutCalculator().layout(tabCount: 0, availableWidth: 120)

        #expect(layout.tabWidth == 150)
        #expect(layout.requiresHorizontalScroll == false)
    }
}
