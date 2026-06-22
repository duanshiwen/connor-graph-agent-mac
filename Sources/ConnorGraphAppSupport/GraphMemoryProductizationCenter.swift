import Foundation

public struct GraphMemoryDashboardSummary: Codable, Sendable, Equatable {
    public var pendingCandidateCount: Int
    public var openHoldCount: Int
    public var recentChangeCount: Int
    public var contextItemCount: Int
    public var feedbackSignalCount: Int
    public var stagedBundleCount: Int
    public var distillationCandidateCount: Int
    public var contextReady: Bool
    public var ingestionReady: Bool
    public var distillationReady: Bool
    public var reviewReady: Bool

    public init(
        pendingCandidateCount: Int,
        openHoldCount: Int,
        recentChangeCount: Int,
        contextItemCount: Int = 0,
        feedbackSignalCount: Int = 0,
        stagedBundleCount: Int = 0,
        distillationCandidateCount: Int = 0,
        contextReady: Bool = false,
        ingestionReady: Bool = false,
        distillationReady: Bool = false,
        reviewReady: Bool = true
    ) {
        self.pendingCandidateCount = pendingCandidateCount
        self.openHoldCount = openHoldCount
        self.recentChangeCount = recentChangeCount
        self.contextItemCount = contextItemCount
        self.feedbackSignalCount = feedbackSignalCount
        self.stagedBundleCount = stagedBundleCount
        self.distillationCandidateCount = distillationCandidateCount
        self.contextReady = contextReady
        self.ingestionReady = ingestionReady
        self.distillationReady = distillationReady
        self.reviewReady = reviewReady
    }
}

public struct GraphMemoryDashboard: Sendable, Equatable {
    public var summary: GraphMemoryDashboardSummary
    public var cards: [String]

    public init(summary: GraphMemoryDashboardSummary, cards: [String] = []) {
        self.summary = summary
        self.cards = cards
    }
}
