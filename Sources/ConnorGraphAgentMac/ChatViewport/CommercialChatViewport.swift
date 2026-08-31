import AppKit
import SwiftUI
import os
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

    /// 仅用于“内容不足一屏时贴底”的 minHeight 布局；只在窗口尺寸变化等
    /// 真正改变可见高度的时机写入，避免滚动过程中每帧触发视图重算。
    @State private var viewportHeight: CGFloat = 0
    @State private var didRequestOlderItemsForCurrentTopReach = false
    /// 原生滚动指标存进引用类型容器：滚动时每帧更新但不会使 SwiftUI 失效重排。
    @State private var nativeMetricsBox = NativeMetricsBox()

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
                }
                .defaultScrollAnchor(.bottom)

                .onAppear {
                    controller.replaceDataSetIfNeeded(id: dataSetID, itemCount: items.count, initialAnchor: .bottom)
                }
                .onChange(of: dataSetID) { _, newDataSetID in
                    resetMeasurementsForDataSetReplacement()
                    controller.replaceDataSet(id: newDataSetID, itemCount: items.count, initialAnchor: .bottom)
                }
                .onChange(of: items.count) { _, newCount in
                    controller.replaceDataSetIfNeeded(id: dataSetID, itemCount: newCount, initialAnchor: .bottom)
                    didRequestOlderItemsForCurrentTopReach = false
                    // 用户停在顶部时自动重估：加载完一页后无需再滚动即可继续加载下一页，
                    // 直到 hasOlderItems 为 false（全部历史加载完成）。
                    DispatchQueue.main.async {
                        requestOlderItemsIfNeeded()
                    }
                }
                .onChange(of: isLoadingOlderItems) { wasLoading, isLoading in
                    guard wasLoading, !isLoading else { return }
                    didRequestOlderItemsForCurrentTopReach = false
                    DispatchQueue.main.async {
                        requestOlderItemsIfNeeded()
                    }
                }
                .onChange(of: controller.isResolvingInitialAnchor) { wasResolving, isResolving in
                    guard wasResolving,
                    !isResolving,
                    ChatViewportTopLoadPolicy.shouldReevaluateAfterInitialAnchor(
                        viewportHeight: Double(nativeMetricsBox.latest?.visibleHeight ?? 0),
                        contentHeight: Double(nativeMetricsBox.latest?.documentHeight ?? 0)
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

        // 原生滚动观察者必须放在滚动内容内部：只有这样才能通过 enclosingScrollView
        // 可靠找到聊天自己的 NSScrollView。此前放在 ScrollView 的 .background() 中，
        // 观察者 NSView 与滚动视图是兄弟节点，enclosingScrollView 要么为 nil、
        // 要么错绑外层容器，导致触顶回调永不触发（即“滚到顶不加载更早消息”）。
        ChatViewportNativeScrollObserver { nativeMetrics in
            publishMetrics(nativeMetrics: nativeMetrics)
            requestOlderItemsIfNeeded(
                distanceToTop: nativeMetrics.distanceToTop,
                viewportHeight: nativeMetrics.visibleHeight
            )
        }
        .id(dataSetID)
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)

        ForEach(items) { item in
            rowContent(item)
                .id(rowID(for: item))
        }

        Color.clear
            .frame(height: 1)
            .id(bottomSentinelID)
    }

    private func rowID(for item: Item) -> String {
        dataSetID.namespacedElementID(String(describing: item.id))
    }

    /// 以原生 NSScrollView 指标作为唯一权威源。
    ///
    /// 性能说明：滚动时这里每帧都会被调用，但只更新引用容器（不触发 SwiftUI 重排），
    /// 仅当可见高度真的变化（例如窗口 resize）时才写入 @State。控制器仍逐帧收到
    /// 最新指标，用于贴底判定与“跳到最新”按钮，快照不变时不会重新发布。
    private func publishMetrics(nativeMetrics: ChatViewportNativeScrollMetrics) {
        let previousContentHeight = nativeMetricsBox.latest?.documentHeight
        nativeMetricsBox.latest = nativeMetrics

        if abs(viewportHeight - nativeMetrics.visibleHeight) > 0.5 {
            viewportHeight = nativeMetrics.visibleHeight
        }

        if let previousContentHeight,
           previousContentHeight > 0,
           abs(nativeMetrics.documentHeight - previousContentHeight) > 1,
           controller.isPinnedToBottom {
            controller.notifyDataChange(.itemHeightChanged(id: "viewport-content"))
        }

        controller.updateMetrics(
            ChatViewportMetrics(
                viewportHeight: nativeMetrics.visibleHeight,
                contentHeight: nativeMetrics.documentHeight,
                distanceToBottom: nativeMetrics.distanceToBottom,
                distanceToTop: nativeMetrics.distanceToTop
            )
        )
    }

    private func requestOlderItemsIfNeeded(distanceToTop: CGFloat? = nil, viewportHeight: CGFloat? = nil) {
        let metrics = nativeMetricsBox.latest
        let resolvedDistanceToTop = distanceToTop ?? metrics?.distanceToTop ?? 0
        let resolvedViewportHeight = viewportHeight ?? metrics?.visibleHeight ?? self.viewportHeight
        guard ChatViewportTopLoadPolicy.shouldRequestOlderItems(
            hasOlderItems: hasOlderItems,
            isLoadingOlderItems: isLoadingOlderItems,
            didRequestOlderItemsForCurrentTopReach: didRequestOlderItemsForCurrentTopReach,
            viewportHeight: resolvedViewportHeight,
            distanceToTop: resolvedDistanceToTop,
            topLoadTriggerOffset: configuration.topLoadTriggerOffset,
            isResolvingInitialAnchor: controller.isResolvingInitialAnchor
        ) else {
            if ChatViewportTopLoadPolicy.shouldResetTopReachRequest(
                distanceToTop: resolvedDistanceToTop,
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
        nativeMetricsBox.latest = nil
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

/// 滚动指标引用容器：把每帧更新的数值放在引用类型里，
/// 避免 @State 写入导致滚动过程中视图反复重算。
private final class NativeMetricsBox {
    var latest: ChatViewportNativeScrollMetrics?
}

struct ChatViewportNativeScrollMetrics: Equatable {
    var distanceToTop: CGFloat
    var distanceToBottom: CGFloat
    var visibleHeight: CGFloat
    var documentHeight: CGFloat

    static func calculate(
        documentBounds: CGRect,
        visibleBounds: CGRect,
        isFlipped: Bool
    ) -> Self {
        if isFlipped {
            return Self(
                distanceToTop: max(0, visibleBounds.minY - documentBounds.minY),
                distanceToBottom: max(0, documentBounds.maxY - visibleBounds.maxY),
                visibleHeight: visibleBounds.height,
                documentHeight: documentBounds.height
            )
        }
        return Self(
            distanceToTop: max(0, documentBounds.maxY - visibleBounds.maxY),
            distanceToBottom: max(0, visibleBounds.minY - documentBounds.minY),
            visibleHeight: visibleBounds.height,
            documentHeight: documentBounds.height
        )
    }
}

struct ChatViewportNativeScrollObserver: NSViewRepresentable {
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

    /// 沿视图祖先链向上查找“真正包含该视图”的滚动视图。
    ///
    /// 关键校验：候选 NSScrollView 的 documentView 必须是该视图的祖先，
    /// 即视图位于滚动内容的文档视图内。SwiftUI 把 `.background()` /
    /// `.overlay()` 视图放在 ScrollView 之外（与滚动视图互为兄弟节点），
    /// 此时 view.enclosingScrollView 要么为 nil、要么错绑外层容器；
    /// 本方法会跳过这类无效候选，保证只绑定聊天自己的滚动视图。
    static func locateScrollView(containing view: NSView) -> NSScrollView? {
        var current: NSView? = view
        while let candidate = current {
            if let scrollView = candidate as? NSScrollView,
               let documentView = scrollView.documentView,
               view.isDescendant(of: documentView) {
                return scrollView
            }
            current = candidate.superview
        }
        return nil
    }

    @MainActor
    final class Coordinator {
        var onMetricsChanged: (ChatViewportNativeScrollMetrics) -> Void
        private weak var scrollView: NSScrollView?
        private var boundsObserver: NSObjectProtocol?
        private var isAttachmentScheduled = false
        private var isDismantled = false
        private var retryAttemptsRemaining = 20
        private var lastPublishedMetrics: ChatViewportNativeScrollMetrics?

        private static let logger = Logger(subsystem: "ConnorGraphAgentMac", category: "ChatViewport")
        private static let retryDelay: TimeInterval = 0.05

        init(onMetricsChanged: @escaping (ChatViewportNativeScrollMetrics) -> Void) {
            self.onMetricsChanged = onMetricsChanged
        }

        func attachWhenAvailable(from view: NSView) {
            guard !isDismantled, scrollView == nil, !isAttachmentScheduled else { return }
            scheduleAttachmentAttempt(from: view, delay: 0)
        }

        private func scheduleAttachmentAttempt(from view: NSView, delay: TimeInterval) {
            guard !isDismantled, scrollView == nil else { return }
            isAttachmentScheduled = true
            let attempt: () -> Void = { [weak self, weak view] in
                guard let self else { return }
                self.isAttachmentScheduled = false
                guard !self.isDismantled, let view else { return }
                if let scrollView = ChatViewportNativeScrollObserver.locateScrollView(containing: view) {
                    Self.logger.info("ChatViewport 原生滚动观察者已绑定聊天滚动视图")
                    self.attach(to: scrollView)
                } else if self.retryAttemptsRemaining > 0 {
                    self.retryAttemptsRemaining -= 1
                    self.scheduleAttachmentAttempt(from: view, delay: Self.retryDelay)
                } else {
                    Self.logger.error("ChatViewport 原生滚动观察者挂载失败：多次尝试后仍未找到聊天滚动视图")
                }
            }
            if delay > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { @MainActor @Sendable in
                    attempt()
                }
            } else {
                DispatchQueue.main.async { @MainActor @Sendable in
                    attempt()
                }
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
                    // NSView.boundsDidChange 会在滚动与布局（视图更新事务）期间同步投递，
                    // 直接在这里写入 @State / @Published 会触发
                    // “Modifying state during view update”与
                    // “Publishing changes from within view updates”运行时告警。
                    // 把指标发布调度到下一轮 RunLoop，等当前视图更新事务结束后再执行。
                    DispatchQueue.main.async {
                        self?.publishMetrics()
                    }
                }
            }
            publishMetrics()
        }

        private func publishMetrics() {
            guard let scrollView, let documentView = scrollView.documentView else { return }
            let visibleBounds = scrollView.contentView.bounds
            let documentBounds = documentView.bounds
            // 布局未完成（可见区域或文档高度为 0）时不发布指标，避免误触发触顶加载。
            guard visibleBounds.width > 0, visibleBounds.height > 0, documentBounds.height > 0 else { return }
            let metrics = ChatViewportNativeScrollMetrics.calculate(
                documentBounds: documentBounds,
                visibleBounds: visibleBounds,
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
