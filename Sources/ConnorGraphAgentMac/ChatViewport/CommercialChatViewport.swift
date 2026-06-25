import SwiftUI

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
                    LazyVStack(alignment: .leading, spacing: configuration.spacing) {
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
                .coordinateSpace(name: coordinateSpaceName)
                .id(dataSetID)
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(key: ChatViewportViewportHeightKey.self, value: geometry.size.height)
                    }
                )
                .onPreferenceChange(ChatViewportViewportHeightKey.self) { height in
                    viewportHeight = height
                    publishMetrics()
                }
                .onPreferenceChange(ChatViewportContentHeightKey.self) { height in
                    contentHeight = height
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
                    didRequestOlderItemsForCurrentTopReach = false
                    controller.replaceDataSet(id: newDataSetID, itemCount: items.count, initialAnchor: .bottom)
                }
                .onChange(of: items.count) { _, newCount in
                    controller.replaceDataSetIfNeeded(id: dataSetID, itemCount: newCount, initialAnchor: .bottom)
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

    private func rowID(for item: Item) -> String {
        dataSetID.namespacedElementID(String(describing: item.id))
    }

    private func publishMetrics() {
        guard viewportHeight > 0 else { return }
        let distanceToBottom = max(0, bottomSentinelMaxY - viewportHeight)
        let distanceToTop = max(0, -topSentinelMinY)
        controller.updateMetrics(
            ChatViewportMetrics(
                viewportHeight: viewportHeight,
                contentHeight: contentHeight,
                distanceToBottom: distanceToBottom,
                distanceToTop: distanceToTop
            )
        )
    }

    private func requestOlderItemsIfNeeded() {
        let distanceToTop = max(0, -topSentinelMinY)
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
        perform(command, proxy: proxy)
    }

    private func perform(_ command: ChatViewportScrollCommand, proxy: ScrollViewProxy) {
        let operation = {
            switch command.target {
            case .top:
                proxy.scrollTo(topSentinelID, anchor: .top)
            case .bottom:
                proxy.scrollTo(bottomSentinelID, anchor: .bottom)
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
