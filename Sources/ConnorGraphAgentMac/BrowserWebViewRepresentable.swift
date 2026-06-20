import SwiftUI
import AppKit
import WebKit
import ConnorGraphCore
import ConnorGraphAppSupport

struct EmbeddedWebView: NSViewRepresentable {
    var initialURLString: String
    var onWebViewCreated: (WKWebView) -> Void
    var onNavigationStateChanged: (WebNavigationState) -> Void
    var onOpenInNewTab: (URL) -> Void
    var onSelectionChanged: (BrowserSelectionPayload) -> Void
    var onMediaSnapshotChanged: (BrowserMediaSourceSnapshot) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onNavigationStateChanged: onNavigationStateChanged,
            onOpenInNewTab: onOpenInNewTab,
            onSelectionChanged: onSelectionChanged,
            onMediaSnapshotChanged: onMediaSnapshotChanged
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.addUserScript(WKUserScript(source: Self.selectionObserverScript, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        configuration.userContentController.addUserScript(WKUserScript(source: Self.mediaObserverScript, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        configuration.userContentController.add(context.coordinator, name: Coordinator.selectionMessageName)
        configuration.userContentController.add(context.coordinator, name: Coordinator.mediaMessageName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.webView = webView
        onWebViewCreated(webView)

        webView.loadBrowserURLString(initialURLString)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.onNavigationStateChanged = onNavigationStateChanged
        context.coordinator.onOpenInNewTab = onOpenInNewTab
        context.coordinator.onSelectionChanged = onSelectionChanged
        context.coordinator.onMediaSnapshotChanged = onMediaSnapshotChanged
    }

    static let mediaObserverScript = """
    (function() {
      if (window.__connorMediaObserverInstalled) { return; }
      window.__connorMediaObserverInstalled = true;

      function attr(selector, name) {
        var element = document.querySelector(selector);
        return element ? (element.getAttribute(name) || '') : '';
      }

      function mediaElements() {
        return Array.prototype.slice.call(document.querySelectorAll('video,audio')).map(function(element, index) {
          var current = element.currentSrc || element.src || '';
          if (!current && element.querySelector('source')) { current = element.querySelector('source').src || ''; }
          return {
            id: (element.id || element.getAttribute('data-connor-media-id') || (element.tagName.toLowerCase() + '-' + index)),
            kind: element.tagName.toLowerCase(),
            sourceURLString: current || null,
            durationSeconds: isFinite(element.duration) ? element.duration : null,
            isPaused: !!element.paused,
            isMuted: !!element.muted,
            readyState: element.readyState
          };
        });
      }

      function openGraphMedia() {
        var candidates = [];
        var ogVideo = attr('meta[property="og:video"]', 'content') || attr('meta[property="og:video:url"]', 'content');
        var ogAudio = attr('meta[property="og:audio"]', 'content') || attr('meta[property="og:audio:url"]', 'content');
        var twitterPlayer = attr('meta[name="twitter:player"]', 'content');
        [ogVideo, ogAudio, twitterPlayer].forEach(function(value, index) {
          if (value) { candidates.push({ id: 'meta-' + index, sourceURLString: value, type: index === 1 ? 'audio' : 'video' }); }
        });
        return candidates;
      }

      var lastPayload = '';
      function reportMedia() {
        try {
          var payload = {
            pageURLString: location.href || '',
            pageTitle: document.title || '',
            detectedAt: new Date().toISOString(),
            mediaElements: mediaElements(),
            openGraphMedia: openGraphMedia(),
            canonicalURLString: attr('link[rel="canonical"]', 'href') || null,
            userVisibleSelection: null
          };
          var encoded = JSON.stringify(payload);
          if (encoded === lastPayload) { return; }
          lastPayload = encoded;
          window.webkit.messageHandlers.connorMedia.postMessage(encoded);
        } catch (error) {}
      }

      reportMedia();
      document.addEventListener('play', reportMedia, true);
      document.addEventListener('pause', reportMedia, true);
      document.addEventListener('loadedmetadata', reportMedia, true);
      setTimeout(reportMedia, 500);
      setTimeout(reportMedia, 2000);
    })();
    """

    static let selectionObserverScript = """
    (function() {
      if (window.__connorSelectionObserverInstalled) { return; }
      window.__connorSelectionObserverInstalled = true;

      function readablePageText() {
        var candidates = [];
        var article = document.querySelector('article');
        if (article && article.innerText) { candidates.push(article.innerText); }
        var main = document.querySelector('main');
        if (main && main.innerText) { candidates.push(main.innerText); }
        if (document.body && document.body.innerText) { candidates.push(document.body.innerText); }
        var text = candidates.find(function(value) { return value && value.trim().length > 0; }) || '';
        return text.replace(/[ \\t]+/g, ' ').replace(/\\n{3,}/g, '\\n\\n').trim().slice(0, 60000);
      }

      var lastKey = '';
      var timer = null;
      function reportSelection() {
        clearTimeout(timer);
        timer = setTimeout(function() {
          try {
            var selection = window.getSelection ? window.getSelection() : null;
            var text = selection ? selection.toString().trim() : '';
            if (!selection || !text || selection.rangeCount === 0) { return; }
            var rect = selection.getRangeAt(0).getBoundingClientRect();
            if (!rect || (rect.width === 0 && rect.height === 0)) { return; }
            var key = text + '|' + location.href + '|' + Math.round(rect.x) + '|' + Math.round(rect.y);
            if (key === lastKey) { return; }
            lastKey = key;
            window.webkit.messageHandlers.connorSelection.postMessage(JSON.stringify({
              pageURL: location.href || '',
              pageTitle: document.title || '',
              pageText: readablePageText(),
              selectedText: text,
              rect: { x: rect.x, y: rect.y, width: rect.width, height: rect.height }
            }));
          } catch (error) {}
        }, 80);
      }

      document.addEventListener('selectionchange', reportSelection, true);
      document.addEventListener('mouseup', reportSelection, true);
      document.addEventListener('keyup', reportSelection, true);
    })();
    """

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        static let selectionMessageName = "connorSelection"
        static let mediaMessageName = "connorMedia"
        weak var webView: WKWebView?
        var onNavigationStateChanged: (WebNavigationState) -> Void
        var onOpenInNewTab: (URL) -> Void
        var onSelectionChanged: (BrowserSelectionPayload) -> Void
        var onMediaSnapshotChanged: (BrowserMediaSourceSnapshot) -> Void

        init(
            onNavigationStateChanged: @escaping (WebNavigationState) -> Void,
            onOpenInNewTab: @escaping (URL) -> Void,
            onSelectionChanged: @escaping (BrowserSelectionPayload) -> Void,
            onMediaSnapshotChanged: @escaping (BrowserMediaSourceSnapshot) -> Void
        ) {
            self.onNavigationStateChanged = onNavigationStateChanged
            self.onOpenInNewTab = onOpenInNewTab
            self.onSelectionChanged = onSelectionChanged
            self.onMediaSnapshotChanged = onMediaSnapshotChanged
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let json = message.body as? String,
                  let data = json.data(using: .utf8)
            else { return }
            if message.name == Self.selectionMessageName,
               let payload = try? JSONDecoder().decode(BrowserSelectionPayload.self, from: data) {
                DispatchQueue.main.async { self.onSelectionChanged(payload) }
                return
            }
            if message.name == Self.mediaMessageName {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                if let payload = try? decoder.decode(BrowserMediaSourceSnapshot.self, from: data) {
                    DispatchQueue.main.async { self.onMediaSnapshotChanged(payload) }
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { publishNavigationState(webView) }
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { publishNavigationState(webView) }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { publishNavigationState(webView) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { handleNavigationFailure(in: webView, error: error) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { handleNavigationFailure(in: webView, error: error) }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                DispatchQueue.main.async { self.onOpenInNewTab(url) }
            }
            return nil
        }

        private func handleNavigationFailure(in webView: WKWebView, error: Error) {
            if (error as NSError).code == NSURLErrorCancelled {
                publishNavigationState(webView, isLoadingOverride: false)
                return
            }
            showErrorPage(in: webView, error: error)
        }

        private func showErrorPage(in webView: WKWebView, error: Error) {
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
            DispatchQueue.main.async { self.onNavigationStateChanged(state) }
        }
    }
}

extension WKWebView {
    func loadBrowserURLString(_ urlString: String) {
        if urlString == BrowserBuiltInPage.blankURLString || urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            loadHTMLString(BrowserBuiltInPage.blankHTML, baseURL: BrowserBuiltInPage.webViewBaseURL)
            return
        }
        guard let url = URL(string: urlString) else {
            loadHTMLString(BrowserBuiltInPage.errorHTML(failedURLString: urlString, message: "Invalid URL"), baseURL: BrowserBuiltInPage.webViewBaseURL)
            return
        }
        load(URLRequest(url: url))
    }
}

extension UUID {
    static func nameUUIDFromBytes(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "00000000-0000-4000-8000-%012llx", hash & 0x0000_FFFF_FFFF_FFFF)
    }
}
