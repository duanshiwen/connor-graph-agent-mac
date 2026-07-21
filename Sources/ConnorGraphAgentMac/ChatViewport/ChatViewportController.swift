import Foundation
import os

struct ChatViewportScrollCommand: Equatable, Identifiable {
    let id: UUID
    var target: ChatViewportScrollTarget

    init(id: UUID = UUID(), target: ChatViewportScrollTarget) {
        self.id = id
        self.target = target
    }
}

enum ChatViewportInitialAnchor: Equatable, Sendable {
    case top
    case bottom
    case none
}

@MainActor
final class ChatViewportController: ObservableObject {
    private static let logger = Logger(subsystem: "ConnorGraphAgentMac", category: "ChatViewport")
    @Published private(set) var snapshot: ChatViewportSnapshot
    @Published private(set) var pendingScrollCommand: ChatViewportScrollCommand?
    @Published private(set) var currentDataSetID: ChatViewportDataSetID?
    @Published private(set) var replacementGeneration: Int

    let configuration: ChatViewportConfiguration
    private let stateMachine: ChatViewportStateMachine
    private var pendingInitialAnchor: ChatViewportInitialAnchor?
    private var currentDataSetItemCount: Int
    private var latestMetrics: ChatViewportMetrics?

    init(configuration: ChatViewportConfiguration = .init()) {
        self.configuration = configuration
        self.stateMachine = ChatViewportStateMachine(configuration: configuration)
        self.snapshot = .initial
        self.replacementGeneration = 0
        self.currentDataSetItemCount = 0
    }

    var isPinnedToBottom: Bool { snapshot.isPinnedToBottom }
    var shouldShowJumpToLatest: Bool { snapshot.shouldShowJumpToLatest }
    var pendingNewItemCount: Int { snapshot.pendingNewItemCount }
    var isResolvingInitialAnchor: Bool {
        if pendingInitialAnchor != nil { return true }
        if pendingScrollCommand?.target == .bottom(animated: false) { return true }
        if pendingScrollCommand?.target == .top(animated: false) { return true }
        switch snapshot.mode {
        case .programmaticScroll(.bottom(animated: false)), .programmaticScroll(.top(animated: false)):
            return true
        default:
            return false
        }
    }

    func updateMetrics(_ metrics: ChatViewportMetrics) {
        latestMetrics = metrics
        apply(.metricsChanged(metrics))
        completePendingInitialAnchorIfNeeded()
    }

    func replaceDataSet(
        id: ChatViewportDataSetID,
        itemCount: Int,
        initialAnchor: ChatViewportInitialAnchor = .bottom
    ) {
        currentDataSetID = id
        currentDataSetItemCount = itemCount
        replacementGeneration += 1
        latestMetrics = nil
        pendingInitialAnchor = itemCount > 0 ? initialAnchor : nil
        pendingScrollCommand = nil
        Self.logger.info("Chat viewport dataset replaced dataset=\(id.description, privacy: .public) generation=\(self.replacementGeneration, privacy: .public) itemCount=\(itemCount, privacy: .public) initialAnchor=\(String(describing: initialAnchor), privacy: .public)")
        setSnapshot(.initial)
    }

    func replaceDataSetIfNeeded(
        id: ChatViewportDataSetID,
        itemCount: Int,
        initialAnchor: ChatViewportInitialAnchor = .bottom
    ) {
        let previousItemCount = currentDataSetItemCount
        guard currentDataSetID != id else {
            currentDataSetItemCount = itemCount
            if previousItemCount == 0, itemCount > 0, initialAnchor != .none {
                pendingInitialAnchor = initialAnchor
                Self.logger.debug("Chat viewport same dataset became non-empty dataset=\(id.description, privacy: .public) generation=\(self.replacementGeneration, privacy: .public) itemCount=\(itemCount, privacy: .public) initialAnchor=\(String(describing: initialAnchor), privacy: .public)")
            }
            completePendingInitialAnchorIfNeeded()
            return
        }
        replaceDataSet(id: id, itemCount: itemCount, initialAnchor: initialAnchor)
    }

    func notifyDataChange(_ change: ChatViewportDataChange) {
        if case .replace = change {
            latestMetrics = nil
            pendingInitialAnchor = nil
        }
        apply(.dataChanged(change))
    }

    func jumpToLatest() {
        apply(.jumpToLatestRequested)
    }

    func scrollToBottom(animated: Bool = true) {
        setSnapshot(
            ChatViewportSnapshot(
                mode: .programmaticScroll(.bottom(animated: animated)),
                isPinnedToBottom: true,
                shouldShowJumpToLatest: false,
                pendingNewItemCount: 0
            )
        )
    }

    func scrollToTop() {
        apply(.scrollToTopRequested)
    }

    func scrollToItem(id: String, anchor: ChatViewportAnchor = .center) {
        apply(.scrollToItemRequested(id: id, anchor: anchor))
    }

    func prepareForPrepend(anchorItemID: String) {
        apply(.prepareForPrepend(anchorItemID: anchorItemID))
    }

    func notifyPrepend(count: Int, anchorItemID: String) {
        notifyDataChange(.prepend(count: count, anchorItemID: anchorItemID))
    }

    func completePrependCorrection() {
        completeProgrammaticScroll()
    }

    func completeProgrammaticScroll() {
        apply(.programmaticScrollCompleted)
    }

    func consumePendingScrollCommand() -> ChatViewportScrollCommand? {
        let command = pendingScrollCommand
        pendingScrollCommand = nil
        return command
    }

    func completePendingInitialAnchorIfNeeded() {
        guard let pendingInitialAnchor,
              let latestMetrics,
              latestMetrics.viewportHeight > 0,
              latestMetrics.contentHeight > 0,
              currentDataSetItemCount > 0
        else { return }

        self.pendingInitialAnchor = nil
        Self.logger.debug("Chat viewport completing initial anchor dataset=\(String(describing: self.currentDataSetID?.description), privacy: .public) generation=\(self.replacementGeneration, privacy: .public) anchor=\(String(describing: pendingInitialAnchor), privacy: .public)")
        switch pendingInitialAnchor {
        case .top:
            setSnapshot(
                ChatViewportSnapshot(
                    mode: .programmaticScroll(.top(animated: false)),
                    isPinnedToBottom: false,
                    shouldShowJumpToLatest: configuration.showsJumpToLatestButton,
                    pendingNewItemCount: 0
                )
            )
        case .bottom:
            scrollToBottom(animated: false)
        case .none:
            break
        }
    }

    func requestPendingInitialAnchorNow() {
        guard let pendingInitialAnchor, currentDataSetItemCount > 0 else { return }
        self.pendingInitialAnchor = nil
        switch pendingInitialAnchor {
        case .top:
            setSnapshot(
                ChatViewportSnapshot(
                    mode: .programmaticScroll(.top(animated: false)),
                    isPinnedToBottom: false,
                    shouldShowJumpToLatest: configuration.showsJumpToLatestButton,
                    pendingNewItemCount: 0
                )
            )
        case .bottom:
            scrollToBottom(animated: false)
        case .none:
            break
        }
    }

    private func apply(_ event: ChatViewportEvent) {
        setSnapshot(stateMachine.reduce(snapshot: snapshot, event: event))
    }

    private func setSnapshot(_ nextSnapshot: ChatViewportSnapshot) {
        snapshot = nextSnapshot
        if case let .programmaticScroll(target) = nextSnapshot.mode {
            pendingScrollCommand = ChatViewportScrollCommand(target: target)
        } else {
            pendingScrollCommand = nil
        }
    }
}
