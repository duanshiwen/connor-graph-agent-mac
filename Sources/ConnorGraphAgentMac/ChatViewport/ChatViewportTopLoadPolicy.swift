import Foundation

struct ChatViewportTopLoadPolicy {
    static func shouldReevaluateAfterInitialAnchor(
        viewportHeight: Double,
        contentHeight: Double
    ) -> Bool {
        viewportHeight > 0 && contentHeight <= viewportHeight + 1
    }

    static func shouldRequestOlderItems(
        hasOlderItems: Bool,
        isLoadingOlderItems: Bool,
        didRequestOlderItemsForCurrentTopReach: Bool,
        viewportHeight: Double,
        distanceToTop: Double,
        topLoadTriggerOffset: Double,
        isResolvingInitialAnchor: Bool
    ) -> Bool {
        hasOlderItems
            && !isLoadingOlderItems
            && !didRequestOlderItemsForCurrentTopReach
            && viewportHeight > 0
            && distanceToTop <= topLoadTriggerOffset
            && !isResolvingInitialAnchor
    }

    static func shouldResetTopReachRequest(
        distanceToTop: Double,
        topLoadTriggerOffset: Double
    ) -> Bool {
        distanceToTop > topLoadTriggerOffset * 2
    }
}
