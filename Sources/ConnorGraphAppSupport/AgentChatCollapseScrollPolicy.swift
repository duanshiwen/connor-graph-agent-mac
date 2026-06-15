import Foundation

public enum AgentChatCollapseScrollSchedule {
    public static let decisionDelays: [TimeInterval] = [0.05, 0.2, 0.35]
}

public struct AgentChatCollapseScrollPolicy: Sendable {
    public enum Decision: Equatable, Sendable {
        case scrollToTop
        case scrollToBottom
        case doNotScroll
    }

    public var overflowTolerance: Double

    public init(overflowTolerance: Double = 1) {
        self.overflowTolerance = overflowTolerance
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

        return contentHeight > viewportHeight + overflowTolerance ? .doNotScroll : .scrollToTop
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
        return wasOverflowing && nowFitsViewport
    }

    private func hasValidDimensions(contentHeight: Double, viewportHeight: Double) -> Bool {
        contentHeight.isFinite &&
            viewportHeight.isFinite &&
            contentHeight > 0 &&
            viewportHeight > 0
    }
}
