import Foundation

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
        guard contentHeight.isFinite,
              viewportHeight.isFinite,
              contentHeight > 0,
              viewportHeight > 0
        else { return .doNotScroll }

        return contentHeight > viewportHeight + overflowTolerance ? .scrollToBottom : .scrollToTop
    }
}
