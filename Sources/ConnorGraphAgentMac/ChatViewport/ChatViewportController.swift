import Foundation

struct ChatViewportScrollCommand: Equatable, Identifiable {
    let id: UUID
    var target: ChatViewportScrollTarget

    init(id: UUID = UUID(), target: ChatViewportScrollTarget) {
        self.id = id
        self.target = target
    }
}

@MainActor
final class ChatViewportController: ObservableObject {
    @Published private(set) var snapshot: ChatViewportSnapshot
    @Published private(set) var pendingScrollCommand: ChatViewportScrollCommand?

    let configuration: ChatViewportConfiguration
    private let stateMachine: ChatViewportStateMachine

    init(configuration: ChatViewportConfiguration = .init()) {
        self.configuration = configuration
        self.stateMachine = ChatViewportStateMachine(configuration: configuration)
        self.snapshot = .initial
    }

    var isPinnedToBottom: Bool { snapshot.isPinnedToBottom }
    var shouldShowJumpToLatest: Bool { snapshot.shouldShowJumpToLatest }
    var pendingNewItemCount: Int { snapshot.pendingNewItemCount }

    func updateMetrics(_ metrics: ChatViewportMetrics) {
        apply(.metricsChanged(metrics))
    }

    func notifyDataChange(_ change: ChatViewportDataChange) {
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
