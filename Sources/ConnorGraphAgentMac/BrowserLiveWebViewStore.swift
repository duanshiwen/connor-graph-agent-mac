import Foundation
import WebKit
import ConnorGraphAppSupport

@MainActor
final class BrowserLiveWebViewStore {
    struct WebViewLease {
        let webView: WKWebView
        let isNewlyCreated: Bool
    }

    struct SnapshotMetadata {
        var scrollX: Double?
        var scrollY: Double?
        var viewportWidth: Double?
        var viewportHeight: Double?
        var contentFingerprint: String?
        var focusedElementHint: String?
    }

    final class WebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        static let selectionMessageName = "connorSelection"

        var onNavigationStateChanged: ((WebNavigationState) -> Void)?
        var onOpenInNewTab: ((URL) -> Void)?
        var onSelectionChanged: ((BrowserSelectionPayload) -> Void)?
        var onRestorationReady: ((WKWebView) -> Void)?

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == Self.selectionMessageName,
                  let json = message.body as? String,
                  let data = json.data(using: .utf8),
                  let payload = try? JSONDecoder().decode(BrowserSelectionPayload.self, from: data)
            else { return }
            DispatchQueue.main.async { self.onSelectionChanged?(payload) }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            publishNavigationState(webView)
            DispatchQueue.main.async { self.onRestorationReady?(webView) }
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { publishNavigationState(webView) }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { publishNavigationState(webView) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { handleNavigationFailure(in: webView, error: error) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { handleNavigationFailure(in: webView, error: error) }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                DispatchQueue.main.async { self.onOpenInNewTab?(url) }
            }
            return nil
        }

        private func handleNavigationFailure(in webView: WKWebView, error: Error) {
            if (error as NSError).code == NSURLErrorCancelled {
                publishNavigationState(webView, isLoadingOverride: false)
                return
            }
            let failedURLString = webView.url?.absoluteString ?? ""
            webView.loadHTMLString(
                BrowserBuiltInPage.errorHTML(failedURLString: failedURLString, message: error.localizedDescription),
                baseURL: BrowserBuiltInPage.webViewBaseURL
            )
            publishNavigationState(webView, errorMessage: error.localizedDescription, isLoadingOverride: false)
        }

        private func publishNavigationState(_ webView: WKWebView, errorMessage: String? = nil, isLoadingOverride: Bool? = nil) {
            let state = WebNavigationState(
                canGoBack: webView.canGoBack,
                canGoForward: webView.canGoForward,
                title: webView.title ?? "",
                url: webView.url?.absoluteString ?? "",
                isLoading: isLoadingOverride ?? webView.isLoading,
                errorMessage: errorMessage
            )
            DispatchQueue.main.async { self.onNavigationStateChanged?(state) }
        }
    }

    private struct Entry {
        var key: BrowserLiveWebViewKey
        var webView: WKWebView
        var coordinator: WebViewCoordinator
        var lastAccessedAt: Date
        var lastVisibleAt: Date?
        var isVisible: Bool
        var restorationStatus: BrowserLiveWebViewRestorationStatus
    }

    private var entries: [BrowserLiveWebViewKey: Entry] = [:]
    private var budgetPolicy = BrowserLiveWebViewBudgetPolicy()
    var onWillEvict: ((BrowserLiveWebViewKey, WKWebView, SnapshotMetadata) -> Void)?

    func leaseWebView(
        key: BrowserLiveWebViewKey,
        initialURLString: String,
        onNavigationStateChanged: @escaping (WebNavigationState) -> Void,
        onOpenInNewTab: @escaping (URL) -> Void,
        onSelectionChanged: @escaping (BrowserSelectionPayload) -> Void,
        onRestorationReady: @escaping (WKWebView) -> Void,
        isVisible: Bool
    ) -> WebViewLease {
        let now = Date()
        if var entry = entries[key] {
            entry.lastAccessedAt = now
            entry.isVisible = isVisible
            if isVisible { entry.lastVisibleAt = now }
            entry.coordinator.onNavigationStateChanged = onNavigationStateChanged
            entry.coordinator.onOpenInNewTab = onOpenInNewTab
            entry.coordinator.onSelectionChanged = onSelectionChanged
            entry.coordinator.onRestorationReady = onRestorationReady
            entries[key] = entry
            return WebViewLease(webView: entry.webView, isNewlyCreated: false)
        }

        let coordinator = WebViewCoordinator()
        coordinator.onNavigationStateChanged = onNavigationStateChanged
        coordinator.onOpenInNewTab = onOpenInNewTab
        coordinator.onSelectionChanged = onSelectionChanged
        coordinator.onRestorationReady = onRestorationReady

        let webView = Self.makeConfiguredWebView(coordinator: coordinator)
        let entry = Entry(
            key: key,
            webView: webView,
            coordinator: coordinator,
            lastAccessedAt: now,
            lastVisibleAt: isVisible ? now : nil,
            isVisible: isVisible,
            restorationStatus: .live
        )
        entries[key] = entry
        return WebViewLease(webView: webView, isNewlyCreated: true)
    }

    func markVisible(_ key: BrowserLiveWebViewKey) {
        guard var entry = entries[key] else { return }
        let now = Date()
        entry.isVisible = true
        entry.lastVisibleAt = now
        entry.lastAccessedAt = now
        entries[key] = entry
    }

    func markHidden(_ key: BrowserLiveWebViewKey) {
        guard var entry = entries[key] else { return }
        entry.isVisible = false
        entry.webView.pauseBrowserMediaPlayback()
        entries[key] = entry
    }

    func markAllHidden() {
        for key in Array(entries.keys) { markHidden(key) }
    }

    func remove(_ key: BrowserLiveWebViewKey) {
        guard let entry = entries.removeValue(forKey: key) else { return }
        cleanup(entry.webView)
    }

    func enforceBudget(processMemoryMegabytes: Int? = nil) {
        let budgetEntries = entries.values.map { entry in
            BrowserLiveWebViewBudgetEntry(
                key: entry.key,
                isVisible: entry.isVisible,
                lastAccessedAt: entry.lastAccessedAt,
                lastVisibleAt: entry.lastVisibleAt,
                restorationStatus: entry.restorationStatus
            )
        }
        let decision = budgetPolicy.evictionDecision(entries: budgetEntries, processMemoryMegabytes: processMemoryMegabytes)
        for key in decision.keysToEvict {
            evict(key)
        }
    }

    private func evict(_ key: BrowserLiveWebViewKey) {
        guard var entry = entries.removeValue(forKey: key) else { return }
        let metadata = snapshotMetadata(from: entry.webView)
        onWillEvict?(key, entry.webView, metadata)
        entry.restorationStatus = .evicted
        cleanup(entry.webView)
    }

    private func cleanup(_ webView: WKWebView) {
        webView.pauseBrowserMediaPlayback()
        if webView.isLoading { webView.stopLoading() }
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: WebViewCoordinator.selectionMessageName)
        webView.removeFromSuperview()
    }

    private func snapshotMetadata(from webView: WKWebView) -> SnapshotMetadata {
        SnapshotMetadata(
            scrollX: nil,
            scrollY: nil,
            viewportWidth: Double(webView.bounds.width),
            viewportHeight: Double(webView.bounds.height),
            contentFingerprint: webView.url?.absoluteString,
            focusedElementHint: nil
        )
    }

    private static func makeConfiguredWebView(coordinator: WebViewCoordinator) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.addUserScript(WKUserScript(source: EmbeddedWebView.selectionObserverScript, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        configuration.userContentController.add(coordinator, name: WebViewCoordinator.selectionMessageName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        webView.allowsBackForwardNavigationGestures = true
        return webView
    }
}

final class BrowserWebViewContainerView: NSView {
    private(set) weak var attachedWebView: WKWebView?

    func attach(_ webView: WKWebView) {
        if attachedWebView === webView { return }
        attachedWebView?.removeFromSuperview()
        attachedWebView = webView
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}
