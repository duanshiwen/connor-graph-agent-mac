import Foundation

public enum AgentChatCollapseScrollSchedule {
    public static let decisionDelays: [TimeInterval] = [0.05, 0.2, 0.35, 0.65]
}

public struct AgentChatCollapseScrollPolicy: Sendable {
    public enum Decision: Equatable, Sendable {
        case scrollToTop
        case scrollToBottom
        case doNotScroll
    }

    public var overflowTolerance: Double
    public var veryTallCollapsePreviousViewportRatio: Double
    public var veryTallCollapseShrinkViewportRatio: Double

    public init(
        overflowTolerance: Double = 1,
        veryTallCollapsePreviousViewportRatio: Double = 3,
        veryTallCollapseShrinkViewportRatio: Double = 2
    ) {
        self.overflowTolerance = overflowTolerance
        self.veryTallCollapsePreviousViewportRatio = veryTallCollapsePreviousViewportRatio
        self.veryTallCollapseShrinkViewportRatio = veryTallCollapseShrinkViewportRatio
    }

    public func decisionAfterAssistantMessageCollapse(
        contentHeight: Double,
        viewportHeight: Double
    ) -> Decision {
        guard hasValidDimensions(contentHeight: contentHeight, viewportHeight: viewportHeight) else {
            return .doNotScroll
        }

        return contentHeight > viewportHeight + overflowTolerance ? .scrollToBottom : .scrollToTop
    }

    public func decisionAfterSessionSwitch(
        contentHeight: Double,
        viewportHeight: Double
    ) -> Decision {
        guard hasValidDimensions(contentHeight: contentHeight, viewportHeight: viewportHeight) else {
            return .doNotScroll
        }

        return contentHeight > viewportHeight + overflowTolerance ? .scrollToBottom : .doNotScroll
    }

    public func shouldResetScrollIdentityAfterCollapse(
        previousContentHeight: Double,
        newContentHeight: Double,
        viewportHeight: Double
    ) -> Bool {
        guard hasValidDimensions(contentHeight: previousContentHeight, viewportHeight: viewportHeight),
              hasValidDimensions(contentHeight: newContentHeight, viewportHeight: viewportHeight)
        else { return false }

        let wasOverflowing = previousContentHeight > viewportHeight + overflowTolerance
        let nowFitsViewport = newContentHeight <= viewportHeight + overflowTolerance
        if wasOverflowing && nowFitsViewport { return true }

        let collapseShrink = previousContentHeight - newContentHeight
        let wasVeryTall = previousContentHeight >= viewportHeight * veryTallCollapsePreviousViewportRatio
        let shrankByMultipleViewports = collapseShrink >= viewportHeight * veryTallCollapseShrinkViewportRatio
        return wasOverflowing && wasVeryTall && shrankByMultipleViewports
    }

    private func hasValidDimensions(contentHeight: Double, viewportHeight: Double) -> Bool {
        contentHeight.isFinite &&
            viewportHeight.isFinite &&
            contentHeight > 0 &&
            viewportHeight > 0
    }
}
