import Foundation

struct ChatViewportTopLoadPolicy {
    static func didFinishLoadingOlderItems(
        wasLoadingOlderItems: Bool,
        isLoadingOlderItems: Bool
    ) -> Bool {
        wasLoadingOlderItems && !isLoadingOlderItems
    }

    static func didFinishResolvingInitialAnchor(
        wasResolvingInitialAnchor: Bool,
        isResolvingInitialAnchor: Bool
    ) -> Bool {
        wasResolvingInitialAnchor && !isResolvingInitialAnchor
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
