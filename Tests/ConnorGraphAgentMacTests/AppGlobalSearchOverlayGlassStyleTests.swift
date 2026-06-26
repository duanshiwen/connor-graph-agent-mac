import Testing
@testable import ConnorGraphAgentMac

struct AppGlobalSearchOverlayGlassStyleTests {
    @Test func rowHighlightOpacityIsStrongEnoughForDarkBackdrops() {
        #expect(GlobalSearchOverlayGlassStyle.selectedAccentOpacity >= 0.18)
        #expect(GlobalSearchOverlayGlassStyle.hoverAccentOpacity >= 0.10)
        #expect(GlobalSearchOverlayGlassStyle.selectedAccentOpacity > GlobalSearchOverlayGlassStyle.hoverAccentOpacity)
    }

    @Test func glassShadowSeparatesOverlayFromDarkBackdrops() {
        #expect(GlobalSearchOverlayGlassStyle.outerShadowOpacity >= 0.20)
        #expect(GlobalSearchOverlayGlassStyle.outerShadowRadius >= 24)
        #expect(GlobalSearchOverlayGlassStyle.outerShadowY >= 12)
    }

    @Test func glassEdgeTreatmentKeepsTransparentMaterialApproach() {
        #expect(GlobalSearchOverlayGlassStyle.edgeHighlightOpacityLight > GlobalSearchOverlayGlassStyle.edgeHighlightOpacityDark)
        #expect(GlobalSearchOverlayGlassStyle.edgeLowlightOpacityDark > GlobalSearchOverlayGlassStyle.edgeLowlightOpacityLight)
        #expect(GlobalSearchOverlayGlassStyle.chipStrokeOpacity >= 0.10)
    }
}
