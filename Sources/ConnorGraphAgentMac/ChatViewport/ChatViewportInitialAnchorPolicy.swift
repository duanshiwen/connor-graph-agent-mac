import CoreGraphics

enum ChatViewportInitialAnchorDecision: Equatable {
    case wait
    case scrollToLatest
    case settleWithoutScroll
    case stop
}

struct ChatViewportInitialAnchorPolicy {
    static func decision(
        itemCount: Int,
        viewportHeight: CGFloat,
        contentHeight: CGFloat,
        distanceToBottom: CGFloat,
        bottomPinThreshold: CGFloat,
        isLoadingOlderItems: Bool,
        isPrependingOlderItems: Bool,
        isResolvingInitialAnchor: Bool,
        isPinnedToBottom: Bool
    ) -> ChatViewportInitialAnchorDecision {
        guard itemCount > 0 else { return .stop }
        guard !isLoadingOlderItems, !isPrependingOlderItems else { return .stop }
        guard isResolvingInitialAnchor || isPinnedToBottom else { return .stop }
        guard viewportHeight > 0, contentHeight > 0 else { return .wait }
        guard contentHeight > viewportHeight + 1 else { return .settleWithoutScroll }
        guard distanceToBottom > bottomPinThreshold else { return .settleWithoutScroll }
        return .scrollToLatest
    }
}
