import CoreGraphics

struct ChatViewportConfiguration: Equatable {
    var spacing: CGFloat = 14
    var bottomPinThreshold: CGFloat = 64
    var topLoadTriggerOffset: CGFloat = 80
    var preservesBottomAnchorForUnderfilledContent: Bool = true
    var showsJumpToLatestButton: Bool = true
}

struct ChatViewportMetrics: Equatable {
    var viewportHeight: CGFloat
    var contentHeight: CGFloat
    var distanceToBottom: CGFloat
    var distanceToTop: CGFloat
    var visibleTopItemID: String? = nil
    var visibleBottomItemID: String? = nil

    var isUnderfilled: Bool { contentHeight <= viewportHeight }
}

enum ChatViewportScrollTarget: Equatable {
    case top(animated: Bool)
    case bottom(animated: Bool)
    case item(id: String, anchor: ChatViewportAnchor, animated: Bool)
}

enum ChatViewportAnchor: Equatable {
    case top
    case center
    case bottom
}

enum ChatViewportCorrection: Equatable {
    case prepend(anchorItemID: String)
    case heightChange(anchorItemID: String?)
}

enum ChatViewportMode: Equatable {
    case initialBottomAnchored
    case pinnedToBottom
    case freeBrowsing
    case programmaticScroll(ChatViewportScrollTarget)
    case correctingAfterDataChange(ChatViewportCorrection)
}

enum ChatViewportDataChange: Equatable {
    case append(count: Int)
    case prepend(count: Int, anchorItemID: String? = nil)
    case replace
    case itemHeightChanged(id: String)
}

enum ChatViewportEvent: Equatable {
    case metricsChanged(ChatViewportMetrics)
    case dataChanged(ChatViewportDataChange)
    case jumpToLatestRequested
    case scrollToTopRequested
    case scrollToItemRequested(id: String, anchor: ChatViewportAnchor)
    case prepareForPrepend(anchorItemID: String)
    case programmaticScrollCompleted
}

struct ChatViewportSnapshot: Equatable {
    var mode: ChatViewportMode
    var isPinnedToBottom: Bool
    var shouldShowJumpToLatest: Bool
    var pendingNewItemCount: Int

    static let initial = ChatViewportSnapshot(
        mode: .initialBottomAnchored,
        isPinnedToBottom: true,
        shouldShowJumpToLatest: false,
        pendingNewItemCount: 0
    )
}

struct ChatViewportStateMachine {
    var configuration: ChatViewportConfiguration

    init(configuration: ChatViewportConfiguration = .init()) {
        self.configuration = configuration
    }

    func reduce(snapshot: ChatViewportSnapshot, event: ChatViewportEvent) -> ChatViewportSnapshot {
        switch event {
        case let .metricsChanged(metrics):
            return reduceMetricsChanged(snapshot: snapshot, metrics: metrics)
        case let .dataChanged(change):
            return reduceDataChanged(snapshot: snapshot, change: change)
        case .jumpToLatestRequested:
            return ChatViewportSnapshot(
                mode: .programmaticScroll(.bottom(animated: true)),
                isPinnedToBottom: true,
                shouldShowJumpToLatest: false,
                pendingNewItemCount: 0
            )
        case .scrollToTopRequested:
            return ChatViewportSnapshot(
                mode: .programmaticScroll(.top(animated: true)),
                isPinnedToBottom: false,
                shouldShowJumpToLatest: configuration.showsJumpToLatestButton,
                pendingNewItemCount: snapshot.pendingNewItemCount
            )
        case let .scrollToItemRequested(id, anchor):
            return ChatViewportSnapshot(
                mode: .programmaticScroll(.item(id: id, anchor: anchor, animated: true)),
                isPinnedToBottom: false,
                shouldShowJumpToLatest: configuration.showsJumpToLatestButton,
                pendingNewItemCount: snapshot.pendingNewItemCount
            )
        case let .prepareForPrepend(anchorItemID):
            return ChatViewportSnapshot(
                mode: .correctingAfterDataChange(.prepend(anchorItemID: anchorItemID)),
                isPinnedToBottom: snapshot.isPinnedToBottom,
                shouldShowJumpToLatest: snapshot.shouldShowJumpToLatest,
                pendingNewItemCount: snapshot.pendingNewItemCount
            )
        case .programmaticScrollCompleted:
            if snapshot.isPinnedToBottom {
                return ChatViewportSnapshot(
                    mode: .pinnedToBottom,
                    isPinnedToBottom: true,
                    shouldShowJumpToLatest: false,
                    pendingNewItemCount: 0
                )
            }
            if case .programmaticScroll = snapshot.mode {
                return ChatViewportSnapshot(
                    mode: .freeBrowsing,
                    isPinnedToBottom: false,
                    shouldShowJumpToLatest: configuration.showsJumpToLatestButton,
                    pendingNewItemCount: snapshot.pendingNewItemCount
                )
            }
            return snapshot
        }
    }

    private func reduceMetricsChanged(snapshot: ChatViewportSnapshot, metrics: ChatViewportMetrics) -> ChatViewportSnapshot {
        let isPinned = metrics.isUnderfilled && configuration.preservesBottomAnchorForUnderfilledContent
            || metrics.distanceToBottom <= configuration.bottomPinThreshold

        if isPinned {
            let mode: ChatViewportMode = metrics.isUnderfilled && configuration.preservesBottomAnchorForUnderfilledContent
                ? .initialBottomAnchored
                : .pinnedToBottom
            return ChatViewportSnapshot(
                mode: mode,
                isPinnedToBottom: true,
                shouldShowJumpToLatest: false,
                pendingNewItemCount: 0
            )
        }

        return ChatViewportSnapshot(
            mode: .freeBrowsing,
            isPinnedToBottom: false,
            shouldShowJumpToLatest: configuration.showsJumpToLatestButton,
            pendingNewItemCount: snapshot.pendingNewItemCount
        )
    }

    private func reduceDataChanged(snapshot: ChatViewportSnapshot, change: ChatViewportDataChange) -> ChatViewportSnapshot {
        switch change {
        case let .append(count):
            if snapshot.isPinnedToBottom {
                return ChatViewportSnapshot(
                    mode: .programmaticScroll(.bottom(animated: true)),
                    isPinnedToBottom: true,
                    shouldShowJumpToLatest: false,
                    pendingNewItemCount: 0
                )
            }
            return ChatViewportSnapshot(
                mode: .freeBrowsing,
                isPinnedToBottom: false,
                shouldShowJumpToLatest: configuration.showsJumpToLatestButton,
                pendingNewItemCount: snapshot.pendingNewItemCount + max(0, count)
            )
        case let .prepend(_, explicitAnchorItemID):
            let correctionAnchorItemID: String?
            if let explicitAnchorItemID {
                correctionAnchorItemID = explicitAnchorItemID
            } else if case let .correctingAfterDataChange(.prepend(anchorItemID)) = snapshot.mode {
                correctionAnchorItemID = anchorItemID
            } else {
                correctionAnchorItemID = nil
            }

            guard let correctionAnchorItemID else { return snapshot }
            return ChatViewportSnapshot(
                mode: .programmaticScroll(.item(id: correctionAnchorItemID, anchor: .top, animated: false)),
                isPinnedToBottom: snapshot.isPinnedToBottom,
                shouldShowJumpToLatest: snapshot.shouldShowJumpToLatest,
                pendingNewItemCount: snapshot.pendingNewItemCount
            )
        case .replace:
            return ChatViewportSnapshot.initial
        case .itemHeightChanged:
            if snapshot.isPinnedToBottom {
                return ChatViewportSnapshot(
                    mode: .programmaticScroll(.bottom(animated: false)),
                    isPinnedToBottom: true,
                    shouldShowJumpToLatest: false,
                    pendingNewItemCount: 0
                )
            }
            return snapshot
        }
    }
}
