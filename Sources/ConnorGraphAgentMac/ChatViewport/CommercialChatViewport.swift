import AppKit
import SwiftUI
import ConnorGraphAppSupport

struct CommercialChatViewport<Item: Identifiable, RowContent: View>: View where Item.ID: Hashable {
    var dataSetID: ChatViewportDataSetID
    var items: [Item]
    @ObservedObject var controller: ChatViewportController
    var configuration: ChatViewportConfiguration
    var hasOlderItems: Bool
    var isLoadingOlderItems: Bool
    var onTopReached: (() -> Void)?
    var rowContent: (Item) -> RowContent

    @State private var viewportHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var topSentinelMinY: CGFloat = 0
    @State private var bottomSentinelMaxY: CGFloat = 0
    @State private var didRequestOlderItemsForCurrentTopReach = false
    private let coordinateSpaceName = "commercial-chat-viewport-scroll-space"

    private var topSentinelID: String {
        dataSetID.namespacedElementID("commercial-chat-viewport-top-sentinel")
    }

    private var bottomSentinelID: String {
        dataSetID.namespacedElementID("commercial-chat-viewport-bottom-sentinel")
    }

    init(
        dataSetID: ChatViewportDataSetID = ChatViewportDataSetID(namespace: "commercial-chat-viewport", rawID: "default"),
        items: [Item],
        controller: ChatViewportController,
        configuration: ChatViewportConfiguration = .init(),
        hasOlderItems: Bool = false,
        isLoadingOlderItems: Bool = false,
        onTopReached: (() -> Void)? = nil,
        @ViewBuilder rowContent: @escaping (Item) -> RowContent
    ) {
        self.dataSetID = dataSetID
        self.items = items
        self.controller = controller
        self.configuration = configuration
        self.hasOlderItems = hasOlderItems
        self.isLoadingOlderItems = isLoadingOlderItems
        self.onTopReached = onTopReached
        self.rowContent = rowContent
    }

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    contentStack
                    .frame(
                        maxWidth: .infinity,
                        minHeight: configuration.preservesBottomAnchorForUnderfilledContent ? viewportHeight : nil,
                        alignment: configuration.preservesBottomAnchorForUnderfilledContent ? .bottomLeading : .topLeading
                    )
                    .background(
                        GeometryReader { geometry in
                            Color.clear.preference(key: ChatViewportContentHeightKey.self, value: geometry.size.height)
                        }
                    )
                }
                .defaultScrollAnchor(.bottom)
                .coordinateSpace(name: coordinateSpaceName)
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(key: ChatViewportViewportHeightKey.self, value: geometry.size.height)
                    }
                )
                .background(
                    ChatViewportNativeScrollObserver { nativeMetrics in
                        publishMetrics(nativeMetrics: nativeMetrics)
                        requestOlderItemsIfNeeded(distanceToTop: nativeMetrics.distanceToTop)
                    }
                    .id(dataSetID)
                )
                .onPreferenceChange(ChatViewportViewportHeightKey.self) { height in
                    viewportHeight = height
                    publishMetrics()
                }
                .onPreferenceChange(ChatViewportContentHeightKey.self) { height in
                    let previousHeight = contentHeight
                    contentHeight = height
                    if previousHeight > 0,
                       abs(height - previousHeight) > 1,
                       controller.isPinnedToBottom {
                        controller.notifyDataChange(.itemHeightChanged(id: "viewport-content"))
                    }
                    publishMetrics()
                }
                .onPreferenceChange(ChatViewportTopSentinelMinYKey.self) { minY in
                    topSentinelMinY = minY
                    publishMetrics()
                    requestOlderItemsIfNeeded()
                }
                .onPreferenceChange(ChatViewportBottomSentinelMaxYKey.self) { maxY in
                    bottomSentinelMaxY = maxY
                    publishMetrics()
                }
                .onAppear {
                    controller.replaceDataSetIfNeeded(id: dataSetID, itemCount: items.count, initialAnchor: .bottom)
                }
                .onChange(of: dataSetID) { _, newDataSetID in
                    resetMeasurementsForDataSetReplacement()
                    controller.replaceDataSet(id: newDataSetID, itemCount: items.count, initialAnchor: .bottom)
                }
                .onChange(of: items.count) { _, newCount in
                    controller.replaceDataSetIfNeeded(id: dataSetID, itemCount: newCount, initialAnchor: .bottom)
                }
                .onChange(of: isLoadingOlderItems) { wasLoading, isLoading in
                    guard wasLoading, !isLoading else { return }
                    didRequestOlderItemsForCurrentTopReach = false
                }
                .onChange(of: controller.isResolvingInitialAnchor) { wasResolving, isResolving in
                    guard wasResolving,
                    !isResolving,
                    ChatViewportTopLoadPolicy.shouldReevaluateAfterInitialAnchor(
                        viewportHeight: viewportHeight,
                        contentHeight: contentHeight
                    ) else { return }
                    DispatchQueue.main.async {
                        requestOlderItemsIfNeeded()
                    }
                }
                .onChange(of: controller.pendingScrollCommand?.id) { _, _ in
                    consumePendingScrollCommandIfAvailable(proxy: proxy)
                }
                .task(id: controller.pendingScrollCommand?.id) {
                    consumePendingScrollCommandIfAvailable(proxy: proxy)
                }

                if configuration.showsJumpToLatestButton,
                   controller.shouldShowJumpToLatest,
                   !items.isEmpty {
                    ChatJumpToLatestButton(pendingCount: controller.pendingNewItemCount) {
                        controller.jumpToLatest()
                    }
                    .padding(.trailing, AgentChatLayout.jumpToLatestButtonTrailingInset)
                    .padding(.bottom, AgentChatLayout.jumpToLatestButtonBottomInset)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    @ViewBuilder
    private var contentStack: some View {
        switch configuration.contentLayout {
        case .eager:
            VStack(alignment: .leading, spacing: configuration.spacing) {
                viewportContent
            }
        case .lazy:
            LazyVStack(alignment: .leading, spacing: configuration.spacing) {
                viewportContent
            }
        }
    }

    @ViewBuilder
    private var viewportContent: some View {
        Color.clear
            .frame(height: 1)
            .id(topSentinelID)
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: ChatViewportTopSentinelMinYKey.self,
                        value: geometry.frame(in: .named(coordinateSpaceName)).minY
                    )
                }
            )

        ForEach(items) { item in
            rowContent(item)
                .id(rowID(for: item))
        }

        Color.clear
            .frame(height: 1)
            .id(bottomSentinelID)
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: ChatViewportBottomSentinelMaxYKey.self,
                        value: geometry.frame(in: .named(coordinateSpaceName)).maxY
                    )
                }
            )
    }

    private func rowID(for item: Item) -> String {
        dataSetID.namespacedElementID(String(describing: item.id))
    }

    private func publishMetrics(nativeMetrics: ChatViewportNativeScrollMetrics? = nil) {
        guard viewportHeight > 0 else { return }
        let distanceToBottom = nativeMetrics?.distanceToBottom
            ?? max(0, bottomSentinelMaxY - viewportHeight)
        let distanceToTop = nativeMetrics?.distanceToTop
            ?? max(0, -topSentinelMinY)
        controller.updateMetrics(
            ChatViewportMetrics(
                viewportHeight: viewportHeight,
                contentHeight: contentHeight,
                distanceToBottom: distanceToBottom,
                distanceToTop: distanceToTop
            )
        )
    }

    private func requestOlderItemsIfNeeded(distanceToTop: CGFloat? = nil) {
        let distanceToTop = distanceToTop ?? max(0, -topSentinelMinY)
        guard ChatViewportTopLoadPolicy.shouldRequestOlderItems(
            hasOlderItems: hasOlderItems,
            isLoadingOlderItems: isLoadingOlderItems,
            didRequestOlderItemsForCurrentTopReach: didRequestOlderItemsForCurrentTopReach,
            viewportHeight: viewportHeight,
            distanceToTop: distanceToTop,
            topLoadTriggerOffset: configuration.topLoadTriggerOffset,
            isResolvingInitialAnchor: controller.isResolvingInitialAnchor
        ) else {
            if ChatViewportTopLoadPolicy.shouldResetTopReachRequest(
                distanceToTop: distanceToTop,
                topLoadTriggerOffset: configuration.topLoadTriggerOffset
            ) {
                didRequestOlderItemsForCurrentTopReach = false
            }
            return
        }

        didRequestOlderItemsForCurrentTopReach = true
        onTopReached?()
    }

    private func consumePendingScrollCommandIfAvailable(proxy: ScrollViewProxy) {
        guard let command = controller.consumePendingScrollCommand() else { return }
        DispatchQueue.main.async {
            perform(command, proxy: proxy)
        }
    }

    private func resetMeasurementsForDataSetReplacement() {
        viewportHeight = 0
        contentHeight = 0
        topSentinelMinY = 0
        bottomSentinelMaxY = 0
        didRequestOlderItemsForCurrentTopReach = false
    }

    private func scrollToLatestRenderedItem(proxy: ScrollViewProxy, animated: Bool) {
        let operation = {
            if let lastItem = items.last {
                proxy.scrollTo(rowID(for: lastItem), anchor: .bottom)
            } else {
                proxy.scrollTo(bottomSentinelID, anchor: .bottom)
            }
        }

        if animated {
            withAnimation(.easeOut(duration: 0.22), operation)
        } else {
            operation()
        }
    }

    private func perform(_ command: ChatViewportScrollCommand, proxy: ScrollViewProxy) {
        let operation = {
            switch command.target {
            case .top:
                proxy.scrollTo(topSentinelID, anchor: .top)
            case .bottom:
                scrollToLatestRenderedItem(proxy: proxy, animated: false)
            case let .item(id, anchor, _):
                proxy.scrollTo(id, anchor: anchor.unitPoint)
            }
        }

        if command.target.isAnimated {
            withAnimation(.easeOut(duration: 0.22), operation)
        } else {
            operation()
        }

        DispatchQueue.main.async {
            controller.completeProgrammaticScroll()
        }
    }
}

struct ChatViewportNativeScrollMetrics: Equatable {
    var distanceToTop: CGFloat
    var distanceToBottom: CGFloat

    static func calculate(
        documentBounds: CGRect,
        visibleBounds: CGRect,
        isFlipped: Bool
    ) -> Self {
        if isFlipped {
            return Self(
                distanceToTop: max(0, visibleBounds.minY - documentBounds.minY),
                distanceToBottom: max(0, documentBounds.maxY - visibleBounds.maxY)
            )
        }
        return Self(
            distanceToTop: max(0, documentBounds.maxY - visibleBounds.maxY),
            distanceToBottom: max(0, visibleBounds.minY - documentBounds.minY)
        )
    }
}

private struct ChatViewportNativeScrollObserver: NSViewRepresentable {
    var onMetricsChanged: (ChatViewportNativeScrollMetrics) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onMetricsChanged: onMetricsChanged)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attachWhenAvailable(from: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.onMetricsChanged = onMetricsChanged
        context.coordinator.attachWhenAvailable(from: view)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator {
        var onMetricsChanged: (ChatViewportNativeScrollMetrics) -> Void
        private weak var scrollView: NSScrollView?
        private var boundsObserver: NSObjectProtocol?
        private var isAttachmentScheduled = false
        private var isDismantled = false
        private var lastPublishedMetrics: ChatViewportNativeScrollMetrics?

        init(onMetricsChanged: @escaping (ChatViewportNativeScrollMetrics) -> Void) {
            self.onMetricsChanged = onMetricsChanged
        }

        func attachWhenAvailable(from view: NSView) {
            guard scrollView == nil, !isAttachmentScheduled, !isDismantled else { return }
            isAttachmentScheduled = true
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self else { return }
                isAttachmentScheduled = false
                guard !isDismantled, let scrollView = view?.enclosingScrollView else { return }
                attach(to: scrollView)
            }
        }

        func detach() {
            isDismantled = true
            removeObservation()
        }

        private func removeObservation() {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
            boundsObserver = nil
            scrollView = nil
            lastPublishedMetrics = nil
        }

        private func attach(to scrollView: NSScrollView) {
            guard self.scrollView !== scrollView else { return }
            removeObservation()
            self.scrollView = scrollView
            scrollView.contentView.postsBoundsChangedNotifications = true
            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.publishMetrics()
                }
            }
            publishMetrics()
        }

        private func publishMetrics() {
            guard let scrollView, let documentView = scrollView.documentView else { return }
            let metrics = ChatViewportNativeScrollMetrics.calculate(
                documentBounds: documentView.bounds,
                visibleBounds: scrollView.contentView.bounds,
                isFlipped: documentView.isFlipped
            )
            guard metrics != lastPublishedMetrics else { return }
            lastPublishedMetrics = metrics
            onMetricsChanged(metrics)
        }
    }
}

private extension ChatViewportScrollTarget {
    var isAnimated: Bool {
        switch self {
        case let .top(animated), let .bottom(animated): return animated
        case let .item(_, _, animated): return animated
        }
    }
}

private extension ChatViewportAnchor {
    var unitPoint: UnitPoint {
        switch self {
        case .top: return .top
        case .center: return .center
        case .bottom: return .bottom
        }
    }
}

private struct ChatViewportTopSentinelMinYKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct ChatViewportViewportHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct ChatViewportContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct ChatViewportBottomSentinelMaxYKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
