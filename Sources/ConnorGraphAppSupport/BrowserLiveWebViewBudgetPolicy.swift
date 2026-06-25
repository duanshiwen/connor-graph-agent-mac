import Foundation

public struct BrowserLiveWebViewKey: Hashable, Codable, Sendable, Equatable {
    public var sessionID: String
    public var tabID: UUID

    public init(sessionID: String, tabID: UUID) {
        self.sessionID = sessionID
        self.tabID = tabID
    }
}

public enum BrowserLiveWebViewRestorationStatus: String, Codable, Sendable, Equatable {
    case live
    case evicted
    case restoredFromSnapshot
    case restoreFailed
}

public struct BrowserLiveWebViewBudgetEntry: Codable, Sendable, Equatable {
    public var key: BrowserLiveWebViewKey
    public var isVisible: Bool
    public var lastAccessedAt: Date
    public var lastVisibleAt: Date?
    public var restorationStatus: BrowserLiveWebViewRestorationStatus
    public var estimatedWeight: Int

    public init(
        key: BrowserLiveWebViewKey,
        isVisible: Bool,
        lastAccessedAt: Date,
        lastVisibleAt: Date? = nil,
        restorationStatus: BrowserLiveWebViewRestorationStatus = .live,
        estimatedWeight: Int = 1
    ) {
        self.key = key
        self.isVisible = isVisible
        self.lastAccessedAt = lastAccessedAt
        self.lastVisibleAt = lastVisibleAt
        self.restorationStatus = restorationStatus
        self.estimatedWeight = max(1, estimatedWeight)
    }
}

public struct BrowserLiveWebViewBudgetConfig: Codable, Sendable, Equatable {
    public var maxHiddenLiveWebViews: Int
    public var minHiddenLiveWebViewsToKeep: Int
    public var softProcessMemoryLimitMegabytes: Int?

    public init(
        maxHiddenLiveWebViews: Int = 4,
        minHiddenLiveWebViewsToKeep: Int = 1,
        softProcessMemoryLimitMegabytes: Int? = 1024
    ) {
        self.maxHiddenLiveWebViews = max(0, maxHiddenLiveWebViews)
        self.minHiddenLiveWebViewsToKeep = max(0, minHiddenLiveWebViewsToKeep)
        self.softProcessMemoryLimitMegabytes = softProcessMemoryLimitMegabytes
    }
}

public enum BrowserLiveWebViewEvictionReason: String, Codable, Sendable, Equatable {
    case withinBudget
    case hiddenCountExceeded
    case memoryPressure
}

public struct BrowserLiveWebViewEvictionDecision: Codable, Sendable, Equatable {
    public var keysToEvict: [BrowserLiveWebViewKey]
    public var reason: BrowserLiveWebViewEvictionReason

    public init(keysToEvict: [BrowserLiveWebViewKey] = [], reason: BrowserLiveWebViewEvictionReason = .withinBudget) {
        self.keysToEvict = keysToEvict
        self.reason = reason
    }
}

public struct BrowserLiveWebViewBudgetPolicy: Sendable, Equatable {
    public var config: BrowserLiveWebViewBudgetConfig

    public init(config: BrowserLiveWebViewBudgetConfig = .init()) {
        self.config = config
    }

    public func evictionDecision(
        entries: [BrowserLiveWebViewBudgetEntry],
        processMemoryMegabytes: Int?
    ) -> BrowserLiveWebViewEvictionDecision {
        let hiddenEntries = entries.filter { !$0.isVisible }
        let sortedHiddenEntries = hiddenEntries.sorted(by: Self.evictionSort)

        let hiddenOverflow = max(0, hiddenEntries.count - config.maxHiddenLiveWebViews)
        if hiddenOverflow > 0 {
            let evictableCount = max(0, hiddenEntries.count - config.minHiddenLiveWebViewsToKeep)
            let count = min(hiddenOverflow, evictableCount)
            return BrowserLiveWebViewEvictionDecision(
                keysToEvict: Array(sortedHiddenEntries.prefix(count)).map(\.key),
                reason: count > 0 ? .hiddenCountExceeded : .withinBudget
            )
        }

        if let limit = config.softProcessMemoryLimitMegabytes,
           let processMemoryMegabytes,
           processMemoryMegabytes > limit,
           hiddenEntries.count > config.minHiddenLiveWebViewsToKeep,
           let first = sortedHiddenEntries.first {
            return BrowserLiveWebViewEvictionDecision(keysToEvict: [first.key], reason: .memoryPressure)
        }

        return BrowserLiveWebViewEvictionDecision()
    }

    private static func evictionSort(_ lhs: BrowserLiveWebViewBudgetEntry, _ rhs: BrowserLiveWebViewBudgetEntry) -> Bool {
        let lhsRestorablePriority = lhs.restorationStatus == .restoredFromSnapshot ? 0 : 1
        let rhsRestorablePriority = rhs.restorationStatus == .restoredFromSnapshot ? 0 : 1
        if lhsRestorablePriority != rhsRestorablePriority {
            return lhsRestorablePriority < rhsRestorablePriority
        }
        if lhs.lastAccessedAt != rhs.lastAccessedAt {
            return lhs.lastAccessedAt < rhs.lastAccessedAt
        }
        return lhs.key.tabID.uuidString < rhs.key.tabID.uuidString
    }
}
