import AppKit
import Testing
@testable import ConnorGraphAgentMac

@MainActor
@Suite("Chat Viewport Native Scroll Observer Tests")
struct ChatViewportNativeScrollObserverTests {
    private func makeScrollView(documentView: NSView) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.documentView = documentView
        return scrollView
    }

    @Test func locatesScrollViewWhenObserverViewIsInsideDocumentView() {
        let content = NSView()
        let scrollView = makeScrollView(documentView: content)
        let observerView = NSView()
        content.addSubview(observerView)

        let located = ChatViewportNativeScrollObserver.locateScrollView(containing: observerView)
        #expect(located === scrollView)
    }

    @Test func returnsNilWhenObserverViewIsSiblingOfScrollView() {
        // 复现旧的 .background() 挂载形态：观察者视图与滚动视图是兄弟节点、
        // 不在 documentView 内。此场景必须被识别为“找不到”，否则会静默失效
        // 或错绑外层容器 —— 这正是“滚到顶不加载更早消息”的根因形态。
        let container = NSView()
        let content = NSView()
        let scrollView = makeScrollView(documentView: content)
        let observerView = NSView()
        container.addSubview(scrollView)
        container.addSubview(observerView)

        let located = ChatViewportNativeScrollObserver.locateScrollView(containing: observerView)
        #expect(located == nil)
    }

    @Test func locatesInnerScrollViewWhenNestedInsideOuterScrollView() {
        let innerContent = NSView()
        let innerScrollView = makeScrollView(documentView: innerContent)
        let observerView = NSView()
        innerContent.addSubview(observerView)

        let outerContent = NSView()
        outerContent.addSubview(innerScrollView)
        _ = makeScrollView(documentView: outerContent)

        let located = ChatViewportNativeScrollObserver.locateScrollView(containing: observerView)
        #expect(located === innerScrollView)
    }

    @Test func returnsNilWhenNoScrollViewAncestorExists() {
        let container = NSView()
        let observerView = NSView()
        container.addSubview(observerView)

        #expect(ChatViewportNativeScrollObserver.locateScrollView(containing: observerView) == nil)
    }

    @Test func returnsScrollViewWhenViewIsTheDocumentViewItself() {
        let content = NSView()
        let scrollView = makeScrollView(documentView: content)

        #expect(ChatViewportNativeScrollObserver.locateScrollView(containing: content) === scrollView)
    }

    @Test func flippedDocumentMetricsAtTopAndBottom() {
        let document = CGRect(x: 0, y: 0, width: 800, height: 2_000)

        let atTop = ChatViewportNativeScrollMetrics.calculate(
            documentBounds: document,
            visibleBounds: CGRect(x: 0, y: 0, width: 800, height: 600),
            isFlipped: true
        )
        #expect(atTop.distanceToTop == 0)
        #expect(atTop.distanceToBottom == 1_400)

        let atBottom = ChatViewportNativeScrollMetrics.calculate(
            documentBounds: document,
            visibleBounds: CGRect(x: 0, y: 1_400, width: 800, height: 600),
            isFlipped: true
        )
        #expect(atBottom.distanceToBottom == 0)
        #expect(atBottom.distanceToTop == 1_400)
    }
}
